create or replace function sj_private.finish_daily(aid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.daily_attempts; p public.profiles; day date; streak int; week date; freezes int;
begin
 select * into a from public.daily_attempts where id=aid for update;
 if not found then raise exception 'ATTEMPT_NOT_FOUND'; end if;
 if a.completed_at is null then
 -- An answered final question is complete even when earlier questions timed out while the app was closed.
 if exists(select 1 from sj_private.daily_windows(aid) w
   where not w.answered and w.closes_at+interval '500 milliseconds'>clock_timestamp())
 then raise exception 'ROUND_NOT_COMPLETE'; end if;
 update public.daily_attempts set score=(select coalesce(sum(points),0) from public.daily_attempt_answers where attempt_id=aid),
 correct_count=(select count(*) from public.daily_attempt_answers where attempt_id=aid and is_correct),
 total_time_ms=(select coalesce(sum(coalesce(ans.response_ms,(q.snapshot->>'time_limit_seconds')::int*1000)),0) from public.daily_challenge_questions q left join public.daily_attempt_answers ans on ans.attempt_id=aid and ans.question_index=q.question_index where q.challenge_id=a.challenge_id),
 completed_at=now() where id=aid returning * into a;
 select * into p from public.profiles where id=a.user_id for update;
 select challenge_date into day from public.daily_challenges where id=a.challenge_id;
 week=date_trunc('week',day::timestamp)::date;
 freezes=case when p.freeze_week is distinct from week then 1 else p.streak_freezes end;
 streak=case when p.last_daily_date=day-1 then p.current_streak+1 when p.last_daily_date=day-2 and freezes>0 then p.current_streak+1 else 1 end;
 if p.last_daily_date=day-2 and freezes>0 then freezes=freezes-1; end if;
 if p.last_daily_date is null or p.last_daily_date<day then
 update public.profiles set current_streak=streak,best_streak=greatest(best_streak,streak),last_daily_date=day,streak_freezes=freezes,freeze_week=week,
 xp=xp+30+a.correct_count*5,level=1+(xp+30+a.correct_count*5)/100 where id=a.user_id;
 insert into public.user_badges(user_id,badge_id) select a.user_id,id from public.badges where milestone<=streak on conflict(user_id,badge_id) do nothing;
 end if;
 end if;
 return jsonb_build_object('score',a.score,'correct_count',a.correct_count);
end $$;
