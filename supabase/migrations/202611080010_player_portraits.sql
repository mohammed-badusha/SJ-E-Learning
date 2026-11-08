-- Small, private portrait thumbnails. Live polling returns references only.
create table sj_private.player_photos (
  owner_id uuid primary key references public.profiles(id) on delete cascade,
  photo_id uuid not null unique default gen_random_uuid(),
  thumbnail bytea not null check (octet_length(thumbnail) between 24 and 180000)
);
revoke all on sj_private.player_photos from public,anon,authenticated;
create function public.save_profile_portrait(full_name text, phone text, portrait text, photo_png text default null)
returns void language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); image_data bytea; photo uuid;
begin
  perform public.complete_profile(full_name,phone);
  if portrait='gallery' then
    if photo_png is null or length(photo_png)>240000 then raise exception 'INVALID_PHOTO'; end if;
    image_data=decode(photo_png,'base64');
    if substring(image_data from 1 for 8)<>decode('89504e470d0a1a0a','hex') or
       substring(image_data from 13 for 12)<>decode('49484452000000c0000000c0','hex') then raise exception 'INVALID_PHOTO'; end if;
    insert into sj_private.player_photos(owner_id,thumbnail) values(uid,image_data)
      on conflict(owner_id) do update set photo_id=gen_random_uuid(),thumbnail=excluded.thumbnail returning photo_id into photo;
    update public.profiles set avatar_url='photo:'||photo where id=uid;
  elsif portrait in ('initials','preset:curie','preset:einstein','preset:raman','preset:explorer') then
    update public.profiles set avatar_url=nullif(portrait,'initials') where id=uid;
  else raise exception 'INVALID_PORTRAIT';
  end if;
end $$;
create function public.get_player_photo(photo_id uuid, match_id uuid default null)
returns text language sql stable security definer set search_path='' as $$
 select replace(encode(f.thumbnail,'base64'),chr(10),'') from sj_private.player_photos f
 where f.photo_id=get_player_photo.photo_id and (f.owner_id=auth.uid() or exists (
 select 1 from public.matches m where m.id=get_player_photo.match_id and auth.uid() in (m.player1_id,m.player2_id)
 and f.owner_id in (m.player1_id,m.player2_id) and m.status in ('pending','in_progress')))
$$;
-- Replacing a gallery picture or anonymising the account removes its old bytes.
create function sj_private.clear_player_photo() returns trigger language plpgsql security definer set search_path='' as $$
begin
 delete from sj_private.player_photos where owner_id=new.id and 'photo:'||photo_id is distinct from new.avatar_url;
 return new;
end $$;
create trigger clear_player_photo after update of avatar_url on public.profiles
for each row when (old.avatar_url is distinct from new.avatar_url) execute function sj_private.clear_player_photo();
revoke all on function public.get_player_photo(uuid,uuid), public.save_profile_portrait(text,text,text,text), sj_private.clear_player_photo() from public,anon,authenticated;
grant execute on function public.get_player_photo(uuid,uuid), public.save_profile_portrait(text,text,text,text) to authenticated;

create or replace function public.get_match_state(match_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); m public.matches; mq public.match_questions;
begin
 select * into m from public.matches where id=match_id and (player1_id=uid or player2_id=uid);
 if not found then raise exception 'MATCH_NOT_FOUND' using errcode='42501'; end if;
 update public.match_players set heartbeat_at=now() where match_players.match_id=get_match_state.match_id and user_id=uid;
 select * into mq from public.match_questions where match_questions.match_id=get_match_state.match_id and question_index=m.current_question_index;
 return jsonb_build_object('match_id',m.id,'status',m.status,'phase',m.phase,'mode',m.mode,'question_index',m.current_question_index,
 'question_count',(select count(*) from public.match_questions q where q.match_id=m.id),'server_now',clock_timestamp(),'starts_at',m.started_at,
 'label_bots',coalesce((select value from public.app_settings where key='label_bots'),'true'::jsonb),
 'players',(select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'avatar_url',case when p.avatar_url like 'preset:%' or p.avatar_url like 'photo:%' then p.avatar_url end,'rating',mp.rating_before,'score',coalesce((select sum(points) from public.match_answers a join public.match_questions q on q.match_id=a.match_id and q.question_index=a.question_index where a.match_id=m.id and a.user_id=p.id and q.revealed_at is not null),0),
 'rating_after',mp.rating_after,'xp_gained',mp.xp_gained,'result',mp.result,'connected',p.is_bot or mp.heartbeat_at>now()-interval '5 seconds')) from public.match_players mp join public.profiles p on p.id=mp.user_id where mp.match_id=m.id),
 'question',case when mq.started_at is null then null else sj_private.safe_question(mq.snapshot)||jsonb_build_object('started_at',mq.started_at,'deadline_at',mq.deadline_at) end,
 'answered',(select coalesce(jsonb_agg(a.user_id),'[]') from public.match_answers a where a.match_id=m.id and a.question_index=m.current_question_index),
 'result',case when mq.revealed_at is not null then jsonb_build_object('correct_option_id',mq.snapshot->>'correct_option_id','explanation',mq.snapshot->>'explanation',
 'answers',(select coalesce(jsonb_agg(jsonb_build_object('user_id',a.user_id,'option_id',a.option_id,'points',a.points)),'[]') from public.match_answers a where a.match_id=m.id and a.question_index=m.current_question_index)) else null end);
end $$;
