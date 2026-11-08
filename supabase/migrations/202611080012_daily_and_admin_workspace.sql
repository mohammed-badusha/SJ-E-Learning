-- Apply once to an existing project after migration 011.
begin;
-- Old answers have no receipt timestamp and retain their original time windows.
alter table public.daily_attempt_answers add column answered_at timestamptz;
alter table public.daily_attempt_answers alter column answered_at set default clock_timestamp();

create function sj_private.daily_windows(aid uuid)
returns table(idx int, opens_at timestamptz, closes_at timestamptz, answered boolean)
language sql stable security definer set search_path='' as $$
 with recursive items as (
   select q.question_index i, make_interval(secs=>(q.snapshot->>'time_limit_seconds')::int) duration,
          a.started_at, r.answered_at, r.id is not null answered
   from public.daily_attempts a join public.daily_challenge_questions q on q.challenge_id=a.challenge_id
   left join public.daily_attempt_answers r on r.attempt_id=a.id and r.question_index=q.question_index
   where a.id=aid
 ), windows as (
   select i,started_at opens,started_at+duration closes,answered_at,answered from items where i=0
   union all
   select n.i,t.opens,t.opens+n.duration,n.answered_at,n.answered from windows w join items n on n.i=w.i+1
   cross join lateral (select greatest(w.opens,least(w.closes,w.answered_at)) opens) t
 ) select i,opens,closes,answered from windows;
$$;
revoke all on function sj_private.daily_windows(uuid) from public,anon,authenticated;
create or replace function sj_private.daily_question(aid uuid, idx int) returns jsonb language plpgsql security definer set search_path='' as $$
declare window_row record; question jsonb;
begin
 select * into window_row from sj_private.daily_windows(aid) w where w.idx=daily_question.idx;
 if not found then raise exception 'INVALID_INDEX'; end if;
 if clock_timestamp()<window_row.opens_at then raise exception 'QUESTION_NOT_ACTIVE'; end if;
 select q.snapshot into question from public.daily_attempts a join public.daily_challenge_questions q on q.challenge_id=a.challenge_id
 where a.id=aid and q.question_index=idx;
 return sj_private.safe_question(question)||jsonb_build_object('started_at',window_row.opens_at,'deadline_at',window_row.closes_at);
end $$;
create or replace function sj_private.finish_daily(aid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.daily_attempts; p public.profiles; total_ms int; day date; streak int; week date; freezes int; answered int; n int;
begin
 select * into a from public.daily_attempts where id=aid for update;
 if not found then raise exception 'ATTEMPT_NOT_FOUND'; end if;
 if a.completed_at is null then
 select sum((snapshot->>'time_limit_seconds')::int)*1000,count(*) into total_ms,n from public.daily_challenge_questions where challenge_id=a.challenge_id;
 select count(*) into answered from public.daily_attempt_answers where attempt_id=aid;
 if answered<n and clock_timestamp()<(select max(closes_at) from sj_private.daily_windows(aid))+interval '500 milliseconds' then raise exception 'ROUND_NOT_COMPLETE'; end if;
 update public.daily_attempts set score=(select coalesce(sum(points),0) from public.daily_attempt_answers where attempt_id=aid),
 correct_count=(select count(*) from public.daily_attempt_answers where attempt_id=aid and is_correct),
 total_time_ms=(select coalesce(sum(coalesce(ans.response_ms,(q.snapshot->>'time_limit_seconds')::int*1000)),0) from public.daily_challenge_questions q left join public.daily_attempt_answers ans on ans.attempt_id=aid and ans.question_index=q.question_index where q.challenge_id=a.challenge_id),
 completed_at=now() where id=aid returning * into a;
 select * into p from public.profiles where id=a.user_id for update;
 select challenge_date into day from public.daily_challenges where id=a.challenge_id;
 week=date_trunc('week',day::timestamp)::date;
 freezes=case when p.freeze_week is distinct from week then 1 else p.streak_freezes end;
 streak=case when p.last_daily_date=day-1 then p.current_streak+1 when p.last_daily_date=day-2 and freezes>0 then p.current_streak+1 else 1 end;
 if p.last_daily_date=day-2 and freezes>0 then freezes=freezes-1; end if;
 if p.last_daily_date is null or p.last_daily_date<day then
 update public.profiles set current_streak=streak,best_streak=greatest(best_streak,streak),last_daily_date=day,streak_freezes=freezes,freeze_week=week,
 xp=xp+30+a.correct_count*5,level=1+(xp+30+a.correct_count*5)/100 where id=a.user_id;
 insert into public.user_badges(user_id,badge_id) select a.user_id,id from public.badges where milestone<=streak on conflict(user_id,badge_id) do nothing;
 end if;
 end if;
 return jsonb_build_object('score',a.score,'correct_count',a.correct_count);
end $$;
create or replace function public.start_daily_attempt() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); today jsonb; a public.daily_attempts; idx int=0; n int;
begin
 today=public.get_today_challenge();
 if today is null then raise exception 'CHALLENGE_NOT_AVAILABLE'; end if;
 insert into public.daily_attempts(challenge_id,user_id) values((today->>'id')::uuid,uid) on conflict(challenge_id,user_id) do nothing;
 select * into a from public.daily_attempts where challenge_id=(today->>'id')::uuid and user_id=uid for update;
 select count(*) into n from public.daily_challenge_questions where challenge_id=a.challenge_id;
 if a.completed_at is null then
   select min(w.idx) into idx from sj_private.daily_windows(a.id) w
   where not w.answered and w.closes_at+interval '500 milliseconds'>clock_timestamp();
   if idx is null then
     perform sj_private.finish_daily(a.id);
     select * into a from public.daily_attempts where id=a.id;
   end if;
 end if;
 return jsonb_build_object('attempt_id',a.id,'question_count',n,'question_index',idx,'completed',a.completed_at is not null,'score',a.score,'correct_count',a.correct_count,
 'question',case when a.completed_at is null then sj_private.daily_question(a.id,idx) else null end);
