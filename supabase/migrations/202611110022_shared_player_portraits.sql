begin;

-- Google may provide its picture under either metadata key. Keep existing
-- learner-selected pictures when filling gaps on older profiles.
create or replace function sj_private.new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,auth_user_id,full_name,email,avatar_url)
 values(new.id,new.id,left(coalesce(new.raw_user_meta_data->>'full_name',''),50),lower(new.email),
   coalesce(nullif(new.raw_user_meta_data->>'avatar_url',''),nullif(new.raw_user_meta_data->>'picture','')));
 return new;
end $$;

update public.profiles p
set avatar_url=coalesce(nullif(u.raw_user_meta_data->>'avatar_url',''),nullif(u.raw_user_meta_data->>'picture',''))
from auth.users u
where p.auth_user_id=u.id and p.avatar_url is null
  and coalesce(nullif(u.raw_user_meta_data->>'avatar_url',''),nullif(u.raw_user_meta_data->>'picture',''))
    like 'https://%.googleusercontent.com/%';

-- Gallery thumbnails remain private table data, but any signed-in learner can
-- fetch the current picture of another player. Old match_id callers still work.
create or replace function public.get_player_photo(photo_id uuid, match_id uuid default null)
returns text language sql stable security definer set search_path='' as $$
 select replace(encode(f.thumbnail,'base64'),chr(10),'')
 from sj_private.player_photos f
 join public.profiles p on p.id=f.owner_id
 where f.photo_id=get_player_photo.photo_id
   and p.avatar_url='photo:'||f.photo_id::text
   and p.deleted_at is null
   and auth.uid() is not null
$$;

-- A match participant receives the same picture reference for Google,
-- gallery, preset and bot avatars. Answer visibility rules stay unchanged.
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
 'players',(select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'level',p.level,'avatar_url',p.avatar_url,'rating',mp.rating_before,'score',coalesce((select sum(points) from public.match_answers a join public.match_questions q on q.match_id=a.match_id and q.question_index=a.question_index where a.match_id=m.id and a.user_id=p.id and q.revealed_at is not null),0),
 'rating_after',mp.rating_after,'xp_gained',mp.xp_gained,'result',mp.result,'connected',p.is_bot or mp.heartbeat_at>now()-interval '5 seconds')) from public.match_players mp join public.profiles p on p.id=mp.user_id where mp.match_id=m.id),
 'question',case when mq.started_at is null then null else sj_private.safe_question(mq.snapshot)||jsonb_build_object('started_at',mq.started_at,'deadline_at',mq.deadline_at) end,
 'answered',(select coalesce(jsonb_agg(a.user_id),'[]') from public.match_answers a where a.match_id=m.id and a.question_index=m.current_question_index),
 'result',case when mq.revealed_at is not null then jsonb_build_object('correct_option_id',mq.snapshot->>'correct_option_id','explanation',mq.snapshot->>'explanation',
 'answers',(select coalesce(jsonb_agg(jsonb_build_object('user_id',a.user_id,'option_id',a.option_id,'points',a.points)),'[]') from public.match_answers a where a.match_id=m.id and a.question_index=m.current_question_index)) else null end);
end $$;

create or replace function sj_private.match_player_report(mid uuid, participant uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',p.id,'full_name',p.full_name,'is_bot',p.is_bot,
 'avatar_url',p.avatar_url,
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

create or replace function public.get_leaderboard(type text default 'all_time', category_id uuid default null, result_limit int default 100) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); rows jsonb;
begin
 if type not in ('all_time','weekly','daily') then raise exception 'INVALID_LEADERBOARD'; end if;
 with ranked as (
 select p.id,p.full_name,p.level,p.rating,p.trophies,p.avatar_url,
 case when type='daily' then coalesce(d.score,0) when type='weekly' then coalesce(w.points,0) else p.trophies end metric,
 rank() over(order by case when type='daily' then coalesce(d.score,0) when type='weekly' then coalesce(w.points,0) else p.trophies end desc,coalesce(d.total_time_ms,0)) rank
 from public.profiles p
 left join public.daily_attempts d on d.user_id=p.id and d.completed_at is not null and d.challenge_id=(select id from public.daily_challenges where challenge_date=(now() at time zone 'Asia/Kolkata')::date)
 left join lateral(select sum(mp.score) points from public.match_players mp join public.matches m on m.id=mp.match_id where mp.user_id=p.id and m.status='completed'
 and (get_leaderboard.category_id is null or m.category_id=get_leaderboard.category_id)
 and m.ended_at>=date_trunc('week',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata') w on true
 where p.profile_completed and not p.is_bot and not p.is_banned and (type<>'daily' or d.id is not null)
 ) select coalesce(jsonb_agg(to_jsonb(r) order by rank,id),'[]') into rows from ranked r where rank<=least(greatest(result_limit,1),100) or id=uid;
 return jsonb_build_object('rows',rows);
end $$;

create or replace function public.get_history_page(before_at timestamptz default null, before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid=sj_private.require_player();
begin
 if (before_at is null)<>(before_id is null) then raise exception 'INVALID_CURSOR'; end if;
 return jsonb_build_object('rows',(select coalesce(jsonb_agg(r order by r.played_at desc,r.id desc),'[]') from (
 select * from (
  select m.id,'battle'::text mode,m.created_at played_at,mp.score,mp.result,
   opponent.full_name title,opponent.avatar_url
  from public.match_players mp join public.matches m on m.id=mp.match_id
  join public.profiles opponent on opponent.id=case when m.player1_id=uid then m.player2_id else m.player1_id end
  where mp.user_id=uid and m.status='completed'
  union all
  select p.id,'practice',p.started_at,p.score,null,'Practice',null::text from public.practice_attempts p where p.user_id=uid and p.completed_at is not null
  union all
  select a.id,'daily',a.started_at,a.score,null,c.title,null::text from public.daily_attempts a join public.daily_challenges c on c.id=a.challenge_id
  where a.user_id=uid and a.completed_at is not null
 ) history where before_at is null or (played_at,id)<(before_at,before_id)
 order by played_at desc,id desc limit 30) r));
end $$;

create or replace function public.admin_user_page(search text default '', after_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('rows',(select coalesce(jsonb_agg(u order by u.id),'[]') from (
   select p.id,p.full_name,p.avatar_url,p.username,p.email,p.phone,p.target_exam,p.rating,p.xp,p.level,p.current_streak,p.best_streak,
     p.last_daily_date,p.profile_completed,p.is_banned,p.created_at,p.updated_at,
     coalesce((select a.role from public.admin_users a where a.is_active and a.email=p.email),'student') role
   from public.profiles p where not p.is_bot and p.deleted_at is null and (after_id is null or p.id>after_id)
     and (search='' or concat_ws(' ',p.full_name,p.email,p.phone) ilike '%'||search||'%')
   order by p.id limit 100
 ) u));
end $$;

commit;
