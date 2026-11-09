begin;
insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('668395b5-5411-5b0b-99a5-5efa80c18faf','Quantitative Aptitude','quant','calculate','#376BD6',0) on conflict(id) do nothing;
insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('d2c9217b-d3a7-5a4a-9815-c33704a25aff','English','english','translate','#087E83',1) on conflict(id) do nothing;
insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('09f88e78-88be-547c-9eb8-ef644b66db02','Reasoning','reasoning','psychology','#8051C5',2) on conflict(id) do nothing;
insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','General Awareness','general-awareness','public','#B66A13',3) on conflict(id) do nothing;
insert into public.subtopics(id,category_id,name,topic_group) select '0c965966-8a76-5cac-bc5d-0fac4c740c9d'::uuid,id,'Percentages','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select 'd8a04e6b-647a-5cfa-b2f2-2fbd91ef400d'::uuid,id,'Profit & Loss','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Ratio','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select '378d3bba-e539-57d4-9450-68034b1df9f7'::uuid,id,'Time & Work','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Speed & Distance','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'SI/CI','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Averages','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Number Systems','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Algebra','Advanced Maths' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Geometry','Advanced Maths' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Trigonometry','Advanced Maths' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Mensuration','Advanced Maths' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Data Interpretation','Advanced Maths' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Coding-Decoding','Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Blood Relations','Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Direction','Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Syllogisms','Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Analogies','Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Series','Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Mirror Images','Non-Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Paper Folding','Non-Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Puzzles','Non-Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Seating Arrangements','Non-Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Static GK','General Awareness' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'History','General Awareness' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Polity','General Awareness' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select 'c48ff9f3-c397-56fe-8ffd-e8af52ca6db0'::uuid,id,'Geography','General Awareness' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Economics','General Awareness' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Computer Awareness','General Awareness' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Current Affairs','General Awareness' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Physics','General Science' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Chemistry','General Science' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Biology','General Science' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Grammar rules','English' from public.categories where slug='english' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select '15ce5c00-e6c7-57c7-90b8-666779e61e99'::uuid,id,'Vocabulary','English' from public.categories where slug='english' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Idioms & Phrases','English' from public.categories where slug='english' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'One Word Substitution','English' from public.categories where slug='english' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Synonyms/Antonyms','English' from public.categories where slug='english' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Cloze Test','English' from public.categories where slug='english' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Reading Comprehension','English' from public.categories where slug='english' on conflict(category_id,name) do update set topic_group=excluded.topic_group;

create table public.user_preferences (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 settings jsonb not null default '{}' check(jsonb_typeof(settings)='object'),
 updated_at timestamptz not null default now()
);
alter table public.user_preferences enable row level security;
create policy own_preferences on public.user_preferences for select to authenticated using(user_id=auth.uid());
grant select on public.user_preferences to authenticated;
create function public.save_preferences(patch jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); result jsonb; k text;
begin
 if uid is null or not exists(select 1 from public.profiles where id=uid and not is_banned) then raise exception 'AUTH_REQUIRED'; end if;
 if jsonb_typeof(patch) is distinct from 'object' then raise exception 'INVALID_SETTINGS'; end if;
 for k in select jsonb_object_keys(patch) loop
 if k in ('haptics','sound_effects','music_enabled','notifications') then
 if jsonb_typeof(patch->k)<>'boolean' then raise exception 'INVALID_SETTINGS'; end if;
 elsif k in ('effects_volume','music_volume') then
 if jsonb_typeof(patch->k)<>'number' or (patch->>k)::numeric not between 0 and 1 then raise exception 'INVALID_SETTINGS'; end if;
 elsif k='theme' then
 if patch->>k not in ('0','1','2') then raise exception 'INVALID_SETTINGS'; end if;
 elsif k='category' then
 if patch->>k<>'mixed' and not exists(select 1 from public.categories where id::text=patch->>k and is_active) then raise exception 'INVALID_SETTINGS'; end if;
 else raise exception 'UNKNOWN_SETTING'; end if;
 end loop;
 insert into public.user_preferences(user_id,settings) values(uid,patch) on conflict(user_id)
 do update set settings=user_preferences.settings||excluded.settings,updated_at=clock_timestamp() returning settings into result;
 return result;
end $$;
revoke all on function public.save_preferences(jsonb) from public,anon;
grant execute on function public.save_preferences(jsonb) to authenticated;

