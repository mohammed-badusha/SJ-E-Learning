-- Wake a match only for its next server event or a missed human heartbeat.
-- The one-second cron cadence and all public match RPCs remain compatible.
begin;

-- The former FOR UPDATE on the caller's profile deadlocked when another
-- request held that caller's queue row and inserted a match (FK KEY SHARE).
-- Serialize only requests from the same caller without locking either
-- player's profile. SKIP LOCKED still chooses one opponent atomically.
create or replace function public.join_matchmaking(
 category_id uuid default null, subtopic_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); myrating int;
        opponent public.matchmaking_queue; mine public.matchmaking_queue; mid uuid;
begin
 perform sj_private.rate_limit('join',30);
 perform pg_advisory_xact_lock(hashtext('sj_matchmaking_user_'||uid::text));
 select id into mid from public.matches
 where (player1_id=uid or player2_id=uid)
   and status in ('pending','in_progress') limit 1;
 if mid is not null then return jsonb_build_object('match_id',mid); end if;
 if exists(select 1 from public.battle_rounds b
   left join public.categories c on c.slug=b.subject_slug and c.is_active
   where c.id is null or not exists(select 1 from public.questions q
     where q.category_id=c.id and q.status='published'
     and (select count(*) from public.question_options o where o.question_id=q.id)=4))
 then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 select rating into myrating from public.profiles where id=uid;
 insert into public.matchmaking_queue(user_id,category_id,subtopic_id,rating)
 values(uid,null,null,myrating) on conflict(user_id) do nothing;
 select * into mine from public.matchmaking_queue where user_id=uid for update;
 if not found then
  -- Another request may have matched and removed this queue row while this
  -- call waited on its lock. Return that match rather than a null timestamp.
  select id into mid from public.matches
  where (player1_id=uid or player2_id=uid)
    and status in ('pending','in_progress') limit 1;
  if mid is not null then return jsonb_build_object('match_id',mid); end if;
  insert into public.matchmaking_queue(user_id,category_id,subtopic_id,rating)
  values(uid,null,null,myrating) on conflict(user_id) do nothing;
  select * into mine from public.matchmaking_queue where user_id=uid for update;
 end if;
 select * into opponent from public.matchmaking_queue q
 where q.user_id<>uid and q.category_id is not distinct from mine.category_id
   and (q.subtopic_id is not distinct from mine.subtopic_id
     or least(q.joined_at,mine.joined_at)<now()-interval '8 seconds')
   and q.joined_at>now()-interval '60 seconds'
   and abs(q.rating-myrating)<=100+100*floor(extract(epoch from
     (now()-least(q.joined_at,mine.joined_at)))/5)
 order by abs(q.rating-myrating),q.joined_at for update skip locked limit 1;
 if found then
  mid=sj_private.new_match(uid,opponent.user_id,mine.category_id,
   case when mine.subtopic_id is not distinct from opponent.subtopic_id
     then mine.subtopic_id else null end,'live');
 end if;
 return jsonb_build_object('match_id',mid,'joined_at',mine.joined_at,
  'server_now',clock_timestamp(),
  'search_timeout_seconds',coalesce((select value from public.app_settings
    where key='search_timeout_seconds'),'10'::jsonb));
end $$;

create or replace function public.start_bot_match() returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); mine public.matchmaking_queue;
        bot uuid; mid uuid; timeout int;
