begin;

-- Total XP remains cumulative. Recalculate only the displayed level for
-- real players using thresholds 0, 100, 250, 450, 700, ...
create function sj_private.level_for_xp(total_xp integer) returns integer
language sql immutable set search_path='' as $$
 select 1 + floor((sqrt(9 + 4 * greatest(total_xp,0)::numeric / 25) - 3) / 2)::integer
$$;
revoke all on function sj_private.level_for_xp(integer) from public,anon,authenticated;

update public.profiles
set level=sj_private.level_for_xp(xp)
where not is_bot and level is distinct from sj_private.level_for_xp(xp);

-- NULL distinguishes historical completions, whose XP was not stored per
-- attempt, from new completions, including a legitimate zero-XP award.
alter table public.daily_attempts add column xp_gained integer
 check (xp_gained between 0 and 24);

create or replace function sj_private.finalize_match(mid uuid, forced_winner uuid default null, abandoned boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare m public.matches; p record; winner uuid; s1 numeric; s2 numeric; t1 bigint; t2 bigint; actual numeric; delta int; reward int; ncorrect int;
begin
 select * into m from public.matches where id=mid for update;
 if m.status in ('completed','abandoned') then return; end if;
 if abandoned then update public.matches set status='abandoned',phase='finished',ended_at=now() where id=mid; return; end if;
 select coalesce(sum(points),0),coalesce(sum(response_ms) filter(where is_correct),0) into s1,t1 from public.match_answers where match_id=mid and user_id=m.player1_id;
 select coalesce(sum(points),0),coalesce(sum(response_ms) filter(where is_correct),0) into s2,t2 from public.match_answers where match_id=mid and user_id=m.player2_id;
 winner=coalesce(forced_winner,case when s1>s2 or (s1=s2 and t1<t2) then m.player1_id when s2>s1 or (s1=s2 and t2<t1) then m.player2_id else null end);
 for p in select mp.*,pr.is_bot from public.match_players mp join public.profiles pr on pr.id=mp.user_id where match_id=mid order by mp.user_id loop
 actual=case when winner is null then .5 when winner=p.user_id then 1 else 0 end;
 delta=sj_private.trophy_delta(actual);
 select count(*) into ncorrect from public.match_answers where match_id=mid and user_id=p.user_id and is_correct;
 reward=(case actual when 1 then 20 when .5 then 12 else 5 end)+3*least(ncorrect,4);
 update public.match_players set score=case when p.user_id=m.player1_id then s1 else s2 end,
 rating_after=greatest(0,p.rating_before+delta),xp_gained=reward,result=case actual when 1 then 'win' when .5 then 'draw' else 'loss' end where id=p.id;
 if not p.is_bot then
 update public.profiles set rating=greatest(0,rating+delta),xp=xp+reward,
  level=sj_private.level_for_xp(xp+reward) where id=p.user_id;
 insert into public.user_category_stats(user_id,category_id,played,correct,total_time_ms)
 select p.user_id,(mq.snapshot->>'category_id')::uuid,count(*),count(*) filter(where a.is_correct),coalesce(sum(a.response_ms),0)
 from public.match_questions mq left join public.match_answers a on a.match_id=mq.match_id and a.question_index=mq.question_index and a.user_id=p.user_id
 where mq.match_id=mid group by mq.snapshot->>'category_id'
 on conflict(user_id,category_id) do update set played=user_category_stats.played+excluded.played,correct=user_category_stats.correct+excluded.correct,total_time_ms=user_category_stats.total_time_ms+excluded.total_time_ms;
 end if;
 end loop;
 update public.matches set status='completed',phase='finished',winner_id=winner,ended_at=now() where id=mid;
 perform sj_private.emit(mid,'match_end',jsonb_build_object('match_id',mid));
end $$;

create or replace function sj_private.finish_daily(aid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.daily_attempts; p public.profiles; day date; streak int; week date; freezes int; reward int;
begin
 select * into a from public.daily_attempts where id=aid for update;
 if not found then raise exception 'ATTEMPT_NOT_FOUND'; end if;
 if a.completed_at is null then
  if exists(select 1 from sj_private.daily_windows(aid) w
    where not w.answered and w.closes_at+interval '500 milliseconds'>clock_timestamp())
  then raise exception 'ROUND_NOT_COMPLETE'; end if;
  update public.daily_attempts set score=(select coalesce(sum(points),0) from public.daily_attempt_answers where attempt_id=aid),
   correct_count=(select count(*) from public.daily_attempt_answers where attempt_id=aid and is_correct),
   total_time_ms=(select coalesce(sum(coalesce(ans.response_ms,(q.snapshot->>'time_limit_seconds')::int*1000)),0)
    from public.daily_challenge_questions q left join public.daily_attempt_answers ans
    on ans.attempt_id=aid and ans.question_index=q.question_index where q.challenge_id=a.challenge_id),
   completed_at=now() where id=aid returning * into a;
  select * into p from public.profiles where id=a.user_id for update;
  select challenge_date into day from public.daily_challenges where id=a.challenge_id;
  week=date_trunc('week',day::timestamp)::date;
  freezes=case when p.freeze_week is distinct from week then 1 else p.streak_freezes end;
  streak=case when p.last_daily_date=day-1 then p.current_streak+1 when p.last_daily_date=day-2 and freezes>0 then p.current_streak+1 else 1 end;
  if p.last_daily_date=day-2 and freezes>0 then freezes=freezes-1; end if;
  reward=0;
  if p.last_daily_date is null or p.last_daily_date<day then
   reward=12+3*least(a.correct_count,4);
   update public.profiles set current_streak=streak,best_streak=greatest(best_streak,streak),last_daily_date=day,
    streak_freezes=freezes,freeze_week=week,xp=xp+reward,
    level=sj_private.level_for_xp(xp+reward) where id=a.user_id;
   insert into public.user_badges(user_id,badge_id) select a.user_id,id from public.badges
    where milestone<=streak on conflict(user_id,badge_id) do nothing;
  end if;
  update public.daily_attempts set xp_gained=reward where id=aid returning * into a;
 end if;
 return jsonb_build_object('score',a.score,'correct_count',a.correct_count,'xp_gained',a.xp_gained);
end $$;

-- Keep the existing RPC name, arguments and response keys for older clients.
-- New clients can use the additive xp_gained field.
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
  'xp_gained',a.xp_gained,
  'question',case when a.completed_at is null then sj_private.daily_question(a.id,idx) else null end);
end $$;

commit;