-- Lightweight invalidations: never broadcast question text, answers, or personal data.
create function sj_private.notify_data_change() returns trigger language plpgsql security definer set search_path='' as $$
declare row_data jsonb=case when TG_OP='DELETE' then to_jsonb(old) else to_jsonb(new) end; owner text;
begin
 if TG_TABLE_NAME='match_players' and TG_OP='UPDATE' and (to_jsonb(old)-'heartbeat_at'-'updated_at')=(to_jsonb(new)-'heartbeat_at'-'updated_at') then return null; end if;
 if TG_TABLE_NAME in ('categories','subtopics','app_settings','battle_rounds','daily_challenges') then
 perform realtime.send(jsonb_build_object('table',TG_TABLE_NAME),'changed','data:catalog',true);
 elsif TG_TABLE_NAME='admin_users' then
 select id::text into owner from public.profiles where email=row_data->>'email';
 if owner is not null then perform realtime.send(jsonb_build_object('table',TG_TABLE_NAME),'changed','data:user:'||owner,true); end if;
 elsif TG_TABLE_NAME in ('profiles','user_preferences','practice_attempts','daily_attempts','match_players') then
 owner=case when TG_TABLE_NAME='profiles' then row_data->>'id' else row_data->>'user_id' end;
 perform realtime.send(jsonb_build_object('table',TG_TABLE_NAME),'changed','data:user:'||owner,true);
 end if;
 perform realtime.send(jsonb_build_object('table',TG_TABLE_NAME),'changed','data:admin',true);
 return null;
end $$;
do $$ declare t text; begin
 foreach t in array array['categories','subtopics','app_settings','battle_rounds','profiles','user_preferences','practice_attempts','daily_attempts','match_players','questions','admin_users'] loop
 execute format('create trigger data_changed after insert or update or delete on public.%I for each row execute function sj_private.notify_data_change()',t);
 end loop;
end $$;
create policy data_receive on realtime.messages for select to authenticated using(
 realtime.topic()='data:catalog' or realtime.topic()='data:user:'||auth.uid()::text or (realtime.topic()='data:admin' and public.is_admin())
);

create function public.get_practice_history(before_at timestamptz default null, before_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare uid uuid=sj_private.require_player();
begin
 return jsonb_build_object('attempts',(select coalesce(jsonb_agg(r order by r.started_at desc,r.id desc),'[]') from (
 select id,score,correct_count,started_at,jsonb_array_length(questions) question_count from public.practice_attempts
 where user_id=uid and completed_at is not null and (before_at is null or (started_at,id)<(before_at,before_id))
 order by started_at desc,id desc limit 30) r));
end $$;
create function public.get_practice_review(attempt_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); a public.practice_attempts;
begin
 select * into a from public.practice_attempts where id=attempt_id and user_id=uid and completed_at is not null;
 if not found then raise exception 'REVIEW_UNAVAILABLE'; end if;
 return jsonb_build_object('questions',(select jsonb_agg(q||coalesce(a.answers->(i::int-1),'{}') order by i) from jsonb_array_elements(a.questions) with ordinality t(q,i)));
end $$;
revoke all on function public.get_practice_history(timestamptz,uuid),public.get_practice_review(uuid) from public,anon;
grant execute on function public.get_practice_history(timestamptz,uuid),public.get_practice_review(uuid) to authenticated;
drop function public.start_practice(uuid,uuid,boolean);
create or replace function public.start_practice(category_id uuid default null, subtopic_id uuid default null, timed boolean default true, exam_filter text default null, difficulty_filter text default null, question_count int default 10) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); aid uuid; qs jsonb;
begin
 perform sj_private.rate_limit('practice',15);
 select jsonb_agg(sj_private.question_snapshot(qid) order by ord) into qs
 from unnest(sj_private.pick_questions(question_count,category_id,subtopic_id,exam_filter,difficulty_filter)) with ordinality t(qid,ord);
 insert into public.practice_attempts(user_id,timed,questions) values(uid,timed,qs) returning id into aid;
 return jsonb_build_object('attempt_id',aid,'question_count',jsonb_array_length(qs),'question_index',0,
 'question',sj_private.safe_question(qs->0)||jsonb_build_object('deadline_at',case when timed then now()+make_interval(secs=>(qs->0->>'time_limit_seconds')::int) else null end));
