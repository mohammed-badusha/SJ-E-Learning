begin;

-- One short catalog revision per subject avoids scanning the whole question
-- bank on every match. The player bag is reconciled only after a catalog edit
-- or when its unused tail has been exhausted.
create table sj_private.question_pool_versions (
 category_id uuid primary key references public.categories(id) on delete cascade,
 revision bigint not null default 0
);
insert into sj_private.question_pool_versions(category_id)
select id from public.categories;
alter table sj_private.question_pool_versions enable row level security;

create function sj_private.bump_question_pool() returns trigger
language plpgsql security definer set search_path='' as $$
declare old_category uuid; new_category uuid;
begin
 if TG_TABLE_NAME='questions' then
  if TG_OP='UPDATE' and new.status is not distinct from old.status
     and new.category_id is not distinct from old.category_id then return new; end if;
  if TG_OP<>'INSERT' then old_category=old.category_id; end if;
  if TG_OP<>'DELETE' then new_category=new.category_id; end if;
 elsif TG_TABLE_NAME='question_options' then
  if TG_OP<>'INSERT' then
   select category_id into old_category from public.questions where id=old.question_id;
  end if;
  if TG_OP<>'DELETE' then
   select category_id into new_category from public.questions where id=new.question_id;
  end if;
 else
  if TG_OP='UPDATE' and new.is_active is not distinct from old.is_active then return new; end if;
  new_category=new.id;
 end if;
 if old_category is not null then
  insert into sj_private.question_pool_versions(category_id,revision) values(old_category,1)
  on conflict(category_id) do update set revision=sj_private.question_pool_versions.revision+1;
 end if;
 if new_category is not null and new_category is distinct from old_category then
  insert into sj_private.question_pool_versions(category_id,revision) values(new_category,1)
  on conflict(category_id) do update set revision=sj_private.question_pool_versions.revision+1;
 end if;
 return case when TG_OP='DELETE' then old else new end;
end $$;
create trigger questions_pool_changed after insert or update of status,category_id or delete on public.questions
for each row execute function sj_private.bump_question_pool();
create trigger options_pool_changed after insert or update or delete on public.question_options
for each row execute function sj_private.bump_question_pool();
create trigger categories_pool_changed after insert or update of is_active on public.categories
for each row execute function sj_private.bump_question_pool();

-- Four bounded rows per learner, one per required battle subject. The used
-- prefix remains in the same array until that subject's cycle completes.
create table public.player_question_cycles (
 user_id uuid not null references public.profiles(id) on delete cascade,
 category_id uuid not null references public.categories(id) on delete cascade,
 question_ids uuid[] not null default '{}'::uuid[],
 next_index integer not null default 0,
 catalog_revision bigint not null default -1,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 primary key(user_id,category_id),
 check(next_index>=0 and next_index<=cardinality(question_ids))
);
alter table public.player_question_cycles enable row level security;
revoke all on public.player_question_cycles from public,anon,authenticated;

create or replace function sj_private.clear_deleted_player_cycle() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 delete from public.player_bot_cycles where user_id=new.id;
 delete from public.player_question_cycles where user_id=new.id;
 return new;
end $$;

create function sj_private.prepare_question_cycle(player_id uuid, subject_id uuid)
returns public.player_question_cycles language plpgsql security definer set search_path='' as $$
declare cycle public.player_question_cycles; active_ids uuid[]; used_ids uuid[]; remaining_ids uuid[];
        new_id uuid; insert_at int; slot int; current_revision bigint;
