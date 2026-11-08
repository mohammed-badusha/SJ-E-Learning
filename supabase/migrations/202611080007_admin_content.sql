create function public.admin_save_subtopic(payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare sid uuid=coalesce((payload->>'id')::uuid,gen_random_uuid());
begin
 perform sj_private.require_admin('editor');
 insert into public.subtopics(id,category_id,name,sort_order,is_active) values(sid,(payload->>'category_id')::uuid,trim(payload->>'name'),coalesce((payload->>'sort_order')::int,0),coalesce((payload->>'is_active')::boolean,true))
 on conflict(id) do update set name=excluded.name,sort_order=excluded.sort_order,is_active=excluded.is_active;
 perform sj_private.audit('save','subtopics',sid::text,payload);return sid;
end $$;
create function public.admin_daily_calendar() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('days',(select coalesce(jsonb_agg(row order by day),'[]') from (
 select day::date,c.id,c.title,c.status,(select count(*) from public.daily_attempts where challenge_id=c.id and completed_at is not null) participation
 from generate_series((now() at time zone 'Asia/Kolkata')::date::timestamp,((now() at time zone 'Asia/Kolkata')::date+29)::timestamp,interval '1 day') day
 left join public.daily_challenges c on c.challenge_date=day::date) row));
end $$;
create function public.admin_schedule_daily(day date,title text,question_ids uuid[] default null) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid; qid uuid; idx int=0;
begin
 perform sj_private.require_admin('editor');
 perform pg_advisory_xact_lock(hashtext('sj_daily_'||day::text));
 if day<(now() at time zone 'Asia/Kolkata')::date or day>(now() at time zone 'Asia/Kolkata')::date+365 or length(trim(title)) not between 2 and 100 then raise exception 'INVALID_CHALLENGE'; end if;
 select id into cid from public.daily_challenges where challenge_date=day for update;
 if exists(select 1 from public.daily_attempts where challenge_id=cid) then raise exception 'CHALLENGE_ALREADY_STARTED'; end if;
 if cid is null then cid=sj_private.generate_daily(day); end if;
 if question_ids is not null then
 if cardinality(question_ids) not between 5 and 20 or (select count(distinct id) from public.questions where id=any(question_ids) and status='published')<>cardinality(question_ids) then raise exception 'INVALID_QUESTIONS'; end if;
 delete from public.daily_challenge_questions where challenge_id=cid;
 foreach qid in array question_ids loop
 insert into public.daily_challenge_questions(challenge_id,question_index,question_id,snapshot) values(cid,idx,qid,sj_private.question_snapshot(qid));idx=idx+1;
 end loop;
 end if;
 update public.daily_challenges set title=trim(admin_schedule_daily.title),status='scheduled',created_by=auth.uid() where id=cid;
 perform sj_private.audit('schedule','daily_challenges',cid::text,jsonb_build_object('day',day,'title',title));return cid;
end $$;
create function public.admin_analytics() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('questions',(select coalesce(jsonb_agg(row),'[]') from (
 select q.id,q.question_text,count(a.id) attempts,round(100.0*count(*) filter(where a.is_correct)/nullif(count(a.id),0),1) accuracy,
 round(avg(a.response_ms)) average_ms from public.questions q join public.match_questions mq on mq.question_id=q.id join public.match_answers a on a.match_id=mq.match_id and a.question_index=mq.question_index
 group by q.id order by count(a.id) desc limit 100) row),
 'categories',(select coalesce(jsonb_agg(row),'[]') from (select c.name,count(m.id) matches from public.categories c left join public.matches m on m.category_id=c.id group by c.id) row),
 'hours',(select coalesce(jsonb_agg(row),'[]') from (select extract(hour from created_at at time zone 'Asia/Kolkata') as "hour",count(*) matches from public.matches group by 1 order by 1) row));
end $$;
revoke all on function public.admin_save_subtopic(jsonb),public.admin_daily_calendar(),public.admin_schedule_daily(date,text,uuid[]),public.admin_analytics() from public,anon;
grant execute on function public.admin_save_subtopic(jsonb),public.admin_daily_calendar(),public.admin_schedule_daily(date,text,uuid[]),public.admin_analytics() to authenticated;
