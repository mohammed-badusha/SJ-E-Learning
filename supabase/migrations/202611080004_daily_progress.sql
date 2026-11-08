create function sj_private.generate_daily(day date) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid; q record; idx int=0;
begin
 perform pg_advisory_xact_lock(hashtext('sj_daily_'||day::text));
 select id into cid from public.daily_challenges where challenge_date=day;
 if cid is not null then return cid; end if;
 if (select count(*) from public.questions where status='published')<10 then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 insert into public.daily_challenges(challenge_date,title,status) values(day,'A little better · '||to_char(day,'DD Mon'),'published') returning id into cid;
 for q in select id from public.questions where status='published' order by row_number() over(partition by category_id,difficulty order by random()),random() limit 10 loop
 insert into public.daily_challenge_questions(challenge_id,question_index,question_id,snapshot) values(cid,idx,q.id,sj_private.question_snapshot(q.id)); idx=idx+1;
 end loop;
 return cid;
end $$;
create function public.get_today_challenge() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); day date=(now() at time zone 'Asia/Kolkata')::date; cid uuid;
begin
 cid=sj_private.generate_daily(day);
 return (select jsonb_build_object('id',c.id,'title',c.title,'challenge_date',c.challenge_date,'question_count',(select count(*) from public.daily_challenge_questions where challenge_id=cid),
 'completed',coalesce(a.completed_at is not null,false),'started',a.id is not null,'score',a.score,'resets_at',(day+1)::timestamp at time zone 'Asia/Kolkata')
 from public.daily_challenges c left join public.daily_attempts a on a.challenge_id=c.id and a.user_id=uid where c.id=cid and c.status in ('published','scheduled'));
end $$;
create function sj_private.daily_question(aid uuid, idx int) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.daily_attempts; q jsonb; start_at timestamptz;
begin
 select * into a from public.daily_attempts where id=aid;
 select snapshot into q from public.daily_challenge_questions where challenge_id=a.challenge_id and question_index=idx;
 if q is null then raise exception 'INVALID_INDEX'; end if;
 select a.started_at+make_interval(secs=>coalesce(sum((snapshot->>'time_limit_seconds')::int),0)::double precision) into start_at
 from public.daily_challenge_questions where challenge_id=a.challenge_id and question_index<idx;
 if now()<start_at then raise exception 'QUESTION_NOT_ACTIVE'; end if;
 return sj_private.safe_question(q)||jsonb_build_object('started_at',start_at,'deadline_at',start_at+make_interval(secs=>(q->>'time_limit_seconds')::int));
end $$;
create function public.start_daily_attempt() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); today jsonb; a public.daily_attempts; idx int=0; n int;
begin
 today=public.get_today_challenge();
 if today is null then raise exception 'CHALLENGE_NOT_AVAILABLE'; end if;
 insert into public.daily_attempts(challenge_id,user_id) values((today->>'id')::uuid,uid) on conflict(challenge_id,user_id) do nothing;
 select * into a from public.daily_attempts where challenge_id=(today->>'id')::uuid and user_id=uid;
 select count(*) into n from public.daily_challenge_questions where challenge_id=a.challenge_id;
 -- Reopening resumes the wall-clock question; it never resets timers or creates another attempt.
 select coalesce(min(question_index),n-1) into idx from (
 select question_index,a.started_at+make_interval(secs=>sum((snapshot->>'time_limit_seconds')::int) over(order by question_index)::double precision) deadline
 from public.daily_challenge_questions where challenge_id=a.challenge_id) q where deadline+interval '500 milliseconds'>now();
 return jsonb_build_object('attempt_id',a.id,'question_count',n,'question_index',idx,'completed',a.completed_at is not null,'score',a.score,'correct_count',a.correct_count,
 'question',case when a.completed_at is null then sj_private.daily_question(a.id,idx) else null end);
end $$;
create function public.get_daily_question(attempt_id uuid, question_index int) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.daily_attempts where id=attempt_id and user_id=sj_private.require_player() and completed_at is null) then raise exception 'ATTEMPT_NOT_FOUND'; end if;
 return sj_private.daily_question(attempt_id,question_index);
