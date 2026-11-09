select jsonb_build_object(
 'cron',(select jsonb_agg(jsonb_build_object('name',jobname,'schedule',schedule,'command',command,'active',active)) from cron.job where jobname like 'sj-%'),
 'subjects',(select jsonb_agg(jsonb_build_object('slug',c.slug,'published', (select count(*) from public.questions q where q.category_id=c.id and q.status='published'))) from public.categories c),
 'non_four_option_questions',(select count(*) from public.questions q where (select count(*) from public.question_options o where o.question_id=q.id)<>4),
 'active_matches',(select count(*) from public.matches where status in ('pending','in_progress'))
) preflight;
