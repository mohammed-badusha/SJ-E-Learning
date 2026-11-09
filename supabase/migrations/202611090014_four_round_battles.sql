-- Additive rules v2. Existing snapshots and legacy scoring remain intact.
begin;
alter table public.matches add column rules_version int not null default 1;
alter table public.matches add column bot_style text;
alter table public.match_players alter column score type numeric(12,4);
alter table public.match_answers alter column points type numeric(12,4);
alter table public.subtopics add column topic_group text;
alter table public.questions add column exam text;
create index questions_exam_pool on public.questions(exam,category_id,difficulty,id) where status='published';
create index practice_owner_history on public.practice_attempts(user_id,started_at desc,id);
create index daily_owner_history on public.daily_attempts(user_id,started_at desc,id);
insert into public.app_settings(key,value) values ('search_timeout_seconds','10'),('questions_per_match','4'),('daily_question_count','10'),('label_bots','false')
on conflict(key) do update set value=excluded.value;

create table public.battle_rounds (
 round_index int primary key check(round_index between 0 and 3),
 subject_slug text not null unique,
 duration_seconds int not null check(duration_seconds between 5 and 120)
);
insert into public.battle_rounds values (0,'reasoning',40),(1,'general-awareness',15),(2,'quant',40),(3,'english',15);
alter table public.battle_rounds enable row level security;
create policy read_rounds on public.battle_rounds for select to authenticated using(true);
grant select on public.battle_rounds to authenticated;
create table sj_private.bot_names(name text primary key);
insert into sj_private.bot_names select unnest(array[
 'Aarav Sharma','Vivaan Patel','Aditya Nair','Vihaan Singh','Arjun Menon','Sai Kumar','Reyansh Gupta','Ayaan Khan',
 'Krishna Rao','Ishaan Shah','Shaurya Das','Atharv Joshi','Dhruv Reddy','Kabir Verma','Ritvik Iyer','Ansh Jain',
 'Rohan Mishra','Rahul Bose','Karan Mehta','Varun Pillai','Nikhil Bhat','Siddharth Roy','Pranav Sinha','Akash Sen',
 'Abhinav Yadav','Harsh Chauhan','Manish Tiwari','Deepak Pandey','Vikram Sethi','Sanjay Kapoor','Ajay Kulkarni','Vijay Desai',
 'Ravi Prasad','Suresh Naidu','Amit Saxena','Ankit Agarwal','Mohit Bansal','Gaurav Chawla','Piyush Goel','Yash Malhotra',
 'Aadhya Sharma','Ananya Nair','Diya Patel','Saanvi Singh','Myra Menon','Aarohi Shah','Anika Gupta','Isha Rao',
 'Kiara Joshi','Avni Reddy','Riya Das','Navya Jain','Sara Khan','Meera Iyer','Tara Bose','Nitya Verma',
 'Priya Mishra','Sneha Mehta','Pooja Pillai','Kavya Bhat','Neha Roy','Shreya Sinha','Aditi Sen','Swati Yadav',
 'Divya Chauhan','Rashmi Tiwari','Anjali Pandey','Nandini Sethi','Shruti Kapoor','Sakshi Kulkarni','Tanvi Desai','Kriti Prasad',
 'Lakshmi Naidu','Simran Saxena','Ishita Agarwal','Palak Bansal','Ritika Chawla','Vani Goel','Juhi Malhotra','Fathima Ali',
 'Aravind Raj','Keerthana Ravi','Muhammed Faris','Aparna Krishnan','Devika Suresh','Aswin Prakash','Amal Thomas','Anu Mathew'
]);
create function sj_private.battle_score(correct boolean, elapsed_ms int, duration_seconds int) returns numeric
language sql immutable set search_path='' as $$
 select case when correct then round(2 + .5 * greatest(0,least(1,1-elapsed_ms::numeric/(duration_seconds*1000))),4) else 0 end
$$;
create function sj_private.pick_questions(n int, subject uuid default null, topic uuid default null, exam_filter text default null, difficulty_filter text default null)
returns uuid[] language plpgsql security definer set search_path='' as $$
declare picked uuid[];
begin
 if n not between 1 and 100 or (difficulty_filter is not null and difficulty_filter not in ('easy','medium','hard')) then raise exception 'INVALID_FILTER'; end if;
 select array_agg(id) into picked from (
 select q.id from public.questions q join public.categories c on c.id=q.category_id and c.is_active
 where q.status='published' and (subject is null or q.category_id=subject) and (topic is null or q.subtopic_id=topic)
 and (exam_filter is null or q.exam=exam_filter) and (difficulty_filter is null or q.difficulty=difficulty_filter)
 and (select count(*) from public.question_options o where o.question_id=q.id)=4
 order by random() limit n) pool;
 if coalesce(cardinality(picked),0)<>n then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 return picked;
