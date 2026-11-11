-- Replace the question bank and topic catalog. Historical attempts retain snapshots.
begin;

-- Reports refer to removed questions; retain their original text for staff review.
alter table public.question_reports add column if not exists question_snapshot text;
update public.question_reports r set question_snapshot=q.question_text
from public.questions q where q.id=r.question_id and r.question_snapshot is null;
alter table public.question_reports alter column question_id drop not null;
alter table public.question_reports drop constraint if exists question_reports_question_id_fkey;
alter table public.question_reports add constraint question_reports_question_id_fkey
  foreign key (question_id) references public.questions(id) on delete set null;

update public.match_questions set question_id=null where question_id is not null;
update public.daily_challenge_questions set question_id=null where question_id is not null;
update public.matchmaking_queue set subtopic_id=null where subtopic_id is not null;
-- Keep historical challenges and attempts but never offer retired snapshots anew.
update public.daily_challenges set status='draft' where exists
  (select 1 from public.daily_challenge_questions q where q.challenge_id=daily_challenges.id);
delete from public.questions;
delete from public.subtopics;

-- Remove unplayed scheduled challenges built from the retired question bank.
delete from public.daily_challenges d where not exists
  (select 1 from public.daily_attempts a where a.challenge_id=d.id);

insert into public.categories(id,name,slug,icon,color_hex,sort_order) values
 ('668395b5-5411-5b0b-99a5-5efa80c18faf','Quantitative Aptitude','quant','calculate','#376BD6',0),
 ('09f88e78-88be-547c-9eb8-ef644b66db02','Reasoning','reasoning','psychology','#8051C5',1),
 ('b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','General Awareness','general-awareness','public','#B66A13',2),
 ('d2c9217b-d3a7-5a4a-9815-c33704a25aff','English','english','translate','#087E83',3)
on conflict(slug) do nothing;

insert into public.subtopics(category_id,name,sort_order)
select c.id,t.name,t.position-1 from public.categories c
join (values
 ('quant',array['Number System','Percentage','Ratio & Proportion','Profit & Loss','Average','Time & Work','Time, Speed & Distance','Simple & Compound Interest','Algebra','Geometry','Trigonometry','Mensuration','Data Interpretation','Simplification','Surds & Indices']),
 ('reasoning',array['Analogy','Classification','Series','Coding-Decoding','Blood Relations','Direction Sense','Syllogism','Venn Diagrams','Seating Arrangement','Puzzles','Mirror & Water Image','Paper Folding & Cutting','Statement & Conclusion','Missing Number','Mathematical Operations']),
 ('general-awareness',array['Indian History','Indian Polity','Geography','Economics','Physics','Chemistry','Biology','Computer Awareness','Current Affairs','Static GK','Awards & Honours','Books & Authors','Important Days','Sports']),
 ('english',array['Vocabulary','Grammar','Comprehension','Synonyms & Antonyms','Idioms & Phrases','One Word Substitution','Sentence Correction','Fill in the Blanks','Cloze Test','Spelling Errors','Active & Passive Voice','Direct & Indirect Speech'])
) as catalog(slug,names) on c.slug=catalog.slug
cross join lateral unnest(catalog.names) with ordinality as t(name,position);

create or replace function sj_private.normalize_import_name(raw text) returns text
language sql immutable set search_path='' as $$
  select regexp_replace(lower(coalesce(raw,'')),'[^a-z0-9]','','g')
$$;

create or replace function sj_private.name_distance(a text,b text) returns int
language plpgsql immutable set search_path='' as $$
declare i int; j int; previous int[]; current_row int[]; cost int;
begin
 if a=b then return 0; end if;
 previous=array(select generate_series(0,length(b)));
 for i in 1..length(a) loop
   current_row=array[i];
   for j in 1..length(b) loop
     cost=case when substr(a,i,1)=substr(b,j,1) then 0 else 1 end;
     current_row=array_append(current_row,least(current_row[j]+1,previous[j+1]+1,previous[j]+cost));
   end loop;
   previous=current_row;
 end loop;
 return previous[length(b)+1];
end $$;

create or replace function sj_private.resolve_import_name(raw text, parent uuid default null) returns uuid
language plpgsql stable security definer set search_path='' as $$
declare key text=sj_private.normalize_import_name(raw); resolved uuid; best int; runner_up int; allowance int;
begin
 if key='' then return null; end if;
 -- Explicit common names are safer than guessing across similarly named topics.
 key=case
   when parent is null and key in ('math','maths','mathematics','quant','quantitative','quantitativeaptitude') then 'quantitativeaptitude'
   when parent is null and key in ('gk','generalknowledge','generalscience','ga') then 'generalawareness'
   when parent is null and key in ('reason','logicalreasoning') then 'reasoning'
   when parent is not null and key='percentages' then 'percentage'
   when parent is not null and key='numbersystems' then 'numbersystem'
   when parent is not null and key='averages' then 'average'
   when parent is not null and key='ratio' then 'ratioproportion'
   when parent is not null and key in ('sici','simpleinterest','compoundinterest') then 'simplecompoundinterest'
   when parent is not null and key='speedanddistance' then 'timespeeddistance'
   when parent is not null and key='history' then 'indianhistory'
   when parent is not null and key='polity' then 'indianpolity'
   when parent is not null and key='analogies' then 'analogy'
   when parent is not null and key='syllogisms' then 'syllogism'
   when parent is not null and key='seatingarrangements' then 'seatingarrangement'
   when parent is not null and key='readingcomprehension' then 'comprehension'
   when parent is not null and key='grammarrules' then 'grammar'
   else key end;
 if parent is null then
   select id into resolved from public.categories c where c.is_active and
     (sj_private.normalize_import_name(c.name)=key or sj_private.normalize_import_name(c.slug)=key) limit 1;
 else
   select id into resolved from public.subtopics s where s.category_id=parent and s.is_active
     and sj_private.normalize_import_name(s.name)=key limit 1;
 end if;
 if resolved is not null then return resolved; end if;
 allowance=case when length(key)<6 then 1 when length(key)<12 then 2 else 3 end;
 if parent is null then
   select id,distance into resolved,best from
     (select c.id,sj_private.name_distance(key,sj_private.normalize_import_name(c.name)) distance
      from public.categories c where c.is_active order by distance,c.id limit 1) ranked;
   select min(sj_private.name_distance(key,sj_private.normalize_import_name(c.name))) into runner_up
     from public.categories c where c.is_active and c.id<>resolved;
 else
   select id,distance into resolved,best from
     (select s.id,sj_private.name_distance(key,sj_private.normalize_import_name(s.name)) distance
      from public.subtopics s where s.is_active and s.category_id=parent order by distance,s.id limit 1) ranked;
   select min(sj_private.name_distance(key,sj_private.normalize_import_name(s.name))) into runner_up
     from public.subtopics s where s.is_active and s.category_id=parent and s.id<>resolved;
 end if;
 if best<=allowance and (runner_up is null or best<runner_up) then return resolved; end if;
 return null;
