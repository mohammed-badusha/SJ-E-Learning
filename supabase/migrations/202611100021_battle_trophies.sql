begin;

-- Reset all players to zero as requested. The old rating column remains a
-- compatibility source for matchmaking; trophies is its stored alias.
alter table public.profiles alter column rating set default 0;
update public.profiles set rating=0 where rating<>0;
update public.matchmaking_queue set rating=0 where rating<>0;
update public.match_players set rating_before=0
where match_id in (select id from public.matches where status in ('pending','in_progress'));
alter table public.profiles add column trophies integer generated always as (rating) stored;
alter table public.profiles add constraint profiles_trophies_nonnegative check (trophies >= 0);
grant select(trophies) on public.profiles to authenticated;

create function sj_private.trophy_delta(outcome numeric) returns integer
language sql immutable set search_path='' as $$
  select case outcome when 1 then 15 when 0 then -5 else 0 end;
$$;

-- Battle points select the winner; the trophy payout is fixed for both live
-- and bot matches. The completed/abandoned guard makes finalization idempotent.
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
 reward=(case actual when 1 then 50 when .5 then 30 else 20 end)+5*ncorrect;
 update public.match_players set score=case when p.user_id=m.player1_id then s1 else s2 end,
 rating_after=greatest(0,p.rating_before+delta),xp_gained=reward,result=case actual when 1 then 'win' when .5 then 'draw' else 'loss' end where id=p.id;
 if not p.is_bot then
 update public.profiles set rating=greatest(0,rating+delta),xp=xp+reward,level=1+(xp+reward)/100 where id=p.user_id;
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

-- The account and all-time ranking now expose the trophy count explicitly.
create or replace function public.get_leaderboard(type text default 'all_time', category_id uuid default null, result_limit int default 100) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); rows jsonb;
begin
 if type not in ('all_time','weekly','daily') then raise exception 'INVALID_LEADERBOARD'; end if;
 with ranked as (
 select p.id,p.full_name,p.level,p.rating,p.trophies,
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

revoke all on function sj_private.trophy_delta(numeric) from public,anon,authenticated;

commit;
