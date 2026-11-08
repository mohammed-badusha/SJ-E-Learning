create function sj_private.emit(mid uuid, event text, payload jsonb) returns void language plpgsql security definer set search_path='' as $$
begin perform realtime.send(payload,event,'match:'||mid::text,true); end $$;
create function sj_private.new_match(p1 uuid, p2 uuid, category uuid, topic uuid, mode text) returns uuid language plpgsql security definer set search_path='' as $$
declare mid uuid; n int; idx int=0; q record; snap jsonb; rating int;
begin
 n=coalesce((select (value#>>'{}')::int from public.app_settings where key='questions_per_match'),10);
 if (select count(*) from public.questions where status='published' and (category is null or category_id=category) and (topic is null or subtopic_id=topic))<n
 then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 insert into public.matches(category_id,mode,player1_id,player2_id,started_at,next_tick_at) values(category,mode,p1,p2,now()+interval '3 seconds',now()+interval '3 seconds') returning id into mid;
 insert into public.match_players(match_id,user_id,rating_before) select mid,id,profiles.rating from public.profiles where id in (p1,p2);
 select profiles.rating into rating from public.profiles where id=p2;
 for q in
 select qu.* from public.questions qu where qu.status='published' and (category is null or qu.category_id=category) and (topic is null or qu.subtopic_id=topic)
 order by exists(select 1 from public.match_questions mq join (select m.id from public.matches m where m.player1_id in (p1,p2) or m.player2_id in (p1,p2) order by m.created_at desc limit 20) recent on recent.id=mq.match_id where mq.question_id=qu.id),
 -- Difficulty strata are interleaved before random sampling.
 row_number() over(partition by qu.difficulty order by random()) / case when qu.difficulty='hard' then 2 else 4 end,random() limit n
 loop
 snap=sj_private.question_snapshot(q.id);
 insert into public.match_questions(match_id,question_index,question_id,snapshot,option_order) values(mid,idx,q.id,snap,snap->'options');
 if mode='bot' then insert into public.bot_plans(match_id,question_index,will_be_correct,response_ms)
 values(mid,idx,random()<greatest(.25,least(.95,.45+(rating-800)*.0005+case q.difficulty when 'easy' then .08 when 'hard' then -.12 else 0 end)),
 floor(q.time_limit_seconds*1000*(.3+random()*.6))::int); end if;
 idx=idx+1;
 end loop;
 delete from public.matchmaking_queue where user_id in (p1,p2);
 perform realtime.send(jsonb_build_object('match_id',mid),'match_found','user:'||p1::text,true);
 if mode='live' then perform realtime.send(jsonb_build_object('match_id',mid),'match_found','user:'||p2::text,true); end if;
 return mid;
end $$;
create function public.join_matchmaking(category_id uuid default null, subtopic_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); myrating int; opponent public.matchmaking_queue; mine public.matchmaking_queue; mid uuid;
begin
 perform sj_private.rate_limit('join',30);
 perform 1 from public.profiles where id=uid for update;
 select id into mid from public.matches where (player1_id=uid or player2_id=uid) and status in ('pending','in_progress') limit 1;
 if mid is not null then return jsonb_build_object('match_id',mid); end if;
 if category_id is not null and not exists(select 1 from public.categories c where c.id=category_id and c.is_active) then raise exception 'CATEGORY_UNAVAILABLE'; end if;
 if subtopic_id is not null and not exists(select 1 from public.subtopics s where s.id=subtopic_id and s.category_id=join_matchmaking.category_id and s.is_active) then raise exception 'INVALID_SUBTOPIC'; end if;
 if (select count(*) from public.questions q where status='published' and (join_matchmaking.category_id is null or q.category_id=join_matchmaking.category_id)
 and (join_matchmaking.subtopic_id is null or q.subtopic_id=join_matchmaking.subtopic_id))<coalesce((select (value#>>'{}')::int from public.app_settings where key='questions_per_match'),10)
 then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 select rating into myrating from public.profiles where id=uid;
 insert into public.matchmaking_queue(user_id,category_id,subtopic_id,rating) values(uid,category_id,subtopic_id,myrating)
 on conflict(user_id) do nothing;
 select * into mine from public.matchmaking_queue where user_id=uid for update;
 select * into opponent from public.matchmaking_queue q where q.user_id<>uid and q.category_id is not distinct from mine.category_id
 and (q.subtopic_id is not distinct from mine.subtopic_id or least(q.joined_at,mine.joined_at)<now()-interval '8 seconds')
 and q.joined_at>now()-interval '60 seconds'
 and abs(q.rating-myrating)<=100+100*floor(extract(epoch from(now()-least(q.joined_at,mine.joined_at)))/5)
 order by abs(q.rating-myrating),q.joined_at for update skip locked limit 1;
 if found then mid=sj_private.new_match(uid,opponent.user_id,mine.category_id,case when mine.subtopic_id is not distinct from opponent.subtopic_id then mine.subtopic_id else null end,'live'); end if;
 return jsonb_build_object('match_id',mid,'joined_at',mine.joined_at,'server_now',clock_timestamp(),
 'search_timeout_seconds',coalesce((select value from public.app_settings where key='search_timeout_seconds'),'20'::jsonb));
end $$;
create function public.leave_matchmaking() returns void language plpgsql security definer set search_path='' as $$
begin delete from public.matchmaking_queue where user_id=auth.uid(); end $$;
create function public.start_bot_match() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); mine public.matchmaking_queue; bot uuid; mid uuid; timeout int;
begin
 perform 1 from public.profiles where id=uid for update;
 select id into mid from public.matches where (player1_id=uid or player2_id=uid) and status in ('pending','in_progress') limit 1;
 if mid is not null then return jsonb_build_object('match_id',mid); end if;
 select * into mine from public.matchmaking_queue where user_id=uid for update;
 if not found then raise exception 'NOT_QUEUED'; end if;
 timeout=coalesce((select (value#>>'{}')::int from public.app_settings where key='search_timeout_seconds'),20);
 if now()<mine.joined_at+make_interval(secs=>timeout) then raise exception 'SEARCH_NOT_EXPIRED'; end if;
 select id into bot from public.profiles where is_bot and not is_banned order by abs(rating-mine.rating),random() limit 1;
 if bot is null then raise exception 'NO_PRACTICE_OPPONENT'; end if;
 mid=sj_private.new_match(uid,bot,mine.category_id,case when mine.joined_at<now()-interval '8 seconds' then null else mine.subtopic_id end,'bot');
 return jsonb_build_object('match_id',mid);
end $$;
create function sj_private.finalize_match(mid uuid, forced_winner uuid default null, abandoned boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare m public.matches; p record; winner uuid; s1 int; s2 int; t1 bigint; t2 bigint; actual numeric; expected numeric; delta int; reward int; ncorrect int;
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
create function sj_private.tick_match(mid uuid) returns void language plpgsql security definer set search_path='' as $$
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
  values(mid,m.current_question_index,m.player2_id,oid,bp.will_be_correct,bp.response_ms,sj_private.score(bp.will_be_correct,bp.response_ms,(q->>'time_limit_seconds')::int,
  m.current_question_index=(select max(question_index) from public.match_questions where match_id=mid))) on conflict(match_id,question_index,user_id) do nothing;
 end if;
 end if;
 select count(*) into n from public.match_answers where match_id=mid and question_index=m.current_question_index;
 if n=2 or now()>mq.deadline_at+interval '500 milliseconds' then
 update public.match_questions set revealed_at=now() where id=mq.id;
 update public.matches set phase='result',next_tick_at=now()+interval '2 seconds' where id=mid;
 perform sj_private.emit(mid,'question_result',jsonb_build_object('question_index',mq.question_index));
 end if;
end $$;
create function public.submit_answer(match_id uuid, question_index int, option_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); m public.matches; mq public.match_questions; elapsed int; correct boolean; points int;
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
 points=sj_private.score(correct,elapsed,(mq.snapshot->>'time_limit_seconds')::int,question_index=(select max(q.question_index) from public.match_questions q where q.match_id=submit_answer.match_id));
 insert into public.match_answers(match_id,question_index,user_id,option_id,is_correct,response_ms,points) values(match_id,question_index,uid,option_id,correct,elapsed,points);
 perform sj_private.emit(match_id,'opponent_answered',jsonb_build_object('user_id',uid,'question_index',question_index));
 perform sj_private.tick_match(match_id);
 return jsonb_build_object('accepted',true);
end $$;
create function public.get_match_state(match_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); m public.matches; mq public.match_questions;
begin
 select * into m from public.matches where id=match_id and (player1_id=uid or player2_id=uid);
 if not found then raise exception 'MATCH_NOT_FOUND' using errcode='42501'; end if;
 update public.match_players set heartbeat_at=now() where match_players.match_id=get_match_state.match_id and user_id=uid;
 select * into mq from public.match_questions where match_questions.match_id=get_match_state.match_id and question_index=m.current_question_index;
 return jsonb_build_object('match_id',m.id,'status',m.status,'phase',m.phase,'mode',m.mode,'question_index',m.current_question_index,
 'question_count',(select count(*) from public.match_questions q where q.match_id=m.id),'server_now',clock_timestamp(),'starts_at',m.started_at,
 'label_bots',coalesce((select value from public.app_settings where key='label_bots'),'true'::jsonb),
 'players',(select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'rating',mp.rating_before,'score',coalesce((select sum(points) from public.match_answers a join public.match_questions q on q.match_id=a.match_id and q.question_index=a.question_index where a.match_id=m.id and a.user_id=p.id and q.revealed_at is not null),0),
 'rating_after',mp.rating_after,'xp_gained',mp.xp_gained,'result',mp.result,'connected',p.is_bot or mp.heartbeat_at>now()-interval '5 seconds')) from public.match_players mp join public.profiles p on p.id=mp.user_id where mp.match_id=m.id),
 'question',case when mq.started_at is null then null else sj_private.safe_question(mq.snapshot)||jsonb_build_object('started_at',mq.started_at,'deadline_at',mq.deadline_at) end,
 'answered',(select coalesce(jsonb_agg(a.user_id),'[]') from public.match_answers a where a.match_id=m.id and a.question_index=m.current_question_index),
 'result',case when mq.revealed_at is not null then jsonb_build_object('correct_option_id',mq.snapshot->>'correct_option_id','explanation',mq.snapshot->>'explanation',
 'answers',(select coalesce(jsonb_agg(jsonb_build_object('user_id',a.user_id,'option_id',a.option_id,'points',a.points)),'[]') from public.match_answers a where a.match_id=m.id and a.question_index=m.current_question_index)) else null end);
end $$;
create function public.forfeit_match(match_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); m public.matches;
begin select * into m from public.matches where id=match_id and (player1_id=uid or player2_id=uid) for update;
 if not found then raise exception 'MATCH_NOT_FOUND'; end if;
 perform sj_private.finalize_match(match_id,case when m.player1_id=uid then m.player2_id else m.player1_id end);
end $$;
create function public.get_match_review(match_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player();
begin
 if not exists(select 1 from public.matches where id=match_id and status='completed' and (player1_id=uid or player2_id=uid)) then raise exception 'REVIEW_UNAVAILABLE'; end if;
 return jsonb_build_object('questions',(select jsonb_agg(q.snapshot||jsonb_build_object('selected_option_id',a.option_id,'is_correct',coalesce(a.is_correct,false),'points',coalesce(a.points,0)) order by q.question_index)
 from public.match_questions q left join public.match_answers a on a.match_id=q.match_id and a.question_index=q.question_index and a.user_id=uid where q.match_id=get_match_review.match_id));
end $$;
create function sj_private.tick_all() returns void language plpgsql security definer set search_path='' as $$
declare m record;
begin
 for m in select id from public.matches where status in ('pending','in_progress') loop perform sj_private.tick_match(m.id); end loop;
 delete from public.matchmaking_queue where joined_at<now()-interval '60 seconds';
end $$;
create function public.can_read_arena_topic(topic text) returns boolean language sql stable security definer set search_path='' as $$
 select topic='user:'||auth.uid()::text or exists(select 1 from public.matches m where topic='match:'||m.id::text and (m.player1_id=auth.uid() or m.player2_id=auth.uid()))
$$;
create policy arena_receive on realtime.messages for select to authenticated using(public.can_read_arena_topic(realtime.topic()));
-- Clients cannot broadcast forged question/result events: no INSERT policy on realtime.messages.
revoke all on all functions in schema sj_private from public,anon,authenticated;
revoke all on function public.join_matchmaking(uuid,uuid),public.leave_matchmaking(),public.start_bot_match(),public.submit_answer(uuid,int,uuid),
 public.get_match_state(uuid),public.forfeit_match(uuid),public.get_match_review(uuid),public.can_read_arena_topic(text) from public,anon;
grant execute on function public.join_matchmaking(uuid,uuid),public.leave_matchmaking(),public.start_bot_match(),public.submit_answer(uuid,int,uuid),
 public.get_match_state(uuid),public.forfeit_match(uuid),public.get_match_review(uuid),public.can_read_arena_topic(text) to authenticated;