end $$;
create or replace function sj_private.new_match(p1 uuid, p2 uuid, category uuid, topic uuid, mode text) returns uuid
language plpgsql security definer set search_path='' as $$
declare mid uuid; r record; qid uuid; snap jsonb; correct_rounds int[]; target int; style text; delay numeric; short boolean;
begin
 style=(array['Speedster','Analytical','Balanced','Wildcard'])[1+floor(random()*4)::int];
 target=2+floor(random()*3)::int;
 select array_agg(i) into correct_rounds from (select i from generate_series(0,3) i order by random() limit target) t;
 insert into public.matches(category_id,mode,player1_id,player2_id,started_at,next_tick_at,rules_version,bot_style)
 values(null,mode,p1,p2,now()+interval '3 seconds',now()+interval '3 seconds',2,case when mode='bot' then style end) returning id into mid;
 insert into public.match_players(match_id,user_id,rating_before) select mid,id,rating from public.profiles where id in(p1,p2);
 for r in select b.*,c.id category from public.battle_rounds b join public.categories c on c.slug=b.subject_slug and c.is_active order by b.round_index loop
  qid=(sj_private.pick_questions(1,r.category))[1];
  snap=sj_private.question_snapshot(qid)||jsonb_build_object('time_limit_seconds',r.duration_seconds);
  insert into public.match_questions(match_id,question_index,question_id,snapshot,option_order) values(mid,r.round_index,qid,snap,snap->'options');
  if mode='bot' then
   short=r.duration_seconds=15;
   delay=case style when 'Speedster' then case when short then 2+random()*4 else 8+random()*8 end
     when 'Analytical' then case when short then 5+random()*6 else 20+random()*14 end
     when 'Balanced' then case when short then 3+random()*5 else 12+random()*12 end
     else 2+random()*(r.duration_seconds-3) end;
   insert into public.bot_plans(match_id,question_index,will_be_correct,response_ms) values(mid,r.round_index,r.round_index=any(correct_rounds),floor(delay*1000)::int);
  end if;
 end loop;
 if (select count(*) from public.match_questions where match_id=mid)<>4 then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 delete from public.matchmaking_queue where user_id in(p1,p2);
 perform realtime.send(jsonb_build_object('match_id',mid),'match_found','user:'||p1::text,true);
 if mode='live' then perform realtime.send(jsonb_build_object('match_id',mid),'match_found','user:'||p2::text,true); end if;
 return mid;
end $$;
create or replace function public.join_matchmaking(category_id uuid default null, subtopic_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); myrating int; opponent public.matchmaking_queue; mine public.matchmaking_queue; mid uuid;
begin
 perform sj_private.rate_limit('join',30);
 perform 1 from public.profiles where id=uid for update;
 select id into mid from public.matches where (player1_id=uid or player2_id=uid) and status in ('pending','in_progress') limit 1;
 if mid is not null then return jsonb_build_object('match_id',mid); end if;
 -- All new battles share the same four-subject queue.
 if exists(select 1 from public.battle_rounds b left join public.categories c on c.slug=b.subject_slug and c.is_active
 where c.id is null or not exists(select 1 from public.questions q where q.category_id=c.id and q.status='published'
 and (select count(*) from public.question_options o where o.question_id=q.id)=4)) then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 select rating into myrating from public.profiles where id=uid;
 insert into public.matchmaking_queue(user_id,category_id,subtopic_id,rating) values(uid,null,null,myrating)
 on conflict(user_id) do nothing;
 select * into mine from public.matchmaking_queue where user_id=uid for update;
 select * into opponent from public.matchmaking_queue q where q.user_id<>uid and q.category_id is not distinct from mine.category_id
 and (q.subtopic_id is not distinct from mine.subtopic_id or least(q.joined_at,mine.joined_at)<now()-interval '8 seconds')
 and q.joined_at>now()-interval '60 seconds'
 and abs(q.rating-myrating)<=100+100*floor(extract(epoch from(now()-least(q.joined_at,mine.joined_at)))/5)
 order by abs(q.rating-myrating),q.joined_at for update skip locked limit 1;
 if found then mid=sj_private.new_match(uid,opponent.user_id,mine.category_id,case when mine.subtopic_id is not distinct from opponent.subtopic_id then mine.subtopic_id else null end,'live'); end if;
 return jsonb_build_object('match_id',mid,'joined_at',mine.joined_at,'server_now',clock_timestamp(),
 'search_timeout_seconds',coalesce((select value from public.app_settings where key='search_timeout_seconds'),'10'::jsonb));
