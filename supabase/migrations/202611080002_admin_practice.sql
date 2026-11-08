create function sj_private.require_admin(min_role text default 'viewer') returns void language plpgsql security definer set search_path='' as $$
begin if not public.is_admin(min_role) then raise exception 'ADMIN_REQUIRED' using errcode='42501'; end if; end $$;
create function sj_private.audit(action text, entity text, entity_id text, diff jsonb) returns void language sql security definer set search_path='' as $$
 insert into public.audit_logs(admin_id,action,entity,entity_id,diff) values(auth.uid(),action,entity,entity_id,diff)
$$;
create function public.admin_questions(search text default '', category_id uuid default null, page_before timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform sj_private.require_admin();
 select coalesce(jsonb_agg(row),'[]') into result from (
 select q.*, (select jsonb_agg(to_jsonb(o) order by sort_order) from public.question_options o where o.question_id=q.id) options,
 (select c.name from public.categories c where c.id=q.category_id) category_name
 from public.questions q where (admin_questions.category_id is null or q.category_id=admin_questions.category_id)
 and (search='' or q.question_text ilike '%'||search||'%') and (page_before is null or q.created_at<page_before)
 order by q.created_at desc,q.id limit 100) row;
 return jsonb_build_object('questions',result);
end $$;
create function public.admin_save_question(payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare qid uuid=coalesce((payload->>'id')::uuid,gen_random_uuid()); before_data jsonb; opt jsonb; idx int=0; n int;
begin
 perform sj_private.require_admin('editor');
 select to_jsonb(q) into before_data from public.questions q where id=qid for update;
 if exists(select 1 from public.match_questions where question_id=qid) or exists(select 1 from public.daily_challenge_questions where question_id=qid)
 then raise exception 'QUESTION_ALREADY_USED_DUPLICATE_INSTEAD'; end if;
 if jsonb_typeof(payload->'options')<>'array' or jsonb_array_length(payload->'options') not between 2 and 6 then raise exception 'INVALID_OPTIONS'; end if;
 select count(*) filter(where (value->>'is_correct')::boolean),count(distinct lower(trim(value->>'option_text')))
 into idx,n from jsonb_array_elements(payload->'options');
 if idx<>1 or n<>jsonb_array_length(payload->'options') or exists(select 1 from jsonb_array_elements(payload->'options') where length(trim(value->>'option_text'))=0)
 then raise exception 'ONE_CORRECT_AND_UNIQUE_OPTIONS_REQUIRED'; end if;
 insert into public.questions(id,category_id,subtopic_id,question_text,image_url,difficulty,time_limit_seconds,explanation,status,created_by)
 values(qid,(payload->>'category_id')::uuid,(payload->>'subtopic_id')::uuid,trim(payload->>'question_text'),payload->>'image_url',payload->>'difficulty',
 (payload->>'time_limit_seconds')::int,payload->>'explanation',payload->>'status',auth.uid())
 on conflict(id) do update set category_id=excluded.category_id,subtopic_id=excluded.subtopic_id,question_text=excluded.question_text,image_url=excluded.image_url,
 difficulty=excluded.difficulty,time_limit_seconds=excluded.time_limit_seconds,explanation=excluded.explanation,status=excluded.status;
 delete from public.question_options where question_id=qid;
 idx=0;
 for opt in select value from jsonb_array_elements(payload->'options') loop
 insert into public.question_options(question_id,option_text,image_url,is_correct,sort_order)
 values(qid,trim(opt->>'option_text'),opt->>'image_url',(opt->>'is_correct')::boolean,idx); idx=idx+1;
 end loop;
 perform sj_private.audit('save','questions',qid::text,jsonb_build_object('before',before_data,'after',payload));
 return qid;
end $$;
create function public.admin_save_category(payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid=coalesce((payload->>'id')::uuid,gen_random_uuid()); before_data jsonb;
begin
 perform sj_private.require_admin('editor');
 select to_jsonb(c) into before_data from public.categories c where id=cid;
 insert into public.categories(id,name,slug,icon,color_hex,sort_order,is_active)
 values(cid,payload->>'name',payload->>'slug',coalesce(payload->>'icon','public'),coalesce(payload->>'color_hex','#5B4CFF'),
 coalesce((payload->>'sort_order')::int,0),coalesce((payload->>'is_active')::boolean,true))
 on conflict(id) do update set name=excluded.name,slug=excluded.slug,icon=excluded.icon,color_hex=excluded.color_hex,sort_order=excluded.sort_order,is_active=excluded.is_active;
 perform sj_private.audit('save','categories',cid::text,jsonb_build_object('before',before_data,'after',payload)); return cid;
end $$;
create function public.admin_list_users(search text default '') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('users',(select coalesce(jsonb_agg(row),'[]') from (
 select id,full_name,email,phone,rating,level,is_banned,created_at from public.profiles where not is_bot and (search='' or full_name ilike '%'||search||'%' or email ilike '%'||search||'%')
 order by created_at desc limit 100) row),
 'admins',case when public.is_admin('super_admin') then (select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.admin_users a) else '[]'::jsonb end);
end $$;
create function public.admin_set_role(email text, role text, is_active boolean default true) returns void language plpgsql security definer set search_path='' as $$
declare target text=lower(trim(email));
begin
 perform sj_private.require_admin('super_admin');
 -- Serialize role changes to prevent two admins concurrently removing the final super admin.
 perform pg_advisory_xact_lock(hashtext('sj_admin_roles'));
 if role not in ('super_admin','editor','viewer') or target !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'INVALID_ADMIN'; end if;
 if exists(select 1 from public.admin_users a where a.email=target and a.role='super_admin' and a.is_active)
 and (not is_active or role<>'super_admin') and (select count(*) from public.admin_users where admin_users.role='super_admin' and admin_users.is_active)<=1
 then raise exception 'KEEP_ONE_SUPER_ADMIN'; end if;
 insert into public.admin_users(email,role,is_active,created_by) values(target,role,is_active,auth.uid())
 on conflict on constraint admin_users_email_key do update set role=excluded.role,is_active=excluded.is_active;
 perform sj_private.audit('set_role','admin_users',target,jsonb_build_object('role',role,'is_active',is_active));
end $$;
create function public.admin_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('students',(select count(*) from public.profiles where not is_bot),'questions',(select count(*) from public.questions where status='published'),
 'matches',(select count(*) from public.matches where created_at>date_trunc('day',now())),
 'reports',(select count(*) from public.question_reports where status='open'),
 'short_categories',(select coalesce(jsonb_agg(row),'[]') from (select c.name,count(q.id) from public.categories c left join public.questions q on q.category_id=c.id and q.status='published' group by c.id having count(q.id)<10) row));
end $$;

create function public.start_practice(category_id uuid default null, subtopic_id uuid default null, timed boolean default true) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); aid uuid; qs jsonb;
begin
 perform sj_private.rate_limit('practice',15);
 select jsonb_agg(sj_private.question_snapshot(q.id)) into qs from (
 select id from public.questions q where q.status='published' and (start_practice.category_id is null or q.category_id=start_practice.category_id)
 and (start_practice.subtopic_id is null or q.subtopic_id=start_practice.subtopic_id) order by random() limit 10) q;
 if qs is null then raise exception 'NO_PUBLISHED_QUESTIONS'; end if;
 insert into public.practice_attempts(user_id,timed,questions) values(uid,timed,qs) returning id into aid;
 return jsonb_build_object('attempt_id',aid,'question_count',jsonb_array_length(qs),'question_index',0,
 'question',sj_private.safe_question(qs->0)||jsonb_build_object('deadline_at',case when timed then now()+make_interval(secs=>(qs->0->>'time_limit_seconds')::int) else null end));
end $$;
create function public.submit_practice_answer(attempt_id uuid, question_index int, option_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); a public.practice_attempts; q jsonb; response jsonb; correct boolean; elapsed int; points int;
begin
 perform sj_private.rate_limit('answer',120);
 select * into a from public.practice_attempts where id=attempt_id and user_id=uid for update;
 if not found then raise exception 'ATTEMPT_NOT_FOUND' using errcode='42501'; end if;
 if question_index<0 or question_index>=jsonb_array_length(a.questions) then raise exception 'INVALID_INDEX'; end if;
 if question_index<jsonb_array_length(a.answers) then return a.answers->question_index; end if;
 if a.current_index<>question_index or a.completed_at is not null then raise exception 'QUESTION_NOT_ACTIVE'; end if;
 q=a.questions->question_index;
 if option_id is not null and not exists(select 1 from jsonb_array_elements(q->'options') where value->>'id'=option_id::text) then raise exception 'INVALID_OPTION'; end if;
 elapsed=greatest(0,floor(extract(epoch from (clock_timestamp()-a.current_started_at))*1000)::int);
 correct=coalesce(option_id::text=q->>'correct_option_id',false) and (not a.timed or elapsed<=(q->>'time_limit_seconds')::int*1000+500);
 points=sj_private.score(correct,case when a.timed then elapsed else (q->>'time_limit_seconds')::int*1000 end,(q->>'time_limit_seconds')::int,question_index=jsonb_array_length(a.questions)-1);
 response=jsonb_build_object('correct_option_id',q->>'correct_option_id','explanation',q->>'explanation','is_correct',correct,'points',points,'selected_option_id',option_id);
 update public.practice_attempts set answers=answers||jsonb_build_array(response),score=score+points,correct_count=correct_count+correct::int where id=attempt_id;
 return response;
end $$;
create function public.get_practice_question(attempt_id uuid, question_index int) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); a public.practice_attempts; q jsonb;
begin
 select * into a from public.practice_attempts where id=attempt_id and user_id=uid for update;
 if not found or a.completed_at is not null then raise exception 'ATTEMPT_NOT_FOUND'; end if;
 if question_index<0 or question_index>=jsonb_array_length(a.questions) or question_index<>jsonb_array_length(a.answers) then raise exception 'QUESTION_NOT_ACTIVE'; end if;
 if a.current_index<>question_index then update public.practice_attempts set current_index=question_index,current_started_at=now() where id=attempt_id returning * into a; end if;
 q=a.questions->question_index;
 return sj_private.safe_question(q)||jsonb_build_object('deadline_at',case when a.timed then a.current_started_at+make_interval(secs=>(q->>'time_limit_seconds')::int) else null end);
end $$;
create function public.finish_practice(attempt_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); a public.practice_attempts;
begin
 select * into a from public.practice_attempts where id=attempt_id and user_id=uid for update;
 if not found or jsonb_array_length(a.answers)<>jsonb_array_length(a.questions) then raise exception 'ROUND_NOT_COMPLETE'; end if;
 update public.practice_attempts set completed_at=coalesce(completed_at,now()) where id=attempt_id;
 return jsonb_build_object('score',a.score,'correct_count',a.correct_count);
end $$;

revoke all on all functions in schema sj_private from public,anon,authenticated;
revoke all on function public.admin_questions(text,uuid,timestamptz),public.admin_save_question(jsonb),public.admin_save_category(jsonb),
 public.admin_list_users(text),public.admin_set_role(text,text,boolean),public.admin_dashboard(),
 public.start_practice(uuid,uuid,boolean),public.submit_practice_answer(uuid,int,uuid),public.get_practice_question(uuid,int),public.finish_practice(uuid) from public,anon;
grant execute on function public.admin_questions(text,uuid,timestamptz),public.admin_save_question(jsonb),public.admin_save_category(jsonb),
 public.admin_list_users(text),public.admin_set_role(text,text,boolean),public.admin_dashboard(),
 public.start_practice(uuid,uuid,boolean),public.submit_practice_answer(uuid,int,uuid),public.get_practice_question(uuid,int),public.finish_practice(uuid) to authenticated;
