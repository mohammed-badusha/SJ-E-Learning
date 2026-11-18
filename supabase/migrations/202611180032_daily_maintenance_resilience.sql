-- A temporarily empty subject must not prevent expired attempts from
-- completing. Question generation can resume once staff add content.
create or replace function sj_private.daily_maintenance() returns void
language plpgsql security definer set search_path='' as $$
declare a record;
begin
 begin
  perform sj_private.generate_daily((now() at time zone 'Asia/Kolkata')::date+1);
 exception when raise_exception then
  if sqlerrm <> 'NOT_ENOUGH_QUESTIONS' then raise; end if;
 end;
 for a in select d.id from public.daily_attempts d
  where d.completed_at is null and now()>d.started_at+
   make_interval(secs=>(select sum((snapshot->>'time_limit_seconds')::int)
    from public.daily_challenge_questions where challenge_id=d.challenge_id)::double precision)
   +interval '1 second'
 loop
  perform sj_private.finish_daily(a.id);
 end loop;
end $$;