end $$;
create function public.admin_question_groups(search text default '') returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('categories',(select coalesce(jsonb_agg(g order by g.name),'[]') from (
   select c.id,c.name,count(q.id) question_count from public.categories c left join public.questions q
   on q.category_id=c.id and q.question_text ilike '%'||search||'%'
   group by c.id having search='' or count(q.id)>0
 ) g));
end $$;
create function public.admin_question_page(subject_id uuid, search text default '', after_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('rows',(select coalesce(jsonb_agg(r order by r.id),'[]') from (
   select q.*,t.name topic_name,(select jsonb_agg(o order by o.sort_order) from public.question_options o where o.question_id=q.id) options
   from public.questions q left join public.subtopics t on t.id=q.subtopic_id
   where q.category_id=subject_id and q.question_text ilike '%'||search||'%' and (after_id is null or q.id>after_id)
   order by q.id limit 50
 ) r));
end $$;

create function public.admin_user_page(search text default '', after_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('rows',(select coalesce(jsonb_agg(u order by u.id),'[]') from (
   select p.id,p.full_name,p.username,p.email,p.phone,p.target_exam,p.rating,p.xp,p.level,p.current_streak,p.best_streak,
     p.last_daily_date,p.profile_completed,p.is_banned,p.created_at,p.updated_at,
     coalesce((select a.role from public.admin_users a where a.is_active and a.email=p.email),'student') role
   from public.profiles p where not p.is_bot and p.deleted_at is null and (after_id is null or p.id>after_id)
     and (search='' or concat_ws(' ',p.full_name,p.email,p.phone) ilike '%'||search||'%')
   order by p.id limit 100
 ) u));
end $$;
create table sj_private.question_imports (batch_hash text primary key, item_count int not null);
revoke all on sj_private.question_imports from public,anon,authenticated;
create function public.admin_import_questions(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
      'difficulty',difficulty,'time_limit_seconds',coalesce((item->>'time_limit_seconds')::int,15),'explanation',trim(item->>'explanation'),'status','draft','options',opts));
 end loop;
 insert into sj_private.question_imports values(fingerprint,row_num);
 return jsonb_build_object('imported',row_num,'already_imported',false);
end $$;
revoke all on function public.admin_question_groups(text),public.admin_question_page(uuid,text,uuid),public.admin_user_page(text,uuid),public.admin_import_questions(jsonb) from public,anon;
grant execute on function public.admin_question_groups(text),public.admin_question_page(uuid,text,uuid),public.admin_user_page(text,uuid),public.admin_import_questions(jsonb) to authenticated;
commit;