end $$;

revoke all on function public.start_practice(uuid,uuid,boolean,text,text,int) from public,anon;
grant execute on function public.start_practice(uuid,uuid,boolean,text,text,int) to authenticated;
create or replace function public.admin_save_question(payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare qid uuid=coalesce((payload->>'id')::uuid,gen_random_uuid()); before_data jsonb; opt jsonb; idx int=0; n int;
begin
 perform sj_private.require_admin('editor');
 select to_jsonb(q) into before_data from public.questions q where id=qid for update;
 if exists(select 1 from public.match_questions where question_id=qid) or exists(select 1 from public.daily_challenge_questions where question_id=qid)
 then raise exception 'QUESTION_ALREADY_USED_DUPLICATE_INSTEAD'; end if;
 if jsonb_typeof(payload->'options')<>'array' or jsonb_array_length(payload->'options') <>4 then raise exception 'INVALID_OPTIONS'; end if;
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
 update public.questions set exam=nullif(trim(payload->>'exam'),'') where id=qid;
 perform sj_private.audit('save','questions',qid::text,jsonb_build_object('before',before_data,'after',payload));
 return qid;
end $$;
create or replace function public.admin_import_questions(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb; row_num int=0; category uuid; topic uuid; topic_name text; choice text; difficulty text; opts jsonb;
 fingerprint text=md5(payload::text); previous int; column_name text;
begin
 perform sj_private.require_admin('editor');
 if jsonb_typeof(payload->'questions') is distinct from 'array' then raise exception 'Expected a questions array'; end if;
 if jsonb_array_length(payload->'questions') not between 1 and 500 then raise exception 'Use 1–500 questions per file'; end if;
 perform pg_advisory_xact_lock(hashtext('sj_question_import'));
 select item_count into previous from sj_private.question_imports where batch_hash=fingerprint;
 if found then return jsonb_build_object('imported',previous,'already_imported',true); end if;
 for item in select value from jsonb_array_elements(payload->'questions') loop
   row_num=row_num+1;
   foreach column_name in array array['question','option_a','option_b','option_c','option_d','correct_answer','subject','difficulty','explanation'] loop
     if jsonb_typeof(item->column_name) is distinct from 'string' or trim(item->>column_name)='' then
       raise exception 'Question %: supply %',row_num,column_name;
     end if;
   end loop;
   choice=upper(trim(item->>'correct_answer')); difficulty=lower(trim(item->>'difficulty'));
   if choice not in ('A','B','C','D') or difficulty not in ('easy','medium','hard') or length(trim(item->>'question'))<4 then
     raise exception 'Question %: check question text, correct_answer (A–D) and difficulty',row_num;
   end if;
   select c.id into category from public.categories c where lower(trim(item->>'subject')) in (lower(c.name),lower(c.slug)) order by c.sort_order,c.id limit 1;
   if category is null then raise exception 'Question %: unknown subject "%". Add the category first',row_num,item->>'subject'; end if;
   topic=null; topic_name=nullif(trim(item->>'topic'),'');
   if topic_name is not null then
     select s.id into topic from public.subtopics s where s.category_id=category and lower(s.name)=lower(topic_name) order by s.id limit 1;
     if topic is null then insert into public.subtopics(category_id,name) values(category,topic_name) on conflict(category_id,name) do update set name=excluded.name returning id into topic; end if;
   end if;
   select jsonb_agg(jsonb_build_object('option_text',trim(item->>('option_'||l)),'is_correct',upper(l)=choice) order by l) into opts from unnest(array['a','b','c','d']) l;
   if (select count(distinct lower(o->>'option_text')) from jsonb_array_elements(opts) o)<>4 then raise exception 'Question %: options must be different',row_num; end if;
   perform public.admin_save_question(jsonb_build_object('category_id',category,'subtopic_id',topic,'question_text',trim(item->>'question'),
      'difficulty',difficulty,'time_limit_seconds',coalesce((item->>'time_limit_seconds')::int,15),'explanation',trim(item->>'explanation'),'status','draft','exam',item->>'exam','options',opts));
 end loop;
 insert into sj_private.question_imports values(fingerprint,row_num);
 return jsonb_build_object('imported',row_num,'already_imported',false);
end $$;
revoke all on all functions in schema sj_private from public,anon,authenticated;
commit;