end $$;
create function public.submit_daily_answer(attempt_id uuid, question_index int, option_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); a public.daily_attempts; q jsonb; timing jsonb; elapsed int; correct boolean; points int; prior public.daily_attempt_answers; n int;
begin
 perform sj_private.rate_limit('answer',120);
 select * into a from public.daily_attempts where id=attempt_id and user_id=uid for update;
 if not found then raise exception 'ATTEMPT_NOT_FOUND' using errcode='42501'; end if;
 select snapshot into q from public.daily_challenge_questions where challenge_id=a.challenge_id and daily_challenge_questions.question_index=submit_daily_answer.question_index;
 if q is null then raise exception 'INVALID_INDEX'; end if;
 select * into prior from public.daily_attempt_answers where daily_attempt_answers.attempt_id=submit_daily_answer.attempt_id and daily_attempt_answers.question_index=submit_daily_answer.question_index;
 if not found then
 if a.completed_at is not null then raise exception 'ATTEMPT_COMPLETE'; end if;
 timing=sj_private.daily_question(attempt_id,question_index);
 if option_id is not null and not exists(select 1 from jsonb_array_elements(q->'options') where value->>'id'=option_id::text) then raise exception 'INVALID_OPTION'; end if;
 elapsed=greatest(0,floor(extract(epoch from(clock_timestamp()-(timing->>'started_at')::timestamptz))*1000)::int);
 correct=coalesce(option_id::text=q->>'correct_option_id',false) and clock_timestamp()<=(timing->>'deadline_at')::timestamptz+interval '500 milliseconds';
 select count(*) into n from public.daily_challenge_questions where challenge_id=a.challenge_id;
 points=sj_private.score(correct,elapsed,(q->>'time_limit_seconds')::int,question_index=n-1);
 insert into public.daily_attempt_answers(attempt_id,question_index,option_id,is_correct,response_ms,points)
 values(attempt_id,question_index,option_id,correct,least(elapsed,(q->>'time_limit_seconds')::int*1000),points) returning * into prior;
 end if;
 return jsonb_build_object('correct_option_id',q->>'correct_option_id','explanation',q->>'explanation','is_correct',prior.is_correct,'points',prior.points);
