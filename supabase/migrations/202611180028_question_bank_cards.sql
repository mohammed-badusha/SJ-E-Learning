-- Keep the bank list light. Options and explanations are fetched only when a
-- staff member expands a card. Archived rows remain for historical references.
create or replace function public.admin_question_groups(search text default '') returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('categories',(select coalesce(jsonb_agg(g order by g.name),'[]') from (
   select c.id,c.name,count(q.id) question_count from public.categories c left join public.questions q
   on q.category_id=c.id and q.status<>'archived'
   and (q.question_text ilike '%'||search||'%' or exists
     (select 1 from public.subtopics t where t.id=q.subtopic_id and t.name ilike '%'||search||'%'))
   group by c.id having search='' or count(q.id)>0
 ) g));
end $$;

create or replace function public.admin_question_page(subject_id uuid, search text default '', after_id uuid default null)
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

create function public.admin_question_detail(question_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare detail jsonb;
begin
 perform sj_private.require_admin();
 select to_jsonb(q)||jsonb_build_object(
  'category_name',c.name,'topic_name',t.name,
  'options',(select coalesce(jsonb_agg(o order by o.sort_order),'[]')
             from public.question_options o where o.question_id=q.id)) into detail
 from public.questions q join public.categories c on c.id=q.category_id
 left join public.subtopics t on t.id=q.subtopic_id
 where q.id=question_id and q.status<>'archived';
 if detail is null then raise exception 'QUESTION_NOT_FOUND'; end if;
 return detail;
end $$;

create function public.admin_archive_question(question_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare previous public.questions;
begin
 perform sj_private.require_admin('editor');
 select * into previous from public.questions where id=question_id for update;
 if not found then raise exception 'QUESTION_NOT_FOUND'; end if;
 if previous.status='archived' then return false; end if;
 update public.questions set status='archived' where id=question_id;
 perform sj_private.audit('archive','questions',question_id::text,
  jsonb_build_object('previous_status',previous.status));
 return true;
end $$;

create index if not exists questions_bank_visible_page
on public.questions(category_id,id) where status<>'archived';
revoke all on function public.admin_question_detail(uuid),public.admin_archive_question(uuid)
from public,anon;
grant execute on function public.admin_question_detail(uuid),public.admin_archive_question(uuid)
to authenticated;