begin
 insert into sj_private.question_pool_versions(category_id) values(subject_id) on conflict do nothing;
 select revision into current_revision from sj_private.question_pool_versions
 where category_id=subject_id for share;
 insert into public.player_question_cycles(user_id,category_id) values(player_id,subject_id)
 on conflict do nothing;
 select * into cycle from public.player_question_cycles
 where user_id=player_id and category_id=subject_id for update;
 if cycle.catalog_revision=current_revision and cycle.next_index<cardinality(cycle.question_ids) then
  return cycle;
 end if;
 select coalesce(array_agg(q.id order by q.id),'{}'::uuid[]) into active_ids
 from public.questions q join public.categories c on c.id=q.category_id and c.is_active
 where q.category_id=subject_id and q.status='published'
 and (select count(*) from public.question_options o where o.question_id=q.id)=4;
 if cardinality(active_ids)=0 then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;

 select coalesce(array_agg(id order by ord) filter(where ord<=cycle.next_index),'{}'::uuid[]),
        coalesce(array_agg(id order by ord) filter(where ord>cycle.next_index and id=any(active_ids)),'{}'::uuid[])
 into used_ids,remaining_ids from unnest(cycle.question_ids) with ordinality saved(id,ord);
 slot=cardinality(used_ids);
 cycle.question_ids=used_ids||remaining_ids;
 -- Insert new questions at random positions in the unused tail. A disabled
 -- question in the used prefix stays used if it is later re-enabled.
 for new_id in select id from unnest(active_ids) available(id)
               where not id=any(cycle.question_ids) order by id loop
  insert_at=slot+floor(random()*(cardinality(cycle.question_ids)-slot+1))::int;
  cycle.question_ids=coalesce(cycle.question_ids[1:insert_at],'{}'::uuid[])||array[new_id]||
                     coalesce(cycle.question_ids[insert_at+1:cardinality(cycle.question_ids)],'{}'::uuid[]);
 end loop;
 if cardinality(cycle.question_ids)=slot then
  select array_agg(id order by random()) into cycle.question_ids
  from unnest(active_ids) available(id);
  slot=0;
 end if;
 cycle.next_index=slot;
 cycle.catalog_revision=current_revision;
 update public.player_question_cycles set question_ids=cycle.question_ids,
  next_index=slot,catalog_revision=current_revision,updated_at=now()
 where user_id=player_id and category_id=subject_id;
 return cycle;
end $$;

-- Automatically generated challenges share this single global cycle. Staff
-- scheduled challenges still use precisely the questions chosen by staff.
create table sj_private.daily_question_cycle (
 singleton boolean primary key default true check(singleton),
 question_ids uuid[] not null default '{}'::uuid[],
 next_index integer not null default 0,
 catalog_revision bigint not null default -1,
 updated_at timestamptz not null default now(),
 check(next_index>=0 and next_index<=cardinality(question_ids))
);
insert into sj_private.daily_question_cycle(singleton) values(true);
alter table sj_private.daily_question_cycle enable row level security;

create function sj_private.prepare_daily_question_cycle()
returns sj_private.daily_question_cycle language plpgsql security definer set search_path='' as $$
declare cycle sj_private.daily_question_cycle; active_ids uuid[]; used_ids uuid[]; remaining_ids uuid[];
        new_id uuid; insert_at int; slot int; current_revision bigint;
begin
 select coalesce(sum(revision),0)::bigint into current_revision
 from sj_private.question_pool_versions;
 select * into cycle from sj_private.daily_question_cycle where singleton for update;
 if cycle.catalog_revision=current_revision and cycle.next_index<cardinality(cycle.question_ids) then
  return cycle;
 end if;
 select coalesce(array_agg(q.id order by q.id),'{}'::uuid[]) into active_ids
 from public.questions q join public.categories c on c.id=q.category_id and c.is_active
 where q.status='published'
 and (select count(*) from public.question_options o where o.question_id=q.id)=4;
 if cardinality(active_ids)<10 then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;

 select coalesce(array_agg(id order by ord) filter(where ord<=cycle.next_index),'{}'::uuid[]),
        coalesce(array_agg(id order by ord) filter(where ord>cycle.next_index and id=any(active_ids)),'{}'::uuid[])
 into used_ids,remaining_ids from unnest(cycle.question_ids) with ordinality saved(id,ord);
 slot=cardinality(used_ids);
 cycle.question_ids=used_ids||remaining_ids;
 for new_id in select id from unnest(active_ids) available(id)
               where not id=any(cycle.question_ids) order by id loop
  insert_at=slot+floor(random()*(cardinality(cycle.question_ids)-slot+1))::int;
  cycle.question_ids=coalesce(cycle.question_ids[1:insert_at],'{}'::uuid[])||array[new_id]||
                     coalesce(cycle.question_ids[insert_at+1:cardinality(cycle.question_ids)],'{}'::uuid[]);
 end loop;
 if cardinality(cycle.question_ids)=slot then
  select array_agg(id order by random()) into cycle.question_ids from unnest(active_ids) available(id);
  slot=0;
 end if;
 cycle.next_index=slot;
 cycle.catalog_revision=current_revision;
 update sj_private.daily_question_cycle set question_ids=cycle.question_ids,
  next_index=slot,catalog_revision=current_revision,updated_at=now() where singleton;
 return cycle;
end $$;