begin
 perform pg_advisory_xact_lock(hashtext('sj_matchmaking_user_'||uid::text));
 select id into mid from public.matches
 where (player1_id=uid or player2_id=uid)
   and status in ('pending','in_progress') limit 1;
 if mid is not null then return jsonb_build_object('match_id',mid); end if;
 select * into mine from public.matchmaking_queue where user_id=uid for update;
 if not found then
  select id into mid from public.matches
  where (player1_id=uid or player2_id=uid)
    and status in ('pending','in_progress') limit 1;
  if mid is not null then return jsonb_build_object('match_id',mid); end if;
  raise exception 'NOT_QUEUED';
 end if;
 timeout=coalesce((select (value#>>'{}')::int from public.app_settings
   where key='search_timeout_seconds'),10);
 if now()<mine.joined_at+make_interval(secs=>timeout) then
  raise exception 'SEARCH_NOT_EXPIRED';
 end if;
 bot=sj_private.next_bot_for_player(uid);
 mid=sj_private.new_match(uid,bot,mine.category_id,
  case when mine.joined_at<now()-interval '8 seconds'
    then null else mine.subtopic_id end,'bot');
 return jsonb_build_object('match_id',mid);
end $$;

create or replace function sj_private.tick_match(mid uuid) returns void
language plpgsql security definer set search_path='' as $$
declare m public.matches; mq public.match_questions; bp public.bot_plans;
        n int; oid uuid; q jsonb; d1 boolean; d2 boolean;
        bot_at timestamptz; wake_at timestamptz;
begin
 select * into m from public.matches where id=mid for update skip locked;
 if not found or m.status not in ('pending','in_progress') then return; end if;
 select heartbeat_at<now()-interval '15 seconds' into d1
 from public.match_players where match_id=mid and user_id=m.player1_id;
 select heartbeat_at<now()-interval '15 seconds' into d2
 from public.match_players where match_id=mid and user_id=m.player2_id;
 if m.mode='bot' then d2=false; end if;
 if d1 or d2 then
  perform sj_private.finalize_match(mid,
    case when d1 then m.player2_id else m.player1_id end,d1 and d2);
  return;
 end if;
 select * into mq from public.match_questions
 where match_id=mid and question_index=m.current_question_index for update;
 if m.phase in ('countdown','result') and now()>=m.next_tick_at then
  if m.phase='result' then
   if not exists(select 1 from public.match_questions
     where match_id=mid and question_index=m.current_question_index+1) then
    perform sj_private.finalize_match(mid); return;
   end if;
   update public.matches set current_question_index=current_question_index+1
   where id=mid returning * into m;
   select * into mq from public.match_questions
   where match_id=mid and question_index=m.current_question_index;
  end if;
  update public.match_questions
  set started_at=clock_timestamp(),
      deadline_at=clock_timestamp()+make_interval(secs=>(snapshot->>'time_limit_seconds')::int)
  where id=mq.id returning * into mq;
  wake_at=mq.deadline_at+interval '500 milliseconds';
  if m.mode='bot' then
   select * into bp from public.bot_plans
   where match_id=mid and question_index=m.current_question_index;
   if bp.response_ms<(mq.snapshot->>'time_limit_seconds')::int*1000 then
    bot_at=mq.started_at+make_interval(secs=>bp.response_ms::numeric/1000);
    wake_at=least(wake_at,bot_at);
   end if;
  end if;
  update public.matches set status='in_progress',phase='question',next_tick_at=wake_at
  where id=mid;
  perform sj_private.emit(mid,'question_start',
   sj_private.safe_question(mq.snapshot)||jsonb_build_object(
    'started_at',mq.started_at,'deadline_at',mq.deadline_at,
    'question_index',mq.question_index));
  return;
 end if;
 if m.phase<>'question' then return; end if;
 q=mq.snapshot;
 if m.mode='bot' then
  select * into bp from public.bot_plans
  where match_id=mid and question_index=m.current_question_index;
  if bp.response_ms<(q->>'time_limit_seconds')::int*1000
     and clock_timestamp()>=mq.started_at+make_interval(secs=>bp.response_ms::numeric/1000)
     and clock_timestamp()<mq.deadline_at then
   select (value->>'id')::uuid into oid from jsonb_array_elements(q->'options')
   where ((value->>'id'=q->>'correct_option_id')=bp.will_be_correct)
   order by random() limit 1;
   insert into public.match_answers(match_id,question_index,user_id,option_id,
     is_correct,response_ms,points)
   values(mid,m.current_question_index,m.player2_id,oid,bp.will_be_correct,
     bp.response_ms,case when m.rules_version=2 then
       sj_private.battle_score(bp.will_be_correct,bp.response_ms,
         (q->>'time_limit_seconds')::int)
      else sj_private.score(bp.will_be_correct,bp.response_ms,
         (q->>'time_limit_seconds')::int,
         m.current_question_index=(select max(question_index)
           from public.match_questions where match_id=mid)) end)
   on conflict(match_id,question_index,user_id) do nothing;
  end if;
 end if;
 select count(*) into n from public.match_answers
 where match_id=mid and question_index=m.current_question_index;
 if n=2 or now()>mq.deadline_at+interval '500 milliseconds' then
  update public.match_questions set revealed_at=now() where id=mq.id;
  update public.matches set phase='result',next_tick_at=now()+interval '2 seconds'
  where id=mid;
  perform sj_private.emit(mid,'question_result',
    jsonb_build_object('question_index',mq.question_index));
 else
  -- submit_answer also invokes tick_match before the bot's scheduled time.
  -- Keep that wake-up until the bot answers; then wait for the deadline.
  wake_at=mq.deadline_at+interval '500 milliseconds';
  if m.mode='bot' and bp.response_ms<(q->>'time_limit_seconds')::int*1000
     and not exists(select 1 from public.match_answers a
       where a.match_id=mid and a.question_index=m.current_question_index
         and a.user_id=m.player2_id) then
   wake_at=least(wake_at,
     mq.started_at+make_interval(secs=>bp.response_ms::numeric/1000));
  end if;
  update public.matches set next_tick_at=wake_at
  where id=mid and next_tick_at is distinct from wake_at;
 end if;
end $$;

-- New clients use this small response for liveness and as a safety net when a
-- Realtime broadcast is missed. Old get_match_state clients remain unchanged.
create function public.heartbeat_match(match_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); m public.matches;
        rival uuid; connected boolean; answered_count int;
begin
 select * into m from public.matches
 where id=heartbeat_match.match_id and (player1_id=uid or player2_id=uid);
 if not found then raise exception 'MATCH_NOT_FOUND' using errcode='42501'; end if;
 if m.status in ('pending','in_progress') then
  update public.match_players set heartbeat_at=clock_timestamp()
  where match_players.match_id=m.id and user_id=uid;
 end if;
 rival=case when m.player1_id=uid then m.player2_id else m.player1_id end;
 select (m.mode='bot' and rival=m.player2_id)
   or mp.heartbeat_at>clock_timestamp()-interval '5 seconds'
 into connected from public.match_players mp
 where mp.match_id=m.id and mp.user_id=rival;
 select count(*) into answered_count from public.match_answers a
 where a.match_id=m.id and a.question_index=m.current_question_index;
 return jsonb_build_object('status',m.status,'phase',m.phase,
  'question_index',m.current_question_index,'answered_count',answered_count,
  'opponent_connected',connected,'server_now',clock_timestamp());
end $$;
revoke all on function public.heartbeat_match(uuid) from public,anon;
grant execute on function public.heartbeat_match(uuid) to authenticated;

create or replace function sj_private.tick_all() returns void
language plpgsql security definer set search_path='' as $$
declare due record; tick_started_at timestamptz=clock_timestamp();
begin
 -- Cron may launch another tick while the previous one is still running.
 -- A skipped run is safe: due work remains due for the next second.
 if not pg_try_advisory_xact_lock(hashtext('sj_match_engine_tick')) then return; end if;
 for due in
  select id from (
   select id,next_tick_at as wake_at from public.matches
   where status in ('pending','in_progress') and next_tick_at<=tick_started_at
   union all
   select m.id,
     least(p1.heartbeat_at,
       case when m.mode='live' then p2.heartbeat_at else p1.heartbeat_at end)
       +interval '15 seconds' as wake_at
   from public.matches m
   join public.match_players p1 on p1.match_id=m.id
     and p1.user_id=m.player1_id
   join public.match_players p2 on p2.match_id=m.id
     and p2.user_id=m.player2_id
   where m.status in ('pending','in_progress')
     and (p1.heartbeat_at<tick_started_at-interval '15 seconds'
       or (m.mode='live' and
         p2.heartbeat_at<tick_started_at-interval '15 seconds'))
  ) pending group by id order by min(wake_at)
 loop
  begin
   perform sj_private.tick_match(due.id);
  exception when deadlock_detected or serialization_failure then
   -- The failed match subtransaction rolls back; its due timestamp remains
   -- eligible for the next cron pass instead of losing the event.
   null;
  when others then
   -- A transient broadcast/database failure also leaves the match due.
   -- Continue other matches and let the next second retry this one.
   raise warning 'MATCH_TICK_RETRY match=% state=%',due.id,sqlstate;
  end;
 end loop;
 delete from public.matchmaking_queue where joined_at<now()-interval '60 seconds';
end $$;

-- Match instances already running when this migration is applied must also
-- wake for their pending bot response rather than waiting until the deadline.
update public.matches m set next_tick_at=least(
  m.next_tick_at,
  mq.started_at+make_interval(secs=>bp.response_ms::numeric/1000))
from public.match_questions mq join public.bot_plans bp
  on bp.match_id=mq.match_id and bp.question_index=mq.question_index
where m.id=mq.match_id and m.mode='bot' and m.status='in_progress'
  and m.phase='question' and m.current_question_index=mq.question_index
  and mq.started_at is not null and mq.deadline_at is not null
  and bp.response_ms<(mq.snapshot->>'time_limit_seconds')::int*1000
  and not exists(select 1 from public.match_answers a
    where a.match_id=m.id and a.question_index=m.current_question_index
      and a.user_id=m.player2_id);

commit;
