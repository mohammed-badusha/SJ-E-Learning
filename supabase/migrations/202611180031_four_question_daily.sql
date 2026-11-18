-- Version 1 challenges (including completed attempts) retain their saved
-- questions and timers. New challenges use the four existing battle rounds.
alter table public.daily_challenges add column rules_version int not null default 1
  check (rules_version in (1,2));
alter table public.daily_challenges alter column title set default 'Your daily four';
insert into public.app_settings(key,value) values('daily_question_count','4'::jsonb)
on conflict(key) do update set value=excluded.value;

create or replace function sj_private.prepare_daily_question_cycle()
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
 if cardinality(active_ids)<4 then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
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

-- Take an unused question from the existing global bag whenever the subject
-- has one. A subject with no unused entries may reuse an old entry without
-- resetting the other subjects' unfinished cycle.
create function sj_private.pick_daily_round(subject_id uuid, chosen_today uuid[])
returns uuid language plpgsql security definer set search_path='' as $$
declare cycle sj_private.daily_question_cycle; selected uuid; from_unused boolean=false;
begin
 cycle=sj_private.prepare_daily_question_cycle();
 select q.id into selected
 from unnest(cycle.question_ids[cycle.next_index+1:cardinality(cycle.question_ids)])
      with ordinality available(id,ord)
 join public.questions q on q.id=available.id
 where q.category_id=subject_id and q.status='published' and not q.id=any(chosen_today)
   and (select count(*) from public.question_options o where o.question_id=q.id)=4
 order by (select count(*) from unnest(chosen_today) chosen(id)
           join public.questions prior on prior.id=chosen.id
           where prior.difficulty=q.difficulty), available.ord
 limit 1;
 if selected is not null then
  from_unused=true;
 else
  select q.id into selected
  from unnest(cycle.question_ids[1:cycle.next_index]) with ordinality used(id,ord)
  join public.questions q on q.id=used.id
  where q.category_id=subject_id and q.status='published' and not q.id=any(chosen_today)
    and (select count(*) from public.question_options o where o.question_id=q.id)=4
  order by used.ord,random() limit 1;
 end if;
 if selected is null then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 if from_unused then perform sj_private.mark_global_daily_question(selected); end if;
 return selected;
end $$;

create or replace function sj_private.generate_daily(day date) returns uuid
language plpgsql security definer set search_path='' as $$
declare cid uuid; r record; qid uuid; selected_today uuid[]='{}'::uuid[];
begin
 select id into cid from public.daily_challenges where challenge_date=day;
 if cid is not null then return cid; end if;
 perform pg_advisory_xact_lock(hashtext('sj_daily_'||day::text));
 select id into cid from public.daily_challenges where challenge_date=day;
 if cid is not null then return cid; end if;
 if (select count(*) from public.battle_rounds b join public.categories c on c.slug=b.subject_slug)<>4
    or exists(select 1 from public.battle_rounds b join public.categories c on c.slug=b.subject_slug
  where not c.is_active or not exists(select 1 from public.questions q where q.category_id=c.id
   and q.status='published' and (select count(*) from public.question_options o where o.question_id=q.id)=4))
 then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 insert into public.daily_challenges(challenge_date,title,status,rules_version)
 values(day,'A little better · '||to_char(day,'DD Mon'),'published',2) returning id into cid;
 for r in select b.round_index,b.duration_seconds,c.id category_id
          from public.battle_rounds b join public.categories c on c.slug=b.subject_slug
          order by b.round_index loop
  qid=sj_private.pick_daily_round(r.category_id,selected_today);
  insert into public.daily_challenge_questions(challenge_id,question_index,question_id,snapshot)
  values(cid,r.round_index,qid,
   sj_private.question_snapshot(qid)||jsonb_build_object('time_limit_seconds',r.duration_seconds));
  selected_today=selected_today||qid;
 end loop;
 return cid;
end $$;

create or replace function public.get_today_challenge() returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); day date=(now() at time zone 'Asia/Kolkata')::date;
  cid uuid;
begin
 select id into cid from public.daily_challenges where challenge_date=day;
 if cid is null then
  if (select count(*) from public.battle_rounds b join public.categories c on c.slug=b.subject_slug
      where c.is_active and exists(select 1 from public.questions q where q.category_id=c.id
       and q.status='published' and (select count(*) from public.question_options o where o.question_id=q.id)=4))<>4
  then return jsonb_build_object('available',false,'question_count',0); end if;
  cid=sj_private.generate_daily(day);
 end if;
 return coalesce((select jsonb_build_object('available',true,'id',c.id,'title',c.title,
   'challenge_date',c.challenge_date,
   'question_count',(select count(*) from public.daily_challenge_questions where challenge_id=cid),
   'completed',coalesce(a.completed_at is not null,false),'started',a.id is not null,
   'score',a.score,'resets_at',(day+1)::timestamp at time zone 'Asia/Kolkata')
   from public.daily_challenges c left join public.daily_attempts a
   on a.challenge_id=c.id and a.user_id=uid
   where c.id=cid and c.status in ('published','scheduled')),
   jsonb_build_object('available',false,'question_count',0));
end $$;