end $$;
create function sj_private.finish_daily(aid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.daily_attempts; p public.profiles; total_ms int; day date; streak int; week date; freezes int; answered int; n int;
begin
 select * into a from public.daily_attempts where id=aid for update;
 if not found then raise exception 'ATTEMPT_NOT_FOUND'; end if;
 if a.completed_at is null then
 select sum((snapshot->>'time_limit_seconds')::int)*1000,count(*) into total_ms,n from public.daily_challenge_questions where challenge_id=a.challenge_id;
 select count(*) into answered from public.daily_attempt_answers where attempt_id=aid;
 if answered<n and now()<a.started_at+make_interval(secs=>total_ms::numeric/1000)+interval '500 milliseconds' then raise exception 'ROUND_NOT_COMPLETE'; end if;
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
create function public.finish_daily_attempt(attempt_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.daily_attempts where id=attempt_id and user_id=sj_private.require_player()) then raise exception 'ATTEMPT_NOT_FOUND'; end if;
 return sj_private.finish_daily(attempt_id);
end $$;
create function public.get_leaderboard(type text default 'all_time', category_id uuid default null, result_limit int default 100) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); rows jsonb;
begin
 if type not in ('all_time','weekly','daily') then raise exception 'INVALID_LEADERBOARD'; end if;
 with ranked as (
 select p.id,p.full_name,p.level,p.rating,
 case when type='daily' then coalesce(d.score,0) when type='weekly' then coalesce(w.points,0) else p.rating end metric,
 rank() over(order by case when type='daily' then coalesce(d.score,0) when type='weekly' then coalesce(w.points,0) else p.rating end desc,coalesce(d.total_time_ms,0)) rank
 from public.profiles p
 left join public.daily_attempts d on d.user_id=p.id and d.completed_at is not null and d.challenge_id=(select id from public.daily_challenges where challenge_date=(now() at time zone 'Asia/Kolkata')::date)
 left join lateral(select sum(mp.score) points from public.match_players mp join public.matches m on m.id=mp.match_id where mp.user_id=p.id and m.status='completed'
 and (get_leaderboard.category_id is null or m.category_id=get_leaderboard.category_id)
 and m.ended_at>=date_trunc('week',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata') w on true
 where p.profile_completed and not p.is_bot and not p.is_banned and (type<>'daily' or d.id is not null)
 ) select coalesce(jsonb_agg(to_jsonb(r) order by rank),'[]') into rows from ranked r where rank<=least(greatest(result_limit,1),100) or id=uid;
 return jsonb_build_object('rows',rows);
end $$;
create function public.get_my_history() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player();
begin return jsonb_build_object('matches',(select coalesce(jsonb_agg(row),'[]') from (
 select m.id,m.mode,m.ended_at,mp.score,mp.result,mp.rating_after-mp.rating_before rating_change,
 (select full_name from public.profiles where id=case when m.player1_id=uid then m.player2_id else m.player1_id end) opponent
 from public.match_players mp join public.matches m on m.id=mp.match_id where mp.user_id=uid and m.status='completed' order by m.ended_at desc limit 50) row)); end $$;
create function public.get_my_stats() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player();
begin return jsonb_build_object('matches',(select count(*) from public.match_players where user_id=uid and result is not null),
 'wins',(select count(*) from public.match_players where user_id=uid and result='win'),
 'categories',(select coalesce(jsonb_agg(jsonb_build_object('name',c.name,'played',s.played,'correct',s.correct)),'[]') from public.user_category_stats s join public.categories c on c.id=s.category_id where user_id=uid),
 'badges',(select coalesce(jsonb_agg(to_jsonb(b)),'[]') from public.user_badges ub join public.badges b on b.id=ub.badge_id where ub.user_id=uid)); end $$;
create function public.report_question(question_id uuid, reason text, note text default '') returns void language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player();
begin
 perform sj_private.rate_limit('report',10);
 if length(reason) not between 3 and 100 or length(note)>1000 then raise exception 'INVALID_REPORT'; end if;
 insert into public.question_reports(question_id,user_id,reason,note) values(question_id,uid,reason,note);
end $$;
create function public.admin_save_setting(key text,value jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin('super_admin');
 if key='questions_per_match' then if (value#>>'{}')::int not between 5 and 20 then raise exception 'INVALID_SETTING'; end if;
 elsif key='search_timeout_seconds' then if (value#>>'{}')::int not between 5 and 60 then raise exception 'INVALID_SETTING'; end if;
 elsif key in ('label_bots','maintenance_mode') then if jsonb_typeof(value)<>'boolean' then raise exception 'INVALID_SETTING'; end if;
 elsif key='min_app_version' then if jsonb_typeof(value)<>'string' then raise exception 'INVALID_SETTING'; end if;
 else raise exception 'INVALID_SETTING'; end if;
 insert into public.app_settings as s(key,value) values(key,value) on conflict on constraint app_settings_pkey do update set value=excluded.value;
 perform sj_private.audit('setting','app_settings',key,value);
end $$;
create function public.admin_set_user(user_id uuid,is_banned boolean,reset_streak boolean default false) returns void language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin('super_admin');
 if user_id=auth.uid() then raise exception 'CANNOT_BAN_SELF'; end if;
 update public.profiles p set is_banned=admin_set_user.is_banned,current_streak=case when reset_streak then 0 else current_streak end where id=user_id and not is_bot;
 delete from public.matchmaking_queue where matchmaking_queue.user_id=admin_set_user.user_id;
 perform sj_private.audit('update','profiles',user_id::text,jsonb_build_object('is_banned',is_banned,'reset_streak',reset_streak));
end $$;
create function public.admin_reports() returns jsonb language plpgsql security definer set search_path='' as $$
begin perform sj_private.require_admin(); return jsonb_build_object('reports',(select coalesce(jsonb_agg(row),'[]') from (select r.*,q.question_text from public.question_reports r join public.questions q on q.id=r.question_id order by r.created_at desc limit 100) row)); end $$;
create function public.admin_resolve_report(report_id uuid,status text) returns void language plpgsql security definer set search_path='' as $$
begin perform sj_private.require_admin('editor'); if status not in ('resolved','dismissed') then raise exception 'INVALID_STATUS'; end if;
 update public.question_reports set status=admin_resolve_report.status,resolved_by=auth.uid() where id=report_id;
 perform sj_private.audit('resolve','question_reports',report_id::text,jsonb_build_object('status',status)); end $$;
create function sj_private.daily_maintenance() returns void language plpgsql security definer set search_path='' as $$
declare a record;
begin
 perform sj_private.generate_daily((now() at time zone 'Asia/Kolkata')::date+1);
 for a in select d.id from public.daily_attempts d where d.completed_at is null and now()>d.started_at+
 make_interval(secs=>(select sum((snapshot->>'time_limit_seconds')::int) from public.daily_challenge_questions where challenge_id=d.challenge_id)::double precision)+interval '1 second'
 loop perform sj_private.finish_daily(a.id); end loop;
end $$;

revoke all on all functions in schema sj_private from public,anon,authenticated;
revoke all on function public.get_today_challenge(),public.start_daily_attempt(),public.get_daily_question(uuid,int),public.submit_daily_answer(uuid,int,uuid),
 public.finish_daily_attempt(uuid),public.get_leaderboard(text,uuid,int),public.get_my_history(),public.get_my_stats(),public.report_question(uuid,text,text),
 public.admin_save_setting(text,jsonb),public.admin_set_user(uuid,boolean,boolean),public.admin_reports(),public.admin_resolve_report(uuid,text) from public,anon;
grant execute on function public.get_today_challenge(),public.start_daily_attempt(),public.get_daily_question(uuid,int),public.submit_daily_answer(uuid,int,uuid),
 public.finish_daily_attempt(uuid),public.get_leaderboard(text,uuid,int),public.get_my_history(),public.get_my_stats(),public.report_question(uuid,text,text),
 public.admin_save_setting(text,jsonb),public.admin_set_user(uuid,boolean,boolean),public.admin_reports(),public.admin_resolve_report(uuid,text) to authenticated;
