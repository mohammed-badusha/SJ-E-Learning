-- Supabase Cron runs the game even if every client closes. No client owns advancement.
create extension if not exists pg_cron;
select cron.schedule('sj-match-engine','1 second','select sj_private.tick_all()');
select cron.schedule('sj-daily-resume','* * * * *','select sj_private.daily_maintenance()');
-- 23:55 IST = 18:25 UTC. Ensure tomorrow's common challenge exists.
select cron.schedule('sj-daily-generate','25 18 * * *','select sj_private.generate_daily((now() at time zone ''Asia/Kolkata'')::date+1)');
