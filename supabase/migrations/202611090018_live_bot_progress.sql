begin;
-- Bot answers use the same private progress signal as human answers.
-- Payload deliberately contains no option ID, correctness or points.
create function sj_private.notify_bot_answer() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.profiles where id=new.user_id and is_bot) then
  perform sj_private.emit(new.match_id,'opponent_answered',jsonb_build_object('user_id',new.user_id,'question_index',new.question_index));
 end if;
 return null;
end $$;
create trigger bot_answered after insert on public.match_answers for each row execute function sj_private.notify_bot_answer();
create function sj_private.erase_preferences() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.deleted_at is not null and old.deleted_at is null then delete from public.user_preferences where user_id=new.id; end if;
 return null;
end $$;
create trigger erased_preferences after update of deleted_at on public.profiles for each row execute function sj_private.erase_preferences();
revoke all on function sj_private.notify_bot_answer(),sj_private.erase_preferences() from public,anon,authenticated;
commit;