create function sj_private.mark_global_daily_question(qid uuid) returns void
language plpgsql security definer set search_path='' as $$
declare cycle sj_private.daily_question_cycle; used_ids uuid[]; remaining_ids uuid[];
begin
 cycle=sj_private.prepare_daily_question_cycle();
 if not qid=any(coalesce(cycle.question_ids[cycle.next_index+1:cardinality(cycle.question_ids)],'{}'::uuid[])) then
  raise exception 'DAILY_QUESTION_NOT_AVAILABLE';
 end if;
 used_ids=coalesce(cycle.question_ids[1:cycle.next_index],'{}'::uuid[]);
 select coalesce(array_agg(id order by ord),'{}'::uuid[]) into remaining_ids
 from unnest(cycle.question_ids[cycle.next_index+1:cardinality(cycle.question_ids)])
 with ordinality saved(id,ord) where id<>qid;
 update sj_private.daily_question_cycle
 set question_ids=used_ids||array[qid]||remaining_ids,
     next_index=cycle.next_index+1,updated_at=now() where singleton;
end $$;

-- Assignments advance a bag once, even if the player does not answer. A
-- shared daily or live question can already be in a used prefix; in that case
-- leave that unfinished cycle intact rather than resetting it prematurely.
create function sj_private.mark_question_seen(player_id uuid, subject_id uuid, qid uuid)
returns void language plpgsql security definer set search_path='' as $$
declare cycle public.player_question_cycles; used_ids uuid[]; remaining_ids uuid[];
begin
 cycle=sj_private.prepare_question_cycle(player_id,subject_id);
 if not qid=any(coalesce(cycle.question_ids[cycle.next_index+1:cardinality(cycle.question_ids)],'{}'::uuid[])) then
  return;
 end if;
 used_ids=coalesce(cycle.question_ids[1:cycle.next_index],'{}'::uuid[]);
 select coalesce(array_agg(id order by ord),'{}'::uuid[]) into remaining_ids
 from unnest(cycle.question_ids[cycle.next_index+1:cardinality(cycle.question_ids)])
 with ordinality saved(id,ord) where id<>qid;
 update public.player_question_cycles
 set question_ids=used_ids||array[qid]||remaining_ids,
     next_index=cycle.next_index+1,updated_at=now()
 where user_id=player_id and category_id=subject_id;
end $$;

create function sj_private.shared_match_question(p1 uuid,p2 uuid,subject_id uuid,match_mode text)
returns uuid language plpgsql security definer set search_path='' as $$
declare first_cycle public.player_question_cycles; second_cycle public.player_question_cycles;
        first_unused uuid[]; second_unused uuid[]; selected uuid;
begin
 first_cycle=sj_private.prepare_question_cycle(p1,subject_id);
 first_unused=coalesce(first_cycle.question_ids[first_cycle.next_index+1:cardinality(first_cycle.question_ids)],'{}'::uuid[]);
 if match_mode='bot' then
  selected=first_unused[1];
 else
  second_cycle=sj_private.prepare_question_cycle(p2,subject_id);
  second_unused=coalesce(second_cycle.question_ids[second_cycle.next_index+1:cardinality(second_cycle.question_ids)],'{}'::uuid[]);
  select q.id into selected from public.questions q
  join public.categories c on c.id=q.category_id and c.is_active
  where q.category_id=subject_id and q.status='published'
    and q.id=any(first_cycle.question_ids) and q.id=any(second_cycle.question_ids)
    and (select count(*) from public.question_options o where o.question_id=q.id)=4
  order by case when q.id=any(first_unused) and q.id=any(second_unused) then 0
                when q.id=any(first_unused) or q.id=any(second_unused) then 1 else 2 end,
           random()
  limit 1;
 end if;
 if selected is null then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 perform sj_private.mark_question_seen(p1,subject_id,selected);
 if match_mode='live' then perform sj_private.mark_question_seen(p2,subject_id,selected); end if;
 return selected;
end $$;

-- The player locks also serialize a match racing a Daily Challenge start.
-- Match creation remains one transaction: a failed question pick rolls back
-- both players' bag advances and all match rows.
create or replace function sj_private.new_match(p1 uuid,p2 uuid,category uuid,topic uuid,mode text)
returns uuid language plpgsql security definer set search_path='' as $$
declare mid uuid; r record; actor record; qid uuid; snap jsonb; correct_rounds int[];
        target int; style text; delay numeric; short boolean;
