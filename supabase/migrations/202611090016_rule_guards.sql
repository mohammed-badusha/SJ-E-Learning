begin;
create or replace function public.admin_save_setting(key text,value jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin('super_admin');
 if key='questions_per_match' then if (value#>>'{}')::int <>4 then raise exception 'INVALID_SETTING'; end if;
 elsif key='search_timeout_seconds' then if (value#>>'{}')::int <>10 then raise exception 'INVALID_SETTING'; end if;
 elsif key in ('label_bots','maintenance_mode') then if jsonb_typeof(value)<>'boolean' then raise exception 'INVALID_SETTING'; end if;
 elsif key='min_app_version' then if jsonb_typeof(value)<>'string' then raise exception 'INVALID_SETTING'; end if;
 else raise exception 'INVALID_SETTING'; end if;
 insert into public.app_settings as s(key,value) values(key,value) on conflict on constraint app_settings_pkey do update set value=excluded.value;
 perform sj_private.audit('setting','app_settings',key,value);
end $$;
create or replace function public.get_match_state(match_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); m public.matches; mq public.match_questions;
begin
 select * into m from public.matches where id=match_id and (player1_id=uid or player2_id=uid);
 if not found then raise exception 'MATCH_NOT_FOUND' using errcode='42501'; end if;
 update public.match_players set heartbeat_at=now() where match_players.match_id=get_match_state.match_id and user_id=uid;
 select * into mq from public.match_questions where match_questions.match_id=get_match_state.match_id and question_index=m.current_question_index;
 return jsonb_build_object('match_id',m.id,'status',m.status,'rules_version',m.rules_version,'phase',m.phase,'mode',m.mode,'question_index',m.current_question_index,
 'question_count',(select count(*) from public.match_questions q where q.match_id=m.id),'server_now',clock_timestamp(),'starts_at',m.started_at,
 'label_bots',coalesce((select value from public.app_settings where key='label_bots'),'true'::jsonb),
 'players',(select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'level',p.level,'avatar_url',case when p.avatar_url like 'preset:%' or p.avatar_url like 'photo:%' or p.avatar_url like 'color:%' then p.avatar_url end,'rating',mp.rating_before,'score',coalesce((select sum(points) from public.match_answers a join public.match_questions q on q.match_id=a.match_id and q.question_index=a.question_index where a.match_id=m.id and a.user_id=p.id and q.revealed_at is not null),0),
 'rating_after',mp.rating_after,'xp_gained',mp.xp_gained,'result',mp.result,'connected',p.is_bot or mp.heartbeat_at>now()-interval '5 seconds')) from public.match_players mp join public.profiles p on p.id=mp.user_id where mp.match_id=m.id),
 'question',case when mq.started_at is null then null else sj_private.safe_question(mq.snapshot)||jsonb_build_object('started_at',mq.started_at,'deadline_at',mq.deadline_at) end,
 'answered',(select coalesce(jsonb_agg(a.user_id),'[]') from public.match_answers a where a.match_id=m.id and a.question_index=m.current_question_index),
 'result',case when mq.revealed_at is not null then jsonb_build_object('correct_option_id',mq.snapshot->>'correct_option_id','explanation',mq.snapshot->>'explanation',
 'answers',(select coalesce(jsonb_agg(jsonb_build_object('user_id',a.user_id,'option_id',a.option_id,'points',a.points)),'[]') from public.match_answers a where a.match_id=m.id and a.question_index=m.current_question_index)) else null end);
end $$;
create or replace function sj_private.match_player_report(mid uuid, participant uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',p.id,'full_name',p.full_name,'is_bot',p.is_bot,
 'avatar_url',case when p.avatar_url like 'preset:%' or p.avatar_url like 'photo:%' or p.avatar_url like 'color:%' then p.avatar_url end,
 'score',mp.score,'rating_before',mp.rating_before,'rating_after',mp.rating_after,
 'rating_change',coalesce(mp.rating_after,mp.rating_before)-mp.rating_before,
 'xp_gained',mp.xp_gained,'result',mp.result,
 'answered',a.answered,'correct',a.correct,'wrong',a.wrong,'unanswered',q.played-a.answered,
 'accuracy',case when q.played=0 then 0 else round(100.0*a.correct/q.played,1) end,
 'avg_response_ms',a.avg_response_ms,'avg_correct_response_ms',a.avg_correct_response_ms,
 'fastest_correct_ms',a.fastest_correct_ms,'total_response_ms',a.total_response_ms,
 'base_points',a.base_points,'speed_bonus',mp.score-a.base_points)
 from public.match_players mp join public.profiles p on p.id=mp.user_id
 cross join lateral(select count(*)::int played from public.match_questions mq where mq.match_id=mid and mq.started_at is not null) q
 cross join lateral(select count(*)::int answered,count(*) filter(where ans.is_correct)::int correct,
 count(*) filter(where not ans.is_correct)::int wrong,
 round(avg(ans.response_ms))::int avg_response_ms,
 round(avg(ans.response_ms) filter(where ans.is_correct))::int avg_correct_response_ms,
 min(ans.response_ms) filter(where ans.is_correct) fastest_correct_ms,
 coalesce(sum(ans.response_ms),0) total_response_ms,
 coalesce(sum(case when ans.is_correct then case when (select rules_version from public.matches where id=mid)=2 then 2 else 10*case when ans.question_index=(select max(x.question_index) from public.match_questions x where x.match_id=mid) then 2 else 1 end end else 0 end),0)::int base_points
 from public.match_answers ans join public.match_questions mq on mq.match_id=ans.match_id and mq.question_index=ans.question_index
 where ans.match_id=mid and ans.user_id=participant and mq.started_at is not null) a
 where mp.match_id=mid and mp.user_id=participant
$$;
create or replace function public.admin_save_question(payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare qid uuid=coalesce((payload->>'id')::uuid,gen_random_uuid()); before_data jsonb; opt jsonb; idx int=0; n int; topic uuid; topic_name text;
begin
 perform sj_private.require_admin('editor');
 select to_jsonb(q) into before_data from public.questions q where id=qid for update;
 if exists(select 1 from public.match_questions where question_id=qid) or exists(select 1 from public.daily_challenge_questions where question_id=qid)
 then raise exception 'QUESTION_ALREADY_USED_DUPLICATE_INSTEAD'; end if;
 if jsonb_typeof(payload->'options')<>'array' or jsonb_array_length(payload->'options') <>4 then raise exception 'INVALID_OPTIONS'; end if;
 select count(*) filter(where (value->>'is_correct')::boolean),count(distinct lower(trim(value->>'option_text')))
 into idx,n from jsonb_array_elements(payload->'options');
 if idx<>1 or n<>jsonb_array_length(payload->'options') or exists(select 1 from jsonb_array_elements(payload->'options') where length(trim(value->>'option_text'))=0)
 then raise exception 'ONE_CORRECT_AND_UNIQUE_OPTIONS_REQUIRED'; end if;
 topic=(payload->>'subtopic_id')::uuid;
 topic_name=nullif(trim(payload->>'topic_name'),'');
 if topic is null and topic_name is not null then
 select id into topic from public.subtopics where category_id=(payload->>'category_id')::uuid and lower(name)=lower(topic_name) limit 1;
 if topic is null then insert into public.subtopics(category_id,name) values((payload->>'category_id')::uuid,topic_name) on conflict(category_id,name) do update set name=excluded.name returning id into topic; end if;
 end if;
 if topic is null or length(trim(coalesce(payload->>'explanation','')))=0 then raise exception 'TOPIC_AND_EXPLANATION_REQUIRED'; end if;
 insert into public.questions(id,category_id,subtopic_id,question_text,image_url,difficulty,time_limit_seconds,explanation,status,created_by)
 values(qid,(payload->>'category_id')::uuid,topic,trim(payload->>'question_text'),payload->>'image_url',payload->>'difficulty',
 (payload->>'time_limit_seconds')::int,payload->>'explanation',payload->>'status',auth.uid())
 on conflict(id) do update set category_id=excluded.category_id,subtopic_id=excluded.subtopic_id,question_text=excluded.question_text,image_url=excluded.image_url,
 difficulty=excluded.difficulty,time_limit_seconds=excluded.time_limit_seconds,explanation=excluded.explanation,status=excluded.status;
 delete from public.question_options where question_id=qid;
 idx=0;
 for opt in select value from jsonb_array_elements(payload->'options') loop
 insert into public.question_options(question_id,option_text,image_url,is_correct,sort_order)
 values(qid,trim(opt->>'option_text'),opt->>'image_url',(opt->>'is_correct')::boolean,idx); idx=idx+1;
 end loop;
 update public.questions set exam=nullif(trim(payload->>'exam'),'') where id=qid;
 perform sj_private.audit('save','questions',qid::text,jsonb_build_object('before',before_data,'after',payload));
 return qid;
end $$;

create function sj_private.notify_standings() returns trigger language plpgsql security definer set search_path='' as $$
begin perform realtime.send('{}','standings','data:catalog',true); return null; end $$;
create trigger standings_changed after update of rating,xp on public.profiles for each statement execute function sj_private.notify_standings();
create trigger daily_standings_changed after update of completed_at on public.daily_attempts for each statement execute function sj_private.notify_standings();
create trigger daily_catalog_changed after insert or update or delete on public.daily_challenges for each row execute function sj_private.notify_data_change();
create index matches_player1_history on public.matches(player1_id,created_at desc,id);
create index matches_player2_history on public.matches(player2_id,created_at desc,id);
revoke all on all functions in schema sj_private from public,anon,authenticated;
commit;
