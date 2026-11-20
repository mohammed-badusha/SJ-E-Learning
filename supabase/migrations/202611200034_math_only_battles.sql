-- Battles use four distinct Quantitative Aptitude questions. Daily Challenge
-- continues to use the four subject definitions in public.battle_rounds.
begin;

create function sj_private.shared_match_question(p1 uuid,p2 uuid,subject_id uuid,match_mode text,excluded_ids uuid[])
returns uuid language plpgsql security definer set search_path='' as $$
declare first_cycle public.player_question_cycles; second_cycle public.player_question_cycles;
        first_unused uuid[]; second_unused uuid[]; selected uuid;
begin
 first_cycle=sj_private.prepare_question_cycle(p1,subject_id);
 first_unused=coalesce(first_cycle.question_ids[first_cycle.next_index+1:cardinality(first_cycle.question_ids)],'{}'::uuid[]);
 if match_mode='bot' then
  select id into selected from unnest(first_unused) with ordinality available(id,position)
  where id<>all(coalesce(excluded_ids,'{}'::uuid[])) order by position limit 1;
 else
  second_cycle=sj_private.prepare_question_cycle(p2,subject_id);
  second_unused=coalesce(second_cycle.question_ids[second_cycle.next_index+1:cardinality(second_cycle.question_ids)],'{}'::uuid[]);
  select q.id into selected from public.questions q
  join public.categories c on c.id=q.category_id and c.is_active
  where q.category_id=subject_id and q.status='published'
    and q.id=any(first_cycle.question_ids) and q.id=any(second_cycle.question_ids)
    and q.id<>all(coalesce(excluded_ids,'{}'::uuid[]))
    and (select count(*) from public.question_options o where o.question_id=q.id)=4
  order by case when q.id=any(first_unused) and q.id=any(second_unused) then 0
                when q.id=any(first_unused) or q.id=any(second_unused) then 1 else 2 end,
           random()
  limit 1;
 end if;
 if selected is null then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 perform sj_private.mark_question_seen(p1,subject_id,selected);
 if match_mode='live' then perform sj_private.mark_question_seen(p2,subject_id,selected); end if;
 return selected;
end $$;
revoke all on function sj_private.shared_match_question(uuid,uuid,uuid,text,uuid[]) from public,anon,authenticated;

create or replace function sj_private.new_match(p1 uuid,p2 uuid,category uuid,topic uuid,mode text)
returns uuid language plpgsql security definer set search_path='' as $$
declare mid uuid; r record; actor record; qid uuid; snap jsonb; correct_rounds int[];
        target int; style text; quant_id uuid; selected_ids uuid[]='{}'::uuid[];
begin
 for actor in select id from public.profiles where id in(p1,p2) and not is_bot order by id loop
  perform pg_advisory_xact_lock(hashtext('sj_question_player_'||actor.id::text));
 end loop;
 select id into quant_id from public.categories where slug='quant' and is_active;
 if quant_id is null or (select count(*) from public.questions q
   where q.category_id=quant_id and q.status='published'
   and (select count(*) from public.question_options o where o.question_id=q.id)=4)<4 then
  raise exception 'NOT_ENOUGH_QUESTIONS';
 end if;
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
 for r in select generate_series(0,3) round_index loop
  qid=sj_private.shared_match_question(p1,p2,quant_id,mode,selected_ids);
  selected_ids=array_append(selected_ids,qid);
  snap=sj_private.question_snapshot(qid)||jsonb_build_object('time_limit_seconds',40);
  insert into public.match_questions(match_id,question_index,question_id,snapshot,option_order)
  values(mid,r.round_index,qid,snap,snap->'options');
  if mode='bot' then
   insert into public.bot_plans(match_id,question_index,will_be_correct,response_ms)
   values(mid,r.round_index,r.round_index=any(correct_rounds),
          sj_private.bot_response_ms(style,40,r.round_index=any(correct_rounds)));
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

commit;