create or replace function public.admin_schedule_daily(day date,title text,question_ids uuid[] default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid; qid uuid; r record;
begin
 perform sj_private.require_admin('editor');
 perform pg_advisory_xact_lock(hashtext('sj_daily_'||day::text));
 if day<(now() at time zone 'Asia/Kolkata')::date
    or day>(now() at time zone 'Asia/Kolkata')::date+365
    or length(trim(title)) not between 2 and 100 then raise exception 'INVALID_CHALLENGE'; end if;
 if question_ids is not null then
  if cardinality(question_ids)<>4 or cardinality(array(select distinct unnest(question_ids)))<>4
  then raise exception 'FOUR_SUBJECT_QUESTIONS_REQUIRED'; end if;
  for r in select b.round_index,b.subject_slug from public.battle_rounds b order by b.round_index loop
   if not exists(select 1 from public.questions q join public.categories c on c.id=q.category_id
     where q.id=question_ids[r.round_index+1] and q.status='published' and c.is_active
     and c.slug=r.subject_slug
     and (select count(*) from public.question_options o where o.question_id=q.id)=4)
   then raise exception 'FOUR_SUBJECT_QUESTIONS_REQUIRED'; end if;
  end loop;
 end if;
 select id into cid from public.daily_challenges where challenge_date=day for update;
 if exists(select 1 from public.daily_attempts where challenge_id=cid) then
  raise exception 'CHALLENGE_ALREADY_STARTED'; end if;
 if cid is null then
  if question_ids is null then
   cid=sj_private.generate_daily(day);
  else
   insert into public.daily_challenges(challenge_date,title,status,created_by,rules_version)
   values(day,trim(title),'scheduled',auth.uid(),2) returning id into cid;
  end if;
 end if;
 if question_ids is not null then
  delete from public.daily_challenge_questions where challenge_id=cid;
  for r in select b.round_index,b.duration_seconds from public.battle_rounds b order by b.round_index loop
   qid=question_ids[r.round_index+1];
   insert into public.daily_challenge_questions(challenge_id,question_index,question_id,snapshot)
   values(cid,r.round_index,qid,
    sj_private.question_snapshot(qid)||jsonb_build_object('time_limit_seconds',r.duration_seconds));
  end loop;
 end if;
 update public.daily_challenges set title=trim(admin_schedule_daily.title),
  status='scheduled',created_by=auth.uid(),rules_version=2 where id=cid;
 perform sj_private.audit('schedule','daily_challenges',cid::text,
  jsonb_build_object('day',day,'title',title));
 return cid;
end $$;

-- Replace only unstarted current/future legacy sets. Attempts already in
-- progress retain their saved ten-question snapshots for every participant.
do $$
declare challenge record; r record; qid uuid; selected_today uuid[];
begin
 for challenge in select c.id from public.daily_challenges c
  where c.rules_version=1
   and c.challenge_date >= (now() at time zone 'Asia/Kolkata')::date
   and not exists(select 1 from public.daily_attempts a where a.challenge_id=c.id)
  order by c.challenge_date loop
  selected_today='{}'::uuid[];
  delete from public.daily_challenge_questions where challenge_id=challenge.id;
  for r in select b.round_index,b.duration_seconds,cat.id category_id
   from public.battle_rounds b join public.categories cat on cat.slug=b.subject_slug
   order by b.round_index loop
   qid=sj_private.pick_daily_round(r.category_id,selected_today);
   insert into public.daily_challenge_questions(challenge_id,question_index,question_id,snapshot)
   values(challenge.id,r.round_index,qid,
    sj_private.question_snapshot(qid)||jsonb_build_object('time_limit_seconds',r.duration_seconds));
   selected_today=selected_today||qid;
  end loop;
  update public.daily_challenges set rules_version=2 where id=challenge.id;
 end loop;
end $$;

create function sj_private.validate_four_question_daily() returns trigger
language plpgsql security definer set search_path='' as $$
declare cid uuid; rule int;
begin
 if tg_table_name='daily_challenges' then
  cid=new.id;
 elsif tg_op='DELETE' then
  cid=old.challenge_id;
 else
  cid=new.challenge_id;
 end if;
 select rules_version into rule from public.daily_challenges where id=cid;
 if rule=2 and (
  (select count(*) from public.daily_challenge_questions where challenge_id=cid)<>4
  or exists(
   select 1 from public.battle_rounds b
   left join public.categories c on c.slug=b.subject_slug
   left join public.daily_challenge_questions q
    on q.challenge_id=cid and q.question_index=b.round_index
   where q.id is null or (q.snapshot->>'category_id')::uuid is distinct from c.id
    or (q.snapshot->>'time_limit_seconds')::int is distinct from b.duration_seconds
  )
 ) then raise exception 'FOUR_SUBJECT_QUESTIONS_REQUIRED'; end if;
 return null;
end $$;

create constraint trigger validate_four_question_daily_parent
after insert or update on public.daily_challenges
deferrable initially deferred for each row
execute function sj_private.validate_four_question_daily();

create constraint trigger validate_four_question_daily_questions
after insert or update or delete on public.daily_challenge_questions
deferrable initially deferred for each row
execute function sj_private.validate_four_question_daily();

revoke all on function sj_private.pick_daily_round(uuid,uuid[]) from public,anon,authenticated;
revoke all on function sj_private.validate_four_question_daily() from public,anon,authenticated;
