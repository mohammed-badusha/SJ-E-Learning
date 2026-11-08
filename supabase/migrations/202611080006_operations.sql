create function public.run_match_tick() returns void language sql security definer set search_path='' as $$ select sj_private.tick_all() $$;
revoke all on function public.run_match_tick() from public,anon,authenticated;
grant execute on function public.run_match_tick() to service_role;
-- Stop new rounds during maintenance, while keeping existing matches playable.
create function sj_private.enforce_maintenance() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (select value='true'::jsonb from public.app_settings where key='maintenance_mode') and not public.is_admin('super_admin')
 then raise exception 'MAINTENANCE_MODE'; end if; return new;
end $$;
create trigger maintenance_queue before insert on public.matchmaking_queue for each row execute function sj_private.enforce_maintenance();
create trigger maintenance_practice before insert on public.practice_attempts for each row execute function sj_private.enforce_maintenance();
create trigger maintenance_daily before insert on public.daily_attempts for each row execute function sj_private.enforce_maintenance();
revoke all on all functions in schema sj_private from public,anon,authenticated;
