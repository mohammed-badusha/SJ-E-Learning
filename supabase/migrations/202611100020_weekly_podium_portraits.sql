begin;

-- A stable tie order makes the portrait endpoint and visible podium agree.
create or replace function public.get_leaderboard(type text default 'all_time', category_id uuid default null, result_limit int default 100) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); rows jsonb;
begin
 if type not in ('all_time','weekly','daily') then raise exception 'INVALID_LEADERBOARD'; end if;
 with ranked as (
 select p.id,p.full_name,p.level,p.rating,
 case when type='daily' then coalesce(d.score,0) when type='weekly' then coalesce(w.points,0) else p.rating end metric,
 rank() over(order by case when type='daily' then coalesce(d.score,0) when type='weekly' then coalesce(w.points,0) else p.rating end desc,coalesce(d.total_time_ms,0)) rank
 from public.profiles p
 left join public.daily_attempts d on d.user_id=p.id and d.completed_at is not null and d.challenge_id=(select id from public.daily_challenges where challenge_date=(now() at time zone 'Asia/Kolkata')::date)
 left join lateral(select sum(mp.score) points from public.match_players mp join public.matches m on m.id=mp.match_id where mp.user_id=p.id and m.status='completed'
 and (get_leaderboard.category_id is null or m.category_id=get_leaderboard.category_id)
 and m.ended_at>=date_trunc('week',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata') w on true
 where p.profile_completed and not p.is_bot and not p.is_banned and (type<>'daily' or d.id is not null)
 ) select coalesce(jsonb_agg(to_jsonb(r) order by rank,id),'[]') into rows from ranked r where rank<=least(greatest(result_limit,1),100) or id=uid;
 return jsonb_build_object('rows',rows);
end $$;

-- Return portraits only for the three weekly leaders. Gallery bytes stay in
-- the private table and are never included in the general leaderboard query.
create function public.get_weekly_podium_portraits() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  perform sj_private.require_player();
  select jsonb_build_object('rows',coalesce(jsonb_agg(
    jsonb_build_object(
      'id',leaders.id,
      'avatar_url',leaders.avatar_url,
      'photo_png',case when leaders.avatar_url='photo:'||photos.photo_id::text
        then replace(encode(photos.thumbnail,'base64'),chr(10),'') end
    ) order by leaders.points desc,leaders.id
  ),'[]'::jsonb)) into result
  from (
    select p.id,p.avatar_url,coalesce(w.points,0) points
    from public.profiles p
    left join lateral (
      select sum(mp.score) points
      from public.match_players mp join public.matches m on m.id=mp.match_id
      where mp.user_id=p.id and m.status='completed'
        and m.ended_at>=date_trunc('week',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'
    ) w on true
    where p.profile_completed and not p.is_bot and not p.is_banned
    order by coalesce(w.points,0) desc,p.id
    limit 3
  ) leaders
  left join sj_private.player_photos photos on photos.owner_id=leaders.id;
  return result;
end $$;

revoke all on function public.get_weekly_podium_portraits() from public,anon,authenticated;
grant execute on function public.get_weekly_podium_portraits() to authenticated;

create trigger podium_identity_changed
after update of avatar_url,full_name on public.profiles
for each statement execute function sj_private.notify_standings();

commit;