begin
 for actor in select id from public.profiles where id in(p1,p2) and not is_bot order by id loop
  perform pg_advisory_xact_lock(hashtext('sj_question_player_'||actor.id::text));
 end loop;
 if mode='bot' then
  select b.play_style into style from sj_private.bot_names b
  join public.profiles p on p.full_name=b.name where p.id=p2;
 end if;
 style=coalesce(style,(array['Speedster','Analytical','Balanced','Wildcard'])[1+floor(random()*4)::int]);
 target=2+floor(random()*3)::int;
 select array_agg(i) into correct_rounds
 from (select i from generate_series(0,3) i order by random() limit target) t;
 insert into public.matches(category_id,mode,player1_id,player2_id,started_at,next_tick_at,rules_version,bot_style)
 values(null,mode,p1,p2,now()+interval '3 seconds',now()+interval '3 seconds',2,
        case when mode='bot' then style end) returning id into mid;
 insert into public.match_players(match_id,user_id,rating_before)
 select mid,id,rating from public.profiles where id in(p1,p2);
 for r in select b.*,c.id category from public.battle_rounds b
          join public.categories c on c.slug=b.subject_slug and c.is_active
          order by b.round_index loop
  qid=sj_private.shared_match_question(p1,p2,r.category,mode);
  snap=sj_private.question_snapshot(qid)||jsonb_build_object('time_limit_seconds',r.duration_seconds);
  insert into public.match_questions(match_id,question_index,question_id,snapshot,option_order)
  values(mid,r.round_index,qid,snap,snap->'options');
  if mode='bot' then
   short=r.duration_seconds=15;
   delay=case style when 'Speedster' then case when short then 2+random()*4 else 8+random()*8 end
     when 'Analytical' then case when short then 5+random()*6 else 20+random()*14 end
     when 'Balanced' then case when short then 3+random()*5 else 12+random()*12 end
     else 2+random()*(r.duration_seconds-3) end;
   insert into public.bot_plans(match_id,question_index,will_be_correct,response_ms)
   values(mid,r.round_index,r.round_index=any(correct_rounds),floor(delay*1000)::int);
  end if;
 end loop;
 if (select count(*) from public.match_questions where match_id=mid)<>4 then
  raise exception 'NOT_ENOUGH_QUESTIONS';
 end if;
 delete from public.matchmaking_queue where user_id in(p1,p2);
 perform realtime.send(jsonb_build_object('match_id',mid),'match_found','user:'||p1::text,true);
 if mode='live' then
  perform realtime.send(jsonb_build_object('match_id',mid),'match_found','user:'||p2::text,true);
 end if;
 return mid;
end $$;

create or replace function sj_private.generate_daily(day date) returns uuid
language plpgsql security definer set search_path='' as $$
declare cid uuid; qid uuid; idx int; selected_today uuid[]='{}'::uuid[];
        cycle sj_private.daily_question_cycle;
begin
 select id into cid from public.daily_challenges where challenge_date=day;
 if cid is not null then return cid; end if;
 perform pg_advisory_xact_lock(hashtext('sj_daily_'||day::text));
 select id into cid from public.daily_challenges where challenge_date=day;
 if cid is not null then return cid; end if;
 if (select count(*) from public.questions q join public.categories c on c.id=q.category_id and c.is_active
     where q.status='published' and
       (select count(*) from public.question_options o where o.question_id=q.id)=4)<10 then
  raise exception 'NOT_ENOUGH_QUESTIONS';
 end if;
 insert into public.daily_challenges(challenge_date,title,status)
 values(day,'A little better · '||to_char(day,'DD Mon'),'published') returning id into cid;
 for idx in 0..9 loop
  cycle=sj_private.prepare_daily_question_cycle();
  -- Respect the existing subject/difficulty spread. The bag order is already
  -- shuffled, so ties stay random without another full ORDER BY random().
  select q.id into qid
  from unnest(cycle.question_ids[cycle.next_index+1:cardinality(cycle.question_ids)])
       with ordinality available(id,ord)
  join public.questions q on q.id=available.id
  where not q.id=any(selected_today)
  order by (
    select count(*) from unnest(selected_today) chosen(id)
    join public.questions prior on prior.id=chosen.id
    where prior.category_id=q.category_id and prior.difficulty=q.difficulty
   ), (
    select count(*) from unnest(selected_today) chosen(id)
    join public.questions prior on prior.id=chosen.id
    where prior.category_id=q.category_id
   ), available.ord
  limit 1;
  if qid is null then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
  insert into public.daily_challenge_questions(challenge_id,question_index,question_id,snapshot)
  values(cid,idx,qid,sj_private.question_snapshot(qid));
  perform sj_private.mark_global_daily_question(qid);
  selected_today=selected_today||qid;
 end loop;
 return cid;
