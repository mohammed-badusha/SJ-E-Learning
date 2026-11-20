-- Keep the existing four-question selection, bot plan, and scoring rules.
-- Begin the three-second VS countdown only after the match is fully prepared.
begin;

create or replace function sj_private.new_match(p1 uuid,p2 uuid,category uuid,topic uuid,mode text)
returns uuid language plpgsql security definer set search_path='' as $$
declare mid uuid; r record; actor record; qid uuid; snap jsonb; correct_rounds int[];
        target int; style text; quant_id uuid; selected_ids uuid[]='{}'::uuid[];
        ready_at timestamptz;
begin
 for actor in select id from public.profiles where id in(p1,p2) and not is_bot order by id loop
  perform pg_advisory_xact_lock(hashtext('sj_question_player_'||actor.id::text));
 end loop;
 select id into quant_id from public.categories where slug='quant' and is_active;
 if quant_id is null or (select count(*) from (
   select 1 from public.questions q
   where q.category_id=quant_id and q.status='published'
     and (select count(*) from public.question_options o where o.question_id=q.id)=4
   limit 4) available)<4 then
  raise exception 'NOT_ENOUGH_QUESTIONS';
 end if;
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
 for r in select generate_series(0,3) round_index loop
  qid=sj_private.shared_match_question(p1,p2,quant_id,mode,selected_ids);
  selected_ids=array_append(selected_ids,qid);
  snap=sj_private.question_snapshot(qid)||jsonb_build_object('time_limit_seconds',40);
  insert into public.match_questions(match_id,question_index,question_id,snapshot,option_order)
  values(mid,r.round_index,qid,snap,snap->'options');
  if mode='bot' then
   insert into public.bot_plans(match_id,question_index,will_be_correct,response_ms)
   values(mid,r.round_index,r.round_index=any(correct_rounds),
          sj_private.bot_response_ms(style,40,r.round_index=any(correct_rounds)));
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
 ready_at=clock_timestamp();
 update public.matches set started_at=ready_at+interval '3 seconds',
   next_tick_at=ready_at+interval '3 seconds' where id=mid;
 update public.match_players set heartbeat_at=ready_at where match_id=mid;
 return mid;
end $$;

-- Match-player inserts and score changes already have a match broadcast and
-- final profile invalidation. Avoid reloading each player's three-part session
-- while entering a match; retain staff dashboard invalidation.
create or replace function sj_private.notify_data_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare row_data jsonb; owner text;
begin
 if TG_TABLE_NAME='match_players' then
  if TG_OP='UPDATE' and
    (to_jsonb(old)-'heartbeat_at'-'updated_at')=
    (to_jsonb(new)-'heartbeat_at'-'updated_at') then return null; end if;
  perform realtime.send(jsonb_build_object('table',TG_TABLE_NAME),
    'changed','data:admin',true);
  return null;
 end if;
 row_data=case when TG_OP='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 if TG_TABLE_NAME in ('categories','subtopics','app_settings','battle_rounds','daily_challenges') then
  perform realtime.send(jsonb_build_object('table',TG_TABLE_NAME),'changed','data:catalog',true);
 elsif TG_TABLE_NAME='admin_users' then
  select id::text into owner from public.profiles where email=row_data->>'email';
  if owner is not null then
   perform realtime.send(jsonb_build_object('table',TG_TABLE_NAME),'changed','data:user:'||owner,true);
  end if;
 elsif TG_TABLE_NAME in ('profiles','user_preferences','practice_attempts','daily_attempts') then
  owner=case when TG_TABLE_NAME='profiles' then row_data->>'id' else row_data->>'user_id' end;
  perform realtime.send(jsonb_build_object('table',TG_TABLE_NAME),'changed','data:user:'||owner,true);
 end if;
 perform realtime.send(jsonb_build_object('table',TG_TABLE_NAME),'changed','data:admin',true);
 return null;
end $$;

commit;
