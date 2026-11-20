-- Realtime remains the fast path. This small read is a fallback when its
-- match_found event is missed; it does not repeat queue writes or rate limits.
begin;

create function public.get_matchmaking_status() returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); mid uuid; queued_at timestamptz;
begin
 select id into mid from public.matches
 where (player1_id=uid or player2_id=uid)
   and status in ('pending','in_progress') limit 1;
 if mid is not null then return jsonb_build_object('match_id',mid); end if;
 select joined_at into queued_at from public.matchmaking_queue where user_id=uid;
 return jsonb_build_object('match_id',null,'joined_at',queued_at,
  'server_now',clock_timestamp(),
  'search_timeout_seconds',coalesce((select value from public.app_settings
    where key='search_timeout_seconds'),'10'::jsonb));
end $$;

revoke all on function public.get_matchmaking_status() from public,anon;
grant execute on function public.get_matchmaking_status() to authenticated;

commit;
