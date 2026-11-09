begin;
create function public.get_history_page(before_at timestamptz default null, before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid=sj_private.require_player();
begin
 if (before_at is null)<>(before_id is null) then raise exception 'INVALID_CURSOR'; end if;
 return jsonb_build_object('rows',(select coalesce(jsonb_agg(r order by r.played_at desc,r.id desc),'[]') from (
 select * from (
  select m.id,'battle'::text mode,m.created_at played_at,mp.score,mp.result,
   (select full_name from public.profiles where id=case when m.player1_id=uid then m.player2_id else m.player1_id end) title
  from public.match_players mp join public.matches m on m.id=mp.match_id where mp.user_id=uid and m.status='completed'
  union all
  select p.id,'practice',p.started_at,p.score,null,'Practice' from public.practice_attempts p where p.user_id=uid and p.completed_at is not null
  union all
  select a.id,'daily',a.started_at,a.score,null,c.title from public.daily_attempts a join public.daily_challenges c on c.id=a.challenge_id
  where a.user_id=uid and a.completed_at is not null
 ) history where before_at is null or (played_at,id)<(before_at,before_id)
 order by played_at desc,id desc limit 30) r));
end $$;
create function public.get_daily_review(attempt_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); a public.daily_attempts;
begin
 select * into a from public.daily_attempts where id=attempt_id and user_id=uid and completed_at is not null;
 if not found then raise exception 'REVIEW_UNAVAILABLE'; end if;
 return jsonb_build_object('questions',(select jsonb_agg(q.snapshot||jsonb_build_object(
 'selected_option_id',r.option_id,'is_correct',coalesce(r.is_correct,false),'points',coalesce(r.points,0)) order by q.question_index)
 from public.daily_challenge_questions q left join public.daily_attempt_answers r on r.attempt_id=a.id and r.question_index=q.question_index where q.challenge_id=a.challenge_id));
end $$;
revoke all on function public.get_history_page(timestamptz,uuid),public.get_daily_review(uuid) from public,anon;
grant execute on function public.get_history_page(timestamptz,uuid),public.get_daily_review(uuid) to authenticated;
commit;
