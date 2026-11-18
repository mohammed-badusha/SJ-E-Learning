-- Match, daily, and practice attempts already hold full question snapshots.
-- Editing the catalog row and its options under this row lock changes future
-- selections only; existing snapshots, answer IDs, and scores stay untouched.
create or replace function public.admin_save_question(payload jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare qid uuid=coalesce((payload->>'id')::uuid,gen_random_uuid()); before_data jsonb;
  opt jsonb; idx int; distinct_options int; category uuid=(payload->>'category_id')::uuid;
  topic uuid=(payload->>'subtopic_id')::uuid; difficulty text=lower(trim(payload->>'difficulty'));
begin
 perform sj_private.require_admin('editor');
 if category is null or topic is null or not exists
   (select 1 from public.subtopics s join public.categories c on c.id=s.category_id
    where s.id=topic and s.category_id=category and s.is_active and c.is_active)
 then raise exception 'VALID_SUBJECT_AND_TOPIC_REQUIRED'; end if;
 if length(trim(coalesce(payload->>'question_text','')))<4 or difficulty not in ('easy','medium','hard')
 then raise exception 'INVALID_QUESTION_OR_DIFFICULTY'; end if;
 if jsonb_typeof(payload->'options') is distinct from 'array' or jsonb_array_length(payload->'options')<>4
 then raise exception 'FOUR_OPTIONS_REQUIRED'; end if;
 select count(*) filter(where (value->>'is_correct')::boolean),
   count(distinct lower(trim(value->>'option_text'))) into idx,distinct_options
 from jsonb_array_elements(payload->'options');
 if idx<>1 or distinct_options<>4 or exists
   (select 1 from jsonb_array_elements(payload->'options') where length(trim(coalesce(value->>'option_text','')))=0)
 then raise exception 'ONE_CORRECT_AND_UNIQUE_OPTIONS_REQUIRED'; end if;
 select to_jsonb(q) into before_data from public.questions q where id=qid for update;
 insert into public.questions(id,category_id,subtopic_id,question_text,image_url,difficulty,
   time_limit_seconds,explanation,status,created_by,exam)
 values(qid,category,topic,trim(payload->>'question_text'),payload->>'image_url',difficulty,
   15,coalesce(trim(payload->>'explanation'),''),'published',auth.uid(),null)
 on conflict(id) do update set category_id=excluded.category_id,subtopic_id=excluded.subtopic_id,
   question_text=excluded.question_text,image_url=excluded.image_url,difficulty=excluded.difficulty,
   time_limit_seconds=15,explanation=excluded.explanation,status='published',exam=null;
 delete from public.question_options where question_id=qid;
 idx=0;
 for opt in select value from jsonb_array_elements(payload->'options') loop
   insert into public.question_options(question_id,option_text,is_correct,sort_order)
   values(qid,trim(opt->>'option_text'),(opt->>'is_correct')::boolean,idx);
   idx=idx+1;
 end loop;
 perform sj_private.audit('save','questions',qid::text,jsonb_build_object('before',before_data,'after',payload));
 return qid;
end $$;
