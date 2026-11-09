select jsonb_build_object(
 'rules',(select jsonb_agg(to_jsonb(r) order by round_index) from public.battle_rounds r),
 'settings',(select jsonb_object_agg(key,value) from public.app_settings where key in ('search_timeout_seconds','questions_per_match','daily_question_count','label_bots')),
 'default_topics',(select count(*) from public.subtopics where topic_group is not null),
 'bot_names',(select count(*) from sj_private.bot_names),
 'unprotected_tables',(select count(*) from pg_tables where schemaname='public' and not rowsecurity),
 'score_instant',sj_private.battle_score(true,0,40),
 'score_half_time',sj_private.battle_score(true,20000,40),
 'score_timeout',sj_private.battle_score(false,40000,40),
 'migrations',(select jsonb_agg(version order by version) from supabase_migrations.schema_migrations)
) verification;