end $$;

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
 if before_data is not null and (exists(select 1 from public.match_questions where question_id=qid)
   or exists(select 1 from public.daily_challenge_questions where question_id=qid))
 then raise exception 'QUESTION_ALREADY_USED_DUPLICATE_INSTEAD'; end if;
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

create or replace function public.admin_import_questions(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare item jsonb; row_num int=0; category uuid; topic uuid; choice text; difficulty text;
  opts jsonb; fingerprint text=md5(payload::text); previous int; column_name text;
begin
 perform sj_private.require_admin('editor');
 if jsonb_typeof(payload->'questions') is distinct from 'array' then raise exception 'Expected a questions array'; end if;
 if jsonb_array_length(payload->'questions') not between 1 and 500 then raise exception 'Use 1–500 questions per file'; end if;
 perform pg_advisory_xact_lock(hashtext('sj_question_import'));
 select item_count into previous from sj_private.question_imports where batch_hash=fingerprint;
 if found then return jsonb_build_object('imported',previous,'already_imported',true); end if;
 for item in select value from jsonb_array_elements(payload->'questions') loop
   row_num=row_num+1;
   foreach column_name in array array['question','option_a','option_b','option_c','option_d','correct_answer','subject','topic','difficulty'] loop
     if jsonb_typeof(item->column_name) is distinct from 'string' or trim(item->>column_name)=''
     then raise exception 'Question %: supply %',row_num,column_name; end if;
   end loop;
   choice=upper(trim(item->>'correct_answer'));
   difficulty=lower(trim(item->>'difficulty'));
   if choice not in ('A','B','C','D') or difficulty not in ('easy','medium','hard') or length(trim(item->>'question'))<4
   then raise exception 'Question %: check question text, correct_answer (A–D) and difficulty',row_num; end if;
   category=sj_private.resolve_import_name(item->>'subject');
   if category is null then raise exception 'Question %: unknown subject "%"',row_num,item->>'subject'; end if;
   topic=sj_private.resolve_import_name(item->>'topic',category);
   if topic is null then raise exception 'Question %: unknown topic "%" for subject "%"',row_num,item->>'topic',item->>'subject'; end if;
   select jsonb_agg(jsonb_build_object('option_text',trim(item->>('option_'||l)),'is_correct',upper(l)=choice) order by l)
     into opts from unnest(array['a','b','c','d']) l;
   if (select count(distinct lower(o->>'option_text')) from jsonb_array_elements(opts) o)<>4
   then raise exception 'Question %: options must be different',row_num; end if;
   perform public.admin_save_question(jsonb_build_object('category_id',category,'subtopic_id',topic,
     'question_text',trim(item->>'question'),'difficulty',difficulty,
     'explanation',coalesce(trim(item->>'explanation'),''),'options',opts));
 end loop;
 insert into sj_private.question_imports values(fingerprint,row_num);
 return jsonb_build_object('imported',row_num,'already_imported',false);
end $$;

-- Existing import hashes referred to questions that have now been removed.
delete from sj_private.question_imports;
revoke all on function sj_private.normalize_import_name(text),sj_private.name_distance(text,text),
  sj_private.resolve_import_name(text,uuid) from public,anon,authenticated;
create or replace function public.admin_reports() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('reports',(select coalesce(jsonb_agg(row),'[]'::jsonb) from
   (select r.*,coalesce(q.question_text,r.question_snapshot) question_text
    from public.question_reports r left join public.questions q on q.id=r.question_id
    order by r.created_at desc limit 100) row));
end $$;
create or replace function public.get_today_challenge() returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); day date=(now() at time zone 'Asia/Kolkata')::date;
  cid uuid; available_count int;
begin
 select count(*) into available_count from public.questions where status='published';
 if available_count<10 then return jsonb_build_object('available',false,'question_count',0); end if;
 cid=sj_private.generate_daily(day);
 return coalesce((select jsonb_build_object('available',true,'id',c.id,'title',c.title,
   'challenge_date',c.challenge_date,
   'question_count',(select count(*) from public.daily_challenge_questions where challenge_id=cid),
   'completed',coalesce(a.completed_at is not null,false),'started',a.id is not null,
   'score',a.score,'resets_at',(day+1)::timestamp at time zone 'Asia/Kolkata')
   from public.daily_challenges c left join public.daily_attempts a
   on a.challenge_id=c.id and a.user_id=uid
   where c.id=cid and c.status in ('published','scheduled')),
   jsonb_build_object('available',false,'question_count',0));
end $$;
commit;
