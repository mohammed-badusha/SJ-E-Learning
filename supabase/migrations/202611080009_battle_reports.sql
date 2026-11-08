-- Backwards-compatible completed-match review, enriched with real comparison stats.
-- Apply this migration only to existing projects; do not rerun setup.sql.
begin;
create or replace function sj_private.match_player_report(mid uuid, participant uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',p.id,'full_name',p.full_name,'is_bot',p.is_bot,
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
 coalesce(sum(case when ans.is_correct then 10*case when ans.question_index=(select max(x.question_index) from public.match_questions x where x.match_id=mid) then 2 else 1 end else 0 end),0)::int base_points
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
 'multiplier',case when q.question_index=(select max(x.question_index) from public.match_questions x where x.match_id=m.id) then 2 else 1 end
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
revoke all on function sj_private.match_player_report(uuid,uuid) from public,anon,authenticated;
revoke all on function public.get_match_review(uuid) from public,anon;
grant execute on function public.get_match_review(uuid) to authenticated;
commit;
