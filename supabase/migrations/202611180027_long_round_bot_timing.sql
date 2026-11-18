-- A response_ms equal to the round duration means the bot deliberately times out.
-- Only already-incorrect long rounds can time out, preserving the planned 2/3/4
-- correct answers and their equal probabilities.
create function sj_private.bot_response_ms(style text, duration_seconds int, will_be_correct boolean)
returns int language plpgsql volatile set search_path='' as $$
declare delay numeric;
begin
 if duration_seconds=40 then
  if not will_be_correct and random()<0.10 then return 40000; end if;
  delay=case style
   when 'Speedster' then 28+random()*4
   when 'Balanced' then 30+random()*5
   when 'Analytical' then 33+random()*5
   else 28+random()*11
  end;
 else
  -- Preserve the existing GK/English distributions exactly.
  delay=case style
   when 'Speedster' then case when duration_seconds=15 then 2+random()*4 else 8+random()*8 end
   when 'Analytical' then case when duration_seconds=15 then 5+random()*6 else 20+random()*14 end
   when 'Balanced' then case when duration_seconds=15 then 3+random()*5 else 12+random()*12 end
   else 2+random()*(duration_seconds-3)
  end;
 end if;
 return floor(delay*1000)::int;
end $$;
revoke all on function sj_private.bot_response_ms(text,int,boolean) from public,anon,authenticated;

create or replace function sj_private.new_match(p1 uuid,p2 uuid,category uuid,topic uuid,mode text)
returns uuid language plpgsql security definer set search_path='' as $$
declare mid uuid; r record; actor record; qid uuid; snap jsonb; correct_rounds int[];
        target int; style text;
begin
 for actor in select id from public.profiles where id in(p1,p2) and not is_bot order by id loop
  perform pg_advisory_xact_lock(hashtext('sj_question_player_'||actor.id::text));
 end loop;
 if mode='bot' then
  select b.play_style into style from sj_private.bot_names b
  join public.profiles p on p.full_name=b.name where p.id=p2;
 end if;
 style=coalesce(style,(array['Speedster','Analytical','Balanced','Wildcard'])[1+floor(random()*4)::int]);
 target=2+floor(random()*3)::int;
 select array_agg(i) into correct_rounds
 from (select i from generate_series(0,3) i order by random() limit target) t;
 insert into public.matches(category_id,mode,player1_id,player2_id,started_at,next_tick_at,rules_version,bot_style)
 values(null,mode,p1,p2,now()+interval '3 seconds',now()+interval '3 seconds',2,
        case when mode='bot' then style end) returning id into mid;
 insert into public.match_players(match_id,user_id,rating_before)
 select mid,id,rating from public.profiles where id in(p1,p2);
 for r in select b.*,c.id category from public.battle_rounds b
          join public.categories c on c.slug=b.subject_slug and c.is_active
          order by b.round_index loop
  qid=sj_private.shared_match_question(p1,p2,r.category,mode);
  snap=sj_private.question_snapshot(qid)||jsonb_build_object('time_limit_seconds',r.duration_seconds);
  insert into public.match_questions(match_id,question_index,question_id,snapshot,option_order)
  values(mid,r.round_index,qid,snap,snap->'options');
  if mode='bot' then
   insert into public.bot_plans(match_id,question_index,will_be_correct,response_ms)
   values(mid,r.round_index,r.round_index=any(correct_rounds),
          sj_private.bot_response_ms(style,r.duration_seconds,r.round_index=any(correct_rounds)));
  end if;
 end loop;
 if (select count(*) from public.match_questions where match_id=mid)<>4 then
  raise exception 'NOT_ENOUGH_QUESTIONS';
 end if;
 delete from public.matchmaking_queue where user_id in(p1,p2);
 perform realtime.send(jsonb_build_object('match_id',mid),'match_found','user:'||p1::text,true);
 if mode='live' then
  perform realtime.send(jsonb_build_object('match_id',mid),'match_found','user:'||p2::text,true);
 end if;
 return mid;
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
 -- A 40-second plan is a timeout sentinel. Never record an answer at or after
 -- the deadline, even if a scheduled tick runs late.
 if bp.response_ms<(q->>'time_limit_seconds')::int*1000
    and clock_timestamp()>=mq.started_at+make_interval(secs=>bp.response_ms::numeric/1000)
    and clock_timestamp()<mq.deadline_at then
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
