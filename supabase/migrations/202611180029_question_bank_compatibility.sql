-- Existing installed APKs still use admin_question_page rows as edit payloads.
-- Give the new expandable bank its own lightweight endpoint.
create function public.admin_question_summary_page(subject_id uuid, search text default '', after_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object(
  'total',(select count(*) from public.questions q left join public.subtopics t on t.id=q.subtopic_id
   where q.status<>'archived' and (subject_id is null or q.category_id=subject_id)
   and (q.question_text ilike '%'||search||'%' or t.name ilike '%'||search||'%')),
  'rows',(select coalesce(jsonb_agg(r order by r.id),'[]') from (
   select q.id,q.question_text,q.difficulty,c.name category_name,t.name topic_name
   from public.questions q join public.categories c on c.id=q.category_id
   left join public.subtopics t on t.id=q.subtopic_id
   where q.status<>'archived' and (subject_id is null or q.category_id=subject_id)
   and (q.question_text ilike '%'||search||'%' or t.name ilike '%'||search||'%')
   and (after_id is null or q.id>after_id)
   order by q.id limit 50
  ) r));
end $$;

create or replace function public.admin_question_page(subject_id uuid, search text default '', after_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('rows',(select coalesce(jsonb_agg(r order by r.id),'[]') from (
   select q.*,t.name topic_name,
    (select jsonb_agg(o order by o.sort_order) from public.question_options o where o.question_id=q.id) options
   from public.questions q left join public.subtopics t on t.id=q.subtopic_id
   where q.category_id=subject_id and q.status<>'archived'
   and q.question_text ilike '%'||search||'%'
   and (after_id is null or q.id>after_id)
   order by q.id limit 50
 ) r));
end $$;

revoke all on function public.admin_question_summary_page(uuid,text,uuid) from public,anon;
grant execute on function public.admin_question_summary_page(uuid,text,uuid) to authenticated;
