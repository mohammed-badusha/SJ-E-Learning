alter table public.profiles add column deleted_at timestamptz;
alter table public.profiles drop constraint profiles_check;
alter table public.profiles add constraint profile_identity check (
 (is_bot and auth_user_id is null) or (not is_bot and auth_user_id is not null and auth_user_id=id)
 or (deleted_at is not null and auth_user_id is null and phone is null and email is null and not profile_completed)
);
create function public.anonymize_account(user_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare original_email text; m record;
begin
 select email into original_email from public.profiles where id=user_id for update;
 if not found then return; end if;
 for m in select id from public.matches where status in ('pending','in_progress') and (player1_id=user_id or player2_id=user_id)
 loop perform sj_private.finalize_match(m.id,null,true); end loop;
 delete from public.matchmaking_queue where matchmaking_queue.user_id=anonymize_account.user_id;
 delete from public.admin_users where admin_users.user_id=anonymize_account.user_id or email=original_email;
 delete from public.daily_attempts where daily_attempts.user_id=anonymize_account.user_id;
 delete from public.practice_attempts where practice_attempts.user_id=anonymize_account.user_id;
 delete from public.user_category_stats where user_category_stats.user_id=anonymize_account.user_id;
 delete from public.user_badges where user_badges.user_id=anonymize_account.user_id;
 update public.question_reports set user_id=null,note=null where question_reports.user_id=anonymize_account.user_id;
 update public.audit_logs set admin_id=null where admin_id=user_id;
 update public.audit_logs set entity_id='deleted',diff=null where (entity='profiles' and entity_id=user_id::text) or (entity='admin_users' and entity_id=original_email);
 update public.profiles set auth_user_id=null,full_name='Deleted learner',phone=null,email=null,username=null,avatar_url=null,target_exam=null,
 fcm_token=null,notifications_enabled=false,profile_completed=false,deleted_at=now() where id=user_id;
end $$;
revoke all on function public.anonymize_account(uuid) from public,anon,authenticated;
grant execute on function public.anonymize_account(uuid) to service_role;