end $$;
create or replace function public.start_bot_match() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); mine public.matchmaking_queue; bot uuid; mid uuid; timeout int;
begin
 perform 1 from public.profiles where id=uid for update;
 select id into mid from public.matches where (player1_id=uid or player2_id=uid) and status in ('pending','in_progress') limit 1;
 if mid is not null then return jsonb_build_object('match_id',mid); end if;
 select * into mine from public.matchmaking_queue where user_id=uid for update;
 if not found then raise exception 'NOT_QUEUED'; end if;
 timeout=coalesce((select (value#>>'{}')::int from public.app_settings where key='search_timeout_seconds'),10);
 if now()<mine.joined_at+make_interval(secs=>timeout) then raise exception 'SEARCH_NOT_EXPIRED'; end if;
 insert into public.profiles(full_name,is_bot,rating,level,avatar_url)
 select name,true,mine.rating,8+floor(random()*28)::int,'color:'||(array['#5B4CFF','#087E83','#376BD6','#B66A13'])[1+floor(random()*4)::int]
 from sj_private.bot_names order by random() limit 1 returning id into bot;
 mid=sj_private.new_match(uid,bot,mine.category_id,case when mine.joined_at<now()-interval '8 seconds' then null else mine.subtopic_id end,'bot');
 return jsonb_build_object('match_id',mid);
end $$;
create or replace function sj_private.tick_match(mid uuid) returns void language plpgsql security definer set search_path='' as $$
declare m public.matches; mq public.match_questions; bp public.bot_plans; n int; oid uuid; q jsonb; d1 boolean; d2 boolean;
begin
 select * into m from public.matches where id=mid for update skip locked;
 if not found or m.status not in ('pending','in_progress') then return; end if;
 select heartbeat_at<now()-interval '15 seconds' into d1 from public.match_players where match_id=mid and user_id=m.player1_id;
 select heartbeat_at<now()-interval '15 seconds' into d2 from public.match_players where match_id=mid and user_id=m.player2_id;
 if m.mode='bot' then d2=false; end if;
 if d1 or d2 then perform sj_private.finalize_match(mid,case when d1 then m.player2_id else m.player1_id end,d1 and d2); return; end if;
 select * into mq from public.match_questions where match_id=mid and question_index=m.current_question_index for update;
 if m.phase in ('countdown','result') and now()>=m.next_tick_at then
 if m.phase='result' then
  if not exists(select 1 from public.match_questions where match_id=mid and question_index=m.current_question_index+1) then perform sj_private.finalize_match(mid); return; end if;
  update public.matches set current_question_index=current_question_index+1 where id=mid returning * into m;
  select * into mq from public.match_questions where match_id=mid and question_index=m.current_question_index;
 end if;
 update public.match_questions set started_at=clock_timestamp(),deadline_at=clock_timestamp()+make_interval(secs=>(snapshot->>'time_limit_seconds')::int) where id=mq.id returning * into mq;
 update public.matches set status='in_progress',phase='question',next_tick_at=mq.deadline_at+interval '500 milliseconds' where id=mid;
 perform sj_private.emit(mid,'question_start',sj_private.safe_question(mq.snapshot)||jsonb_build_object('started_at',mq.started_at,'deadline_at',mq.deadline_at,'question_index',mq.question_index));
 return;
 end if;
 if m.phase<>'question' then return; end if;
 q=mq.snapshot;
 if m.mode='bot' then
 select * into bp from public.bot_plans where match_id=mid and question_index=m.current_question_index;
 if now()>=mq.started_at+make_interval(secs=>bp.response_ms::numeric/1000) then
  select (value->>'id')::uuid into oid from jsonb_array_elements(q->'options') where ((value->>'id'=q->>'correct_option_id')=bp.will_be_correct) order by random() limit 1;
  insert into public.match_answers(match_id,question_index,user_id,option_id,is_correct,response_ms,points)
  values(mid,m.current_question_index,m.player2_id,oid,bp.will_be_correct,bp.response_ms,case when m.rules_version=2 then sj_private.battle_score(bp.will_be_correct,bp.response_ms,(q->>'time_limit_seconds')::int) else sj_private.score(bp.will_be_correct,bp.response_ms,(q->>'time_limit_seconds')::int,
  m.current_question_index=(select max(question_index) from public.match_questions where match_id=mid)) end) on conflict(match_id,question_index,user_id) do nothing;
 end if;
 end if;
 select count(*) into n from public.match_answers where match_id=mid and question_index=m.current_question_index;
 if n=2 or now()>mq.deadline_at+interval '500 milliseconds' then
 update public.match_questions set revealed_at=now() where id=mq.id;
 update public.matches set phase='result',next_tick_at=now()+interval '2 seconds' where id=mid;
 perform sj_private.emit(mid,'question_result',jsonb_build_object('question_index',mq.question_index));
 end if;
end $$;
create or replace function public.submit_answer(match_id uuid, question_index int, option_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); m public.matches; mq public.match_questions; elapsed int; correct boolean; points numeric;
begin
 perform sj_private.rate_limit('answer',120);
 select * into m from public.matches where id=match_id and (player1_id=uid or player2_id=uid) for update;
 if not found then raise exception 'MATCH_NOT_FOUND' using errcode='42501'; end if;
 if exists(select 1 from public.match_answers a where a.match_id=submit_answer.match_id and a.question_index=submit_answer.question_index and a.user_id=uid) then return jsonb_build_object('accepted',true); end if;
 select * into mq from public.match_questions where match_questions.match_id=submit_answer.match_id and match_questions.question_index=submit_answer.question_index;
 if m.status<>'in_progress' or m.phase<>'question' or m.current_question_index<>question_index or clock_timestamp()>mq.deadline_at+interval '500 milliseconds' then raise exception 'TIME_UP'; end if;
 if not exists(select 1 from jsonb_array_elements(mq.snapshot->'options') where value->>'id'=option_id::text) then raise exception 'INVALID_OPTION'; end if;
 elapsed=greatest(0,floor(extract(epoch from(clock_timestamp()-mq.started_at))*1000)::int);
 correct=option_id::text=mq.snapshot->>'correct_option_id';
 points=case when m.rules_version=2 then sj_private.battle_score(correct,elapsed,(mq.snapshot->>'time_limit_seconds')::int) else sj_private.score(correct,elapsed,(mq.snapshot->>'time_limit_seconds')::int,question_index=(select max(q.question_index) from public.match_questions q where q.match_id=submit_answer.match_id)) end;
 insert into public.match_answers(match_id,question_index,user_id,option_id,is_correct,response_ms,points) values(match_id,question_index,uid,option_id,correct,elapsed,points);
 perform sj_private.emit(match_id,'opponent_answered',jsonb_build_object('user_id',uid,'question_index',question_index));
 perform sj_private.tick_match(match_id);
 return jsonb_build_object('accepted',true);
end $$;
create or replace function sj_private.finalize_match(mid uuid, forced_winner uuid default null, abandoned boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare m public.matches; p record; winner uuid; s1 numeric; s2 numeric; t1 bigint; t2 bigint; actual numeric; expected numeric; delta int; reward int; ncorrect int;
begin
 select * into m from public.matches where id=mid for update;
 if m.status in ('completed','abandoned') then return; end if;
 if abandoned then update public.matches set status='abandoned',phase='finished',ended_at=now() where id=mid; return; end if;
 select coalesce(sum(points),0),coalesce(sum(response_ms) filter(where is_correct),0) into s1,t1 from public.match_answers where match_id=mid and user_id=m.player1_id;
 select coalesce(sum(points),0),coalesce(sum(response_ms) filter(where is_correct),0) into s2,t2 from public.match_answers where match_id=mid and user_id=m.player2_id;
 winner=coalesce(forced_winner,case when s1>s2 or (s1=s2 and t1<t2) then m.player1_id when s2>s1 or (s1=s2 and t2<t1) then m.player2_id else null end);
 for p in select mp.*,pr.is_bot from public.match_players mp join public.profiles pr on pr.id=mp.user_id where match_id=mid order by mp.user_id loop
 actual=case when winner is null then .5 when winner=p.user_id then 1 else 0 end;
 expected=1/(1+power(10::numeric,((select rating_before from public.match_players where match_id=mid and user_id<>p.user_id)-p.rating_before)::numeric/400));
 delta=round(32*(actual-expected)*case when m.mode='bot' then .5 else 1 end)::int;
 select count(*) into ncorrect from public.match_answers where match_id=mid and user_id=p.user_id and is_correct;
 reward=(case actual when 1 then 50 when .5 then 30 else 20 end)+5*ncorrect;
 update public.match_players set score=case when p.user_id=m.player1_id then s1 else s2 end,
 rating_after=greatest(0,p.rating_before+delta),xp_gained=reward,result=case actual when 1 then 'win' when .5 then 'draw' else 'loss' end where id=p.id;
 if not p.is_bot then
 update public.profiles set rating=greatest(0,rating+delta),xp=xp+reward,level=1+(xp+reward)/100 where id=p.user_id;
 insert into public.user_category_stats(user_id,category_id,played,correct,total_time_ms)
 select p.user_id,(mq.snapshot->>'category_id')::uuid,count(*),count(*) filter(where a.is_correct),coalesce(sum(a.response_ms),0)
 from public.match_questions mq left join public.match_answers a on a.match_id=mq.match_id and a.question_index=mq.question_index and a.user_id=p.user_id
 where mq.match_id=mid group by mq.snapshot->>'category_id'
 on conflict(user_id,category_id) do update set played=user_category_stats.played+excluded.played,correct=user_category_stats.correct+excluded.correct,total_time_ms=user_category_stats.total_time_ms+excluded.total_time_ms;
 end if;
 end loop;
 update public.matches set status='completed',phase='finished',winner_id=winner,ended_at=now() where id=mid;
 perform sj_private.emit(mid,'match_end',jsonb_build_object('match_id',mid));
end $$;
create or replace function sj_private.match_player_report(mid uuid, participant uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',p.id,'full_name',p.full_name,'is_bot',p.is_bot,
 'avatar_url',case when p.avatar_url like 'preset:%' or p.avatar_url like 'photo:%' then p.avatar_url end,
 'score',mp.score,'rating_before',mp.rating_before,'rating_after',mp.rating_after,
 'rating_change',coalesce(mp.rating_after,mp.rating_before)-mp.rating_before,
 'xp_gained',mp.xp_gained,'result',mp.result,
 'answered',a.answered,'correct',a.correct,'wrong',a.wrong,'unanswered',q.played-a.answered,
 'accuracy',case when q.played=0 then 0 else round(100.0*a.correct/q.played,1) end,
 'avg_response_ms',a.avg_response_ms,'avg_correct_response_ms',a.avg_correct_response_ms,
 'fastest_correct_ms',a.fastest_correct_ms,'total_response_ms',a.total_response_ms,
 'base_points',a.base_points,'speed_bonus',mp.score-a.base_points)
 from public.match_players mp join public.profiles p on p.id=mp.user_id
 cross join lateral(select count(*)::int played from public.match_questions mq where mq.match_id=mid and mq.started_at is not null) q
 cross join lateral(select count(*)::int answered,count(*) filter(where ans.is_correct)::int correct,
 count(*) filter(where not ans.is_correct)::int wrong,
 round(avg(ans.response_ms))::int avg_response_ms,
 round(avg(ans.response_ms) filter(where ans.is_correct))::int avg_correct_response_ms,
 min(ans.response_ms) filter(where ans.is_correct) fastest_correct_ms,
 coalesce(sum(ans.response_ms),0) total_response_ms,
 coalesce(sum(case when ans.is_correct then case when (select rules_version from public.matches where id=mid)=2 then 2 else 10*case when ans.question_index=(select max(x.question_index) from public.match_questions x where x.match_id=mid) then 2 else 1 end end else 0 end),0)::int base_points
 from public.match_answers ans join public.match_questions mq on mq.match_id=ans.match_id and mq.question_index=ans.question_index
 where ans.match_id=mid and ans.user_id=participant and mq.started_at is not null) a
 where mp.match_id=mid and mp.user_id=participant
$$;
create or replace function public.get_match_review(match_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); m public.matches; opponent uuid; questions jsonb;
begin
 select * into m from public.matches where id=match_id and status='completed' and (player1_id=uid or player2_id=uid);
 if not found then raise exception 'REVIEW_UNAVAILABLE' using errcode='42501'; end if;
 opponent=case when m.player1_id=uid then m.player2_id else m.player1_id end;
 select coalesce(jsonb_agg(q.snapshot||jsonb_build_object(
 'question_index',q.question_index,'started_at',q.started_at,'deadline_at',q.deadline_at,
 'category_name',(select name from public.categories where id=(q.snapshot->>'category_id')::uuid),
 'selected_option_id',a.option_id,'is_correct',coalesce(a.is_correct,false),'points',coalesce(a.points,0),
 'response_ms',a.response_ms,'opponent_option_id',b.option_id,'opponent_is_correct',coalesce(b.is_correct,false),
 'opponent_points',coalesce(b.points,0),'opponent_response_ms',b.response_ms,
 'multiplier',case when m.rules_version=2 then 1 when q.question_index=(select max(x.question_index) from public.match_questions x where x.match_id=m.id) then 2 else 1 end
 ) order by q.question_index),'[]'::jsonb) into questions
 from public.match_questions q
 left join public.match_answers a on a.match_id=q.match_id and a.question_index=q.question_index and a.user_id=uid
 left join public.match_answers b on b.match_id=q.match_id and b.question_index=q.question_index and b.user_id=opponent
 where q.match_id=m.id and q.started_at is not null;
 return jsonb_build_object('match_id',m.id,'mode',m.mode,'category_id',m.category_id,
 'question_count',(select count(*) from public.match_questions where match_questions.match_id=m.id),
 'rounds_played',jsonb_array_length(questions),'duration_ms',greatest(0,round(extract(epoch from(m.ended_at-m.started_at))*1000)),
 'completed_at',m.ended_at,'players',jsonb_build_array(sj_private.match_player_report(m.id,uid),sj_private.match_player_report(m.id,opponent)),
 'label_bots',coalesce((select value from public.app_settings where key='label_bots'),'true'::jsonb),
 'questions',questions);
end $$;
create or replace function sj_private.option_integrity() returns trigger language plpgsql security definer set search_path='' as $$
declare qid uuid; n int; correct int;
begin
 qid=case when TG_OP='DELETE' then old.question_id else new.question_id end;
 if not exists(select 1 from public.questions where id=qid) then return null; end if;
 select count(*),count(*) filter(where is_correct) into n,correct from public.question_options where question_id=qid;
 if n <>4 or correct<>1 then raise exception 'QUESTION_NEEDS_FOUR_OPTIONS_AND_ONE_CORRECT'; end if;
 return null;
end $$;
create or replace function sj_private.published_integrity() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='published' and (select count(*) from public.question_options where question_id=new.id) <>4
 then raise exception 'QUESTION_NEEDS_OPTIONS'; end if; return null;
end $$;
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
 perform sj_private.audit('save','questions',qid::text,jsonb_build_object('before',before_data,'after',payload));
 return qid;
end $$;
create or replace function public.admin_schedule_daily(day date,title text,question_ids uuid[] default null) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid; qid uuid; idx int=0;
begin
 perform sj_private.require_admin('editor');
 perform pg_advisory_xact_lock(hashtext('sj_daily_'||day::text));
 if day<(now() at time zone 'Asia/Kolkata')::date or day>(now() at time zone 'Asia/Kolkata')::date+365 or length(trim(title)) not between 2 and 100 then raise exception 'INVALID_CHALLENGE'; end if;
 select id into cid from public.daily_challenges where challenge_date=day for update;
 if exists(select 1 from public.daily_attempts where challenge_id=cid) then raise exception 'CHALLENGE_ALREADY_STARTED'; end if;
 if cid is null then cid=sj_private.generate_daily(day); end if;
 if question_ids is not null then
 if cardinality(question_ids) <>10 or (select count(distinct id) from public.questions where id=any(question_ids) and status='published')<>cardinality(question_ids) then raise exception 'INVALID_QUESTIONS'; end if;
 delete from public.daily_challenge_questions where challenge_id=cid;
 foreach qid in array question_ids loop
 insert into public.daily_challenge_questions(challenge_id,question_index,question_id,snapshot) values(cid,idx,qid,sj_private.question_snapshot(qid));idx=idx+1;
 end loop;
 end if;
 update public.daily_challenges set title=trim(admin_schedule_daily.title),status='scheduled',created_by=auth.uid() where id=cid;
 perform sj_private.audit('schedule','daily_challenges',cid::text,jsonb_build_object('day',day,'title',title));return cid;
end $$;

revoke all on all functions in schema sj_private from public,anon,authenticated;
revoke all on sj_private.bot_names from public,anon,authenticated;
commit;
