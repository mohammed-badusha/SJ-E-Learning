begin;

-- Avatar references can remain the same (notably Google photos), so expose a
-- version that changes only when the stored picture reference changes.
alter table public.profiles add column avatar_revision integer not null default 0;
create function sj_private.bump_avatar_revision() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.avatar_url is distinct from old.avatar_url then
  new.avatar_revision=old.avatar_revision+1;
 end if;
 return new;
end $$;
create trigger bump_avatar_revision before update of avatar_url on public.profiles
for each row execute function sj_private.bump_avatar_revision();
revoke all on function sj_private.bump_avatar_revision() from public,anon,authenticated;

create index matches_weekly_leaderboard on public.matches(ended_at,id)
 include(category_id) where status='completed';
create index profiles_eligible_rating on public.profiles(rating desc,id)
 where profile_completed and not is_bot and not is_banned and deleted_at is null;

-- One response contains rank, display name and avatar reference for every
-- visible row. Aggregate this week's matches once instead of once per user.
create or replace function public.get_leaderboard(
 type text default 'all_time', category_id uuid default null, result_limit int default 100
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); rows jsonb;
begin
 if type not in ('all_time','weekly','daily') then raise exception 'INVALID_LEADERBOARD'; end if;
 with weekly_scores as (
   select mp.user_id,sum(mp.score) points
   from public.matches m
   join public.match_players mp on mp.match_id=m.id
   where get_leaderboard.type='weekly' and m.status='completed'
     and m.ended_at>=date_trunc('week',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'
     and (get_leaderboard.category_id is null or m.category_id=get_leaderboard.category_id)
   group by mp.user_id
 ), daily_scores as (
   select a.user_id,a.score,a.total_time_ms
   from public.daily_attempts a
   join public.daily_challenges c on c.id=a.challenge_id
   where get_leaderboard.type='daily' and a.completed_at is not null
     and c.challenge_date=(now() at time zone 'Asia/Kolkata')::date
 ), ranked as (
   select p.id,p.full_name,p.username,p.level,p.rating,p.trophies,
     p.avatar_url,p.avatar_revision,
     case when type='daily' then coalesce(d.score,0)
          when type='weekly' then coalesce(w.points,0) else p.trophies end metric,
     rank() over(order by
       case when type='daily' then coalesce(d.score,0)
            when type='weekly' then coalesce(w.points,0) else p.trophies end desc,
       coalesce(d.total_time_ms,0)) rank
   from public.profiles p
   left join daily_scores d on d.user_id=p.id
   left join weekly_scores w on w.user_id=p.id
   where p.profile_completed and not p.is_bot and not p.is_banned
     and p.deleted_at is null and (type<>'daily' or d.user_id is not null)
 )
 select coalesce(jsonb_agg(to_jsonb(r) order by rank,id),'[]'::jsonb)
 into rows from ranked r
 where rank<=least(greatest(result_limit,1),100) or id=uid;
 return jsonb_build_object('rows',rows);
end $$;

commit;
