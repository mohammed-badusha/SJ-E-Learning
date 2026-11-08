-- Share the current player picture with the two participants in a completed battle report.
begin;
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
 coalesce(sum(case when ans.is_correct then 10*case when ans.question_index=(select max(x.question_index) from public.match_questions x where x.match_id=mid) then 2 else 1 end else 0 end),0)::int base_points
 from public.match_answers ans join public.match_questions mq on mq.match_id=ans.match_id and mq.question_index=ans.question_index
 where ans.match_id=mid and ans.user_id=participant and mq.started_at is not null) a
 where mp.match_id=mid and mp.user_id=participant
$$;
create or replace function public.get_player_photo(photo_id uuid, match_id uuid default null)
returns text language sql stable security definer set search_path='' as $$
 select replace(encode(f.thumbnail,'base64'),chr(10),'') from sj_private.player_photos f
 where f.photo_id=get_player_photo.photo_id and (f.owner_id=auth.uid() or exists (
 select 1 from public.matches m where m.id=get_player_photo.match_id and auth.uid() in (m.player1_id,m.player2_id)
 and f.owner_id in (m.player1_id,m.player2_id) and m.status in ('pending','in_progress','completed')))
$$;
commit;