end $$;

create or replace function public.start_daily_attempt() returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); today jsonb; a public.daily_attempts;
        idx int=0; n int; new_attempt uuid; assigned record;
begin
 today=public.get_today_challenge();
 if today is null then raise exception 'CHALLENGE_NOT_AVAILABLE'; end if;
 perform pg_advisory_xact_lock(hashtext('sj_question_player_'||uid::text));
 insert into public.daily_attempts(challenge_id,user_id)
 values((today->>'id')::uuid,uid) on conflict(challenge_id,user_id) do nothing
 returning id into new_attempt;
 select * into a from public.daily_attempts
 where challenge_id=(today->>'id')::uuid and user_id=uid for update;
 if new_attempt is not null then
  for assigned in
   select q.question_id,p.category_id from public.daily_challenge_questions q
   join public.questions p on p.id=q.question_id
   join public.categories c on c.id=p.category_id and c.is_active
   where q.challenge_id=a.challenge_id and p.status='published'
   order by p.category_id,q.question_index loop
   perform sj_private.mark_question_seen(uid,assigned.category_id,assigned.question_id);
  end loop;
 end if;
 select count(*) into n from public.daily_challenge_questions where challenge_id=a.challenge_id;
 if a.completed_at is null then
  select min(w.idx) into idx from sj_private.daily_windows(a.id) w
  where not w.answered and w.closes_at+interval '500 milliseconds'>clock_timestamp();
  if idx is null then
   perform sj_private.finish_daily(a.id);
   select * into a from public.daily_attempts where id=a.id;
  end if;
 end if;
 return jsonb_build_object('attempt_id',a.id,'question_count',n,'question_index',idx,
  'completed',a.completed_at is not null,'score',a.score,'correct_count',a.correct_count,
  'question',case when a.completed_at is null then sj_private.daily_question(a.id,idx) else null end);
end $$;

-- A manual schedule should not consume ten unseen questions from the global
-- automatic bag merely to replace them a moment later.
create or replace function public.admin_schedule_daily(day date,title text,question_ids uuid[] default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid; qid uuid; idx int=0;
begin
 perform sj_private.require_admin('editor');
 perform pg_advisory_xact_lock(hashtext('sj_daily_'||day::text));
 if day<(now() at time zone 'Asia/Kolkata')::date
    or day>(now() at time zone 'Asia/Kolkata')::date+365
    or length(trim(title)) not between 2 and 100 then raise exception 'INVALID_CHALLENGE'; end if;
 select id into cid from public.daily_challenges where challenge_date=day for update;
 if exists(select 1 from public.daily_attempts where challenge_id=cid) then
  raise exception 'CHALLENGE_ALREADY_STARTED';
 end if;
 if cid is null then
  if question_ids is null then
   cid=sj_private.generate_daily(day);
  else
   insert into public.daily_challenges(challenge_date,title,status,created_by)
   values(day,trim(title),'scheduled',auth.uid()) returning id into cid;
  end if;
 end if;
 if question_ids is not null then
  if cardinality(question_ids)<>10 or
     (select count(distinct id) from public.questions
      where id=any(question_ids) and status='published')<>cardinality(question_ids) then
   raise exception 'INVALID_QUESTIONS';
  end if;
  delete from public.daily_challenge_questions where challenge_id=cid;
  foreach qid in array question_ids loop
   insert into public.daily_challenge_questions(challenge_id,question_index,question_id,snapshot)
   values(cid,idx,qid,sj_private.question_snapshot(qid));
   idx=idx+1;
  end loop;
 end if;
 update public.daily_challenges set title=trim(admin_schedule_daily.title),
  status='scheduled',created_by=auth.uid() where id=cid;
 perform sj_private.audit('schedule','daily_challenges',cid::text,
  jsonb_build_object('day',day,'title',title));
 return cid;
end $$;

revoke all on function sj_private.bump_question_pool(),
 sj_private.prepare_question_cycle(uuid,uuid),sj_private.mark_question_seen(uuid,uuid,uuid),
 sj_private.prepare_daily_question_cycle(),sj_private.mark_global_daily_question(uuid),
 sj_private.shared_match_question(uuid,uuid,uuid,text)
 from public,anon,authenticated;

commit;
