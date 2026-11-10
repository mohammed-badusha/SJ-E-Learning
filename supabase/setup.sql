-- SJ E-Learning: first installation only. Run in your NEW Supabase project's SQL Editor.
-- Includes sample educational content. No service-role key is embedded.
begin;
do $$ begin
 if to_regclass('public.profiles') is not null or exists(select 1 from pg_namespace where nspname='sj_private') then
  raise exception 'SJ schema already exists. Apply only new migrations via CLI; do not rerun initial setup.';
 end if;
end $$;


-- 202611080001_foundation.sql
-- SJ E-Learning. Default-deny tables; student clients use narrow RPCs.
create schema if not exists sj_private;
revoke all on schema sj_private from public;
create table public.profiles (
 id uuid primary key default gen_random_uuid(), auth_user_id uuid unique references auth.users(id) on delete cascade,
 full_name text not null default '', phone text unique check(phone ~ '^\+91[6-9][0-9]{9}$'),
 email text, profile_completed boolean not null default false, username text unique,
 avatar_url text, target_exam text, rating int not null default 1000 check(rating>=0), xp int not null default 0,
 level int not null default 1, current_streak int not null default 0, best_streak int not null default 0,
 last_daily_date date, streak_freezes int not null default 1, freeze_week date,
 is_bot boolean not null default false, is_banned boolean not null default false, fcm_token text,
 notifications_enabled boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check ((is_bot and auth_user_id is null) or (not is_bot and auth_user_id is not null and auth_user_id = id)),
 check (not profile_completed or (length(trim(full_name)) between 2 and 50 and (phone is not null or is_bot)))
);
create table public.admin_users (
 id uuid primary key default gen_random_uuid(), email text not null unique check(email=lower(trim(email))),
 user_id uuid references public.profiles(id) on delete set null,
 role text not null check(role in ('super_admin','editor','viewer')), is_active boolean not null default true,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.categories (
 id uuid primary key default gen_random_uuid(), name text not null, slug text not null unique,
 icon text not null default 'public', color_hex text not null default '#5B4CFF' check(color_hex ~ '^#[0-9a-fA-F]{6}$'),
 sort_order int not null default 0, is_active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.subtopics (
 id uuid primary key default gen_random_uuid(), category_id uuid not null references public.categories(id), name text not null,
 sort_order int not null default 0, is_active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(category_id,name), unique(id,category_id)
);
create table public.questions (
 id uuid primary key default gen_random_uuid(), category_id uuid not null references public.categories(id),
 subtopic_id uuid, question_text text not null check(length(trim(question_text))>3), image_url text,
 difficulty text not null default 'medium' check(difficulty in ('easy','medium','hard')),
 time_limit_seconds int not null default 15 check(time_limit_seconds between 5 and 120), explanation text not null,
 status text not null default 'draft' check(status in ('draft','published','archived')),
 times_shown int not null default 0, times_correct int not null default 0, created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 foreign key(subtopic_id,category_id) references public.subtopics(id,category_id)
);
create table public.question_options (
 id uuid primary key default gen_random_uuid(), question_id uuid not null references public.questions(id) on delete cascade,
 option_text text not null, image_url text, is_correct boolean not null default false, sort_order int not null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(question_id,sort_order)
);
create table public.app_settings (key text primary key, value jsonb not null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.matchmaking_queue (
 user_id uuid primary key references public.profiles(id) on delete cascade, category_id uuid references public.categories(id), subtopic_id uuid,
 rating int not null, joined_at timestamptz not null default now(), foreign key(subtopic_id,category_id) references public.subtopics(id,category_id)
);
create table public.matches (
 id uuid primary key default gen_random_uuid(), category_id uuid references public.categories(id), mode text not null check(mode in ('live','bot')),
 status text not null default 'pending' check(status in ('pending','in_progress','completed','abandoned')),
 player1_id uuid not null references public.profiles(id), player2_id uuid not null references public.profiles(id),
 winner_id uuid references public.profiles(id), current_question_index int not null default 0,
 phase text not null default 'countdown', next_tick_at timestamptz not null default now(),
 started_at timestamptz, ended_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(player1_id<>player2_id)
);
create table public.match_questions (
 id uuid primary key default gen_random_uuid(), match_id uuid not null references public.matches(id) on delete cascade,
 question_index int not null, question_id uuid references public.questions(id), snapshot jsonb not null,
 option_order jsonb not null, started_at timestamptz, deadline_at timestamptz, revealed_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(match_id,question_index)
);
create table public.match_players (
 id uuid primary key default gen_random_uuid(), match_id uuid not null references public.matches(id) on delete cascade,
 user_id uuid not null references public.profiles(id), score int not null default 0, rating_before int not null, rating_after int,
 xp_gained int not null default 0, result text check(result in ('win','loss','draw')), heartbeat_at timestamptz not null default now(),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(match_id,user_id)
);
create table public.match_answers (
 id uuid primary key default gen_random_uuid(), match_id uuid not null, question_index int not null,
 user_id uuid not null references public.profiles(id), option_id uuid, is_correct boolean not null, response_ms int not null,
 points int not null, answered_at timestamptz not null default now(),
 foreign key(match_id,question_index) references public.match_questions(match_id,question_index), unique(match_id,question_index,user_id)
);
create table public.bot_plans (
 id uuid primary key default gen_random_uuid(), match_id uuid not null references public.matches(id), question_index int not null,
 will_be_correct boolean not null, response_ms int not null, unique(match_id,question_index)
);
create table public.daily_challenges (
 id uuid primary key default gen_random_uuid(), challenge_date date not null unique, title text not null default 'Your daily ten',
 status text not null default 'scheduled' check(status in ('draft','scheduled','published')), created_by uuid references public.profiles(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.daily_challenge_questions (
 id uuid primary key default gen_random_uuid(), challenge_id uuid not null references public.daily_challenges(id) on delete cascade,
 question_index int not null, question_id uuid references public.questions(id), snapshot jsonb not null, unique(challenge_id,question_index)
);
create table public.daily_attempts (
 id uuid primary key default gen_random_uuid(), challenge_id uuid not null references public.daily_challenges(id),
 user_id uuid not null references public.profiles(id) on delete cascade, score int not null default 0, correct_count int not null default 0,
 total_time_ms int not null default 0, started_at timestamptz not null default now(), completed_at timestamptz,
 unique(challenge_id,user_id)
);
create table public.daily_attempt_answers (
 id uuid primary key default gen_random_uuid(), attempt_id uuid not null references public.daily_attempts(id) on delete cascade,
 question_index int not null, option_id uuid, is_correct boolean not null, response_ms int not null, points int not null, unique(attempt_id,question_index)
);
create table public.practice_attempts (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 timed boolean not null, score int not null default 0, correct_count int not null default 0, questions jsonb not null,
 current_index int not null default 0, current_started_at timestamptz not null default now(),
 answers jsonb not null default '[]', started_at timestamptz not null default now(), completed_at timestamptz
);
create table public.user_category_stats (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 category_id uuid not null references public.categories(id), played int not null default 0, correct int not null default 0,
 total_time_ms bigint not null default 0, unique(user_id,category_id)
);
create table public.badges (id uuid primary key default gen_random_uuid(), slug text not null unique, name text not null, milestone int not null);
create table public.user_badges (id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 badge_id uuid not null references public.badges(id), created_at timestamptz not null default now(), unique(user_id,badge_id));
create table public.question_reports (
 id uuid primary key default gen_random_uuid(), question_id uuid not null references public.questions(id),
 user_id uuid references public.profiles(id) on delete set null, reason text not null, note text,
 status text not null default 'open' check(status in ('open','resolved','dismissed')), resolved_by uuid references public.profiles(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.audit_logs (id uuid primary key default gen_random_uuid(), admin_id uuid references public.profiles(id) on delete set null,
 action text not null, entity text not null, entity_id text, diff jsonb, created_at timestamptz not null default now());
create table sj_private.rate_limits (user_id uuid not null, action text not null, window_at timestamptz not null default now(),
 count int not null default 1, primary key(user_id,action));

create index questions_selection on public.questions(category_id,status,difficulty);
create index questions_subtopic on public.questions(subtopic_id,status);
create index queue_matching on public.matchmaking_queue(category_id,rating,joined_at);
create index queue_age on public.matchmaking_queue(joined_at);
create index matches_player1 on public.matches(player1_id,status);
create index matches_player2 on public.matches(player2_id,status);
create index matches_tick on public.matches(next_tick_at) where status in ('pending','in_progress');
create index answers_match on public.match_answers(match_id);
create index players_user on public.match_players(user_id,created_at desc);
create index daily_attempts_ranking on public.daily_attempts(challenge_id,score desc,total_time_ms);
create index daily_attempts_user on public.daily_attempts(user_id);
create index practice_user on public.practice_attempts(user_id,started_at desc);
create index reports_status on public.question_reports(status,question_id);
create index options_question on public.question_options(question_id);
create index admin_active_email on public.admin_users(email) where is_active;
create index stats_category on public.user_category_stats(category_id);
create index daily_questions_question on public.daily_challenge_questions(question_id);
create index match_questions_question on public.match_questions(question_id);

create function sj_private.touch_updated_at() returns trigger language plpgsql set search_path='' as $$
begin new.updated_at=now(); return new; end $$;
do $$ declare t text; begin
 for t in select table_name from information_schema.columns where table_schema='public' and column_name='updated_at' and table_name=any(array['profiles','admin_users','categories','subtopics','questions','question_options','app_settings','matchmaking_queue','matches','match_questions','match_players','match_answers','bot_plans','daily_challenges','daily_challenge_questions','daily_attempts','daily_attempt_answers','practice_attempts','user_category_stats','badges','user_badges','question_reports','audit_logs']) loop
  execute format('create trigger touch_updated before update on public.%I for each row execute function sj_private.touch_updated_at()',t);
 end loop;
 foreach t in array array['profiles','admin_users','categories','subtopics','questions','question_options','app_settings','matchmaking_queue','matches','match_questions','match_players','match_answers','bot_plans','daily_challenges','daily_challenge_questions','daily_attempts','daily_attempt_answers','practice_attempts','user_category_stats','badges','user_badges','question_reports','audit_logs'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon, authenticated',t);
 end loop;
end $$;

create function sj_private.new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,auth_user_id,full_name,email,avatar_url)
 values(new.id,new.id,left(coalesce(new.raw_user_meta_data->>'full_name',''),50),lower(new.email),new.raw_user_meta_data->>'avatar_url');
 return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function sj_private.new_user();

create function public.get_my_role() returns text language plpgsql security definer set search_path='' as $$
declare result text;
begin
 -- Trust the verified server-side identity, never user-editable metadata or a submitted email.
 select a.role into result from public.admin_users a join auth.users u on lower(u.email)=a.email
 where u.id=auth.uid() and u.email_confirmed_at is not null and u.raw_app_meta_data->>'provider'='google'
 and a.is_active and not exists(select 1 from public.profiles p where p.id=u.id and p.is_banned);
 if result is not null then update public.admin_users set user_id=auth.uid() where email=(select lower(email) from auth.users where id=auth.uid()); end if;
 return coalesce(result,'student');
end $$;
create function public.is_admin(min_role text default 'viewer') returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.admin_users a join auth.users u on lower(u.email)=a.email
 join public.profiles p on p.id=u.id
 where u.id=auth.uid() and u.email_confirmed_at is not null and u.raw_app_meta_data->>'provider'='google'
 and a.is_active and not p.is_banned and p.profile_completed and
 case min_role when 'super_admin' then a.role='super_admin' when 'editor' then a.role in ('editor','super_admin') when 'viewer' then true else false end)
$$;
create function sj_private.require_player() returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid();
begin
 if uid is null or not exists(select 1 from public.profiles where id=uid and profile_completed and not is_banned and not is_bot)
 then raise exception 'PROFILE_REQUIRED' using errcode='42501'; end if;
 return uid;
end $$;
create function sj_private.rate_limit(action text, maximum int, period_seconds int default 60) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); hit int;
begin
 insert into sj_private.rate_limits as r(user_id,action) values(uid,action)
 on conflict on constraint rate_limits_pkey do update set count=case when r.window_at<now()-make_interval(secs=>period_seconds) then 1 else r.count+1 end,
 window_at=case when r.window_at<now()-make_interval(secs=>period_seconds) then now() else r.window_at end returning count into hit;
 if hit>maximum then raise exception 'RATE_LIMITED'; end if;
end $$;
create function public.complete_profile(full_name text, phone text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'SIGN_IN_REQUIRED' using errcode='42501'; end if;
 if length(trim(full_name)) not between 2 and 50 then raise exception 'INVALID_NAME'; end if;
 if phone is null or phone !~ '^\+91[6-9][0-9]{9}$' then raise exception 'INVALID_PHONE'; end if;
 if exists(select 1 from public.profiles where id=auth.uid() and is_banned) then raise exception 'ACCOUNT_SUSPENDED'; end if;
 update public.profiles p set full_name=trim(complete_profile.full_name),phone=complete_profile.phone,profile_completed=true where id=auth.uid();
 if not found then raise exception 'PROFILE_NOT_FOUND'; end if;
 exception when unique_violation then raise exception 'PHONE_IN_USE' using errcode='23505';
end $$;

create policy own_profile on public.profiles for select to authenticated using(id=auth.uid());
grant select(id,full_name,phone,avatar_url,profile_completed,rating,xp,level,current_streak,best_streak,target_exam,is_banned) on public.profiles to authenticated;
create policy visible_categories on public.categories for select to authenticated using (is_active or public.is_admin());
create policy visible_subtopics on public.subtopics for select to authenticated using (is_active or public.is_admin());
grant select on public.categories,public.subtopics to authenticated;

create function sj_private.option_integrity() returns trigger language plpgsql security definer set search_path='' as $$
declare qid uuid; n int; correct int;
begin
 qid=case when TG_OP='DELETE' then old.question_id else new.question_id end;
 if not exists(select 1 from public.questions where id=qid) then return null; end if;
 select count(*),count(*) filter(where is_correct) into n,correct from public.question_options where question_id=qid;
 if n not between 2 and 6 or correct<>1 then raise exception 'QUESTION_NEEDS_2_TO_6_OPTIONS_AND_ONE_CORRECT'; end if;
 return null;
end $$;
create constraint trigger option_integrity after insert or update or delete on public.question_options
 deferrable initially deferred for each row execute function sj_private.option_integrity();
create function sj_private.published_integrity() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='published' and (select count(*) from public.question_options where question_id=new.id) not between 2 and 6
 then raise exception 'QUESTION_NEEDS_OPTIONS'; end if; return null;
end $$;
create constraint trigger published_integrity after insert or update on public.questions deferrable initially deferred
 for each row execute function sj_private.published_integrity();

create function sj_private.question_snapshot(qid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',q.id,'category_id',q.category_id,'question_text',q.question_text,'image_url',q.image_url,
 'explanation',q.explanation,'difficulty',q.difficulty,'time_limit_seconds',q.time_limit_seconds,
 'options',(select jsonb_agg(jsonb_build_object('id',o.id,'option_text',o.option_text,'image_url',o.image_url) order by random()) from public.question_options o where o.question_id=q.id),
 'correct_option_id',(select id from public.question_options where question_id=q.id and is_correct))
 from public.questions q where q.id=qid
$$;
create function sj_private.safe_question(snapshot jsonb) returns jsonb language sql immutable set search_path='' as $$
 select snapshot-'correct_option_id'-'explanation'
$$;
create function sj_private.score(correct boolean, elapsed_ms int, duration_seconds int, final_round boolean default false) returns int language sql immutable set search_path='' as $$
 select case when correct then (10+floor(10*greatest(0,least(1,1-elapsed_ms::numeric/(duration_seconds*1000))))::int)*case when final_round then 2 else 1 end else 0 end
$$;
create function public.get_app_settings() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_object_agg(key,value),'{}') from public.app_settings
 where key in ('search_timeout_seconds','questions_per_match','label_bots','maintenance_mode','min_app_version')
$$;

-- All security-definer RPCs are opt-in. Internal helpers are never executable through PostgREST.
revoke all on all functions in schema sj_private from public,anon,authenticated;
revoke all on function public.get_my_role(),public.is_admin(text),public.complete_profile(text,text),public.get_app_settings() from public,anon,authenticated;
grant execute on function public.get_my_role(),public.is_admin(text),public.complete_profile(text,text),public.get_app_settings() to authenticated;


-- 202611080002_admin_practice.sql
create function sj_private.require_admin(min_role text default 'viewer') returns void language plpgsql security definer set search_path='' as $$
begin if not public.is_admin(min_role) then raise exception 'ADMIN_REQUIRED' using errcode='42501'; end if; end $$;
create function sj_private.audit(action text, entity text, entity_id text, diff jsonb) returns void language sql security definer set search_path='' as $$
 insert into public.audit_logs(admin_id,action,entity,entity_id,diff) values(auth.uid(),action,entity,entity_id,diff)
$$;
create function public.admin_questions(search text default '', category_id uuid default null, page_before timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform sj_private.require_admin();
 select coalesce(jsonb_agg(row),'[]') into result from (
 select q.*, (select jsonb_agg(to_jsonb(o) order by sort_order) from public.question_options o where o.question_id=q.id) options,
 (select c.name from public.categories c where c.id=q.category_id) category_name
 from public.questions q where (admin_questions.category_id is null or q.category_id=admin_questions.category_id)
 and (search='' or q.question_text ilike '%'||search||'%') and (page_before is null or q.created_at<page_before)
 order by q.created_at desc,q.id limit 100) row;
 return jsonb_build_object('questions',result);
end $$;
create function public.admin_save_question(payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare qid uuid=coalesce((payload->>'id')::uuid,gen_random_uuid()); before_data jsonb; opt jsonb; idx int=0; n int;
begin
 perform sj_private.require_admin('editor');
 select to_jsonb(q) into before_data from public.questions q where id=qid for update;
 if exists(select 1 from public.match_questions where question_id=qid) or exists(select 1 from public.daily_challenge_questions where question_id=qid)
 then raise exception 'QUESTION_ALREADY_USED_DUPLICATE_INSTEAD'; end if;
 if jsonb_typeof(payload->'options')<>'array' or jsonb_array_length(payload->'options') not between 2 and 6 then raise exception 'INVALID_OPTIONS'; end if;
 select count(*) filter(where (value->>'is_correct')::boolean),count(distinct lower(trim(value->>'option_text')))
 into idx,n from jsonb_array_elements(payload->'options');
 if idx<>1 or n<>jsonb_array_length(payload->'options') or exists(select 1 from jsonb_array_elements(payload->'options') where length(trim(value->>'option_text'))=0)
 then raise exception 'ONE_CORRECT_AND_UNIQUE_OPTIONS_REQUIRED'; end if;
 insert into public.questions(id,category_id,subtopic_id,question_text,image_url,difficulty,time_limit_seconds,explanation,status,created_by)
 values(qid,(payload->>'category_id')::uuid,(payload->>'subtopic_id')::uuid,trim(payload->>'question_text'),payload->>'image_url',payload->>'difficulty',
 (payload->>'time_limit_seconds')::int,payload->>'explanation',payload->>'status',auth.uid())
 on conflict(id) do update set category_id=excluded.category_id,subtopic_id=excluded.subtopic_id,question_text=excluded.question_text,image_url=excluded.image_url,
 difficulty=excluded.difficulty,time_limit_seconds=excluded.time_limit_seconds,explanation=excluded.explanation,status=excluded.status;
 delete from public.question_options where question_id=qid;
 idx=0;
 for opt in select value from jsonb_array_elements(payload->'options') loop
 insert into public.question_options(question_id,option_text,image_url,is_correct,sort_order)
 values(qid,trim(opt->>'option_text'),opt->>'image_url',(opt->>'is_correct')::boolean,idx); idx=idx+1;
 end loop;
 perform sj_private.audit('save','questions',qid::text,jsonb_build_object('before',before_data,'after',payload));
 return qid;
end $$;
create function public.admin_save_category(payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid=coalesce((payload->>'id')::uuid,gen_random_uuid()); before_data jsonb;
begin
 perform sj_private.require_admin('editor');
 select to_jsonb(c) into before_data from public.categories c where id=cid;
 insert into public.categories(id,name,slug,icon,color_hex,sort_order,is_active)
 values(cid,payload->>'name',payload->>'slug',coalesce(payload->>'icon','public'),coalesce(payload->>'color_hex','#5B4CFF'),
 coalesce((payload->>'sort_order')::int,0),coalesce((payload->>'is_active')::boolean,true))
 on conflict(id) do update set name=excluded.name,slug=excluded.slug,icon=excluded.icon,color_hex=excluded.color_hex,sort_order=excluded.sort_order,is_active=excluded.is_active;
 perform sj_private.audit('save','categories',cid::text,jsonb_build_object('before',before_data,'after',payload)); return cid;
end $$;
create function public.admin_list_users(search text default '') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('users',(select coalesce(jsonb_agg(row),'[]') from (
 select id,full_name,email,phone,rating,level,is_banned,created_at from public.profiles where not is_bot and (search='' or full_name ilike '%'||search||'%' or email ilike '%'||search||'%')
 order by created_at desc limit 100) row),
 'admins',case when public.is_admin('super_admin') then (select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.admin_users a) else '[]'::jsonb end);
end $$;
create function public.admin_set_role(email text, role text, is_active boolean default true) returns void language plpgsql security definer set search_path='' as $$
declare target text=lower(trim(email));
begin
 perform sj_private.require_admin('super_admin');
 -- Serialize role changes to prevent two admins concurrently removing the final super admin.
 perform pg_advisory_xact_lock(hashtext('sj_admin_roles'));
 if role not in ('super_admin','editor','viewer') or target !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'INVALID_ADMIN'; end if;
 if exists(select 1 from public.admin_users a where a.email=target and a.role='super_admin' and a.is_active)
 and (not is_active or role<>'super_admin') and (select count(*) from public.admin_users where admin_users.role='super_admin' and admin_users.is_active)<=1
 then raise exception 'KEEP_ONE_SUPER_ADMIN'; end if;
 insert into public.admin_users(email,role,is_active,created_by) values(target,role,is_active,auth.uid())
 on conflict on constraint admin_users_email_key do update set role=excluded.role,is_active=excluded.is_active;
 perform sj_private.audit('set_role','admin_users',target,jsonb_build_object('role',role,'is_active',is_active));
end $$;
create function public.admin_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('students',(select count(*) from public.profiles where not is_bot),'questions',(select count(*) from public.questions where status='published'),
 'matches',(select count(*) from public.matches where created_at>date_trunc('day',now())),
 'reports',(select count(*) from public.question_reports where status='open'),
 'short_categories',(select coalesce(jsonb_agg(row),'[]') from (select c.name,count(q.id) from public.categories c left join public.questions q on q.category_id=c.id and q.status='published' group by c.id having count(q.id)<10) row));
end $$;

create function public.start_practice(category_id uuid default null, subtopic_id uuid default null, timed boolean default true) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); aid uuid; qs jsonb;
begin
 perform sj_private.rate_limit('practice',15);
 select jsonb_agg(sj_private.question_snapshot(q.id)) into qs from (
 select id from public.questions q where q.status='published' and (start_practice.category_id is null or q.category_id=start_practice.category_id)
 and (start_practice.subtopic_id is null or q.subtopic_id=start_practice.subtopic_id) order by random() limit 10) q;
 if qs is null then raise exception 'NO_PUBLISHED_QUESTIONS'; end if;
 insert into public.practice_attempts(user_id,timed,questions) values(uid,timed,qs) returning id into aid;
 return jsonb_build_object('attempt_id',aid,'question_count',jsonb_array_length(qs),'question_index',0,
 'question',sj_private.safe_question(qs->0)||jsonb_build_object('deadline_at',case when timed then now()+make_interval(secs=>(qs->0->>'time_limit_seconds')::int) else null end));
end $$;
create function public.submit_practice_answer(attempt_id uuid, question_index int, option_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); a public.practice_attempts; q jsonb; response jsonb; correct boolean; elapsed int; points int;
begin
 perform sj_private.rate_limit('answer',120);
 select * into a from public.practice_attempts where id=attempt_id and user_id=uid for update;
 if not found then raise exception 'ATTEMPT_NOT_FOUND' using errcode='42501'; end if;
 if question_index<0 or question_index>=jsonb_array_length(a.questions) then raise exception 'INVALID_INDEX'; end if;
 if question_index<jsonb_array_length(a.answers) then return a.answers->question_index; end if;
 if a.current_index<>question_index or a.completed_at is not null then raise exception 'QUESTION_NOT_ACTIVE'; end if;
 q=a.questions->question_index;
 if option_id is not null and not exists(select 1 from jsonb_array_elements(q->'options') where value->>'id'=option_id::text) then raise exception 'INVALID_OPTION'; end if;
 elapsed=greatest(0,floor(extract(epoch from (clock_timestamp()-a.current_started_at))*1000)::int);
 correct=coalesce(option_id::text=q->>'correct_option_id',false) and (not a.timed or elapsed<=(q->>'time_limit_seconds')::int*1000+500);
 points=sj_private.score(correct,case when a.timed then elapsed else (q->>'time_limit_seconds')::int*1000 end,(q->>'time_limit_seconds')::int,question_index=jsonb_array_length(a.questions)-1);
 response=jsonb_build_object('correct_option_id',q->>'correct_option_id','explanation',q->>'explanation','is_correct',correct,'points',points,'selected_option_id',option_id);
 update public.practice_attempts set answers=answers||jsonb_build_array(response),score=score+points,correct_count=correct_count+correct::int where id=attempt_id;
 return response;
end $$;
create function public.get_practice_question(attempt_id uuid, question_index int) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); a public.practice_attempts; q jsonb;
begin
 select * into a from public.practice_attempts where id=attempt_id and user_id=uid for update;
 if not found or a.completed_at is not null then raise exception 'ATTEMPT_NOT_FOUND'; end if;
 if question_index<0 or question_index>=jsonb_array_length(a.questions) or question_index<>jsonb_array_length(a.answers) then raise exception 'QUESTION_NOT_ACTIVE'; end if;
 if a.current_index<>question_index then update public.practice_attempts set current_index=question_index,current_started_at=now() where id=attempt_id returning * into a; end if;
 q=a.questions->question_index;
 return sj_private.safe_question(q)||jsonb_build_object('deadline_at',case when a.timed then a.current_started_at+make_interval(secs=>(q->>'time_limit_seconds')::int) else null end);
end $$;
create function public.finish_practice(attempt_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); a public.practice_attempts;
begin
 select * into a from public.practice_attempts where id=attempt_id and user_id=uid for update;
 if not found or jsonb_array_length(a.answers)<>jsonb_array_length(a.questions) then raise exception 'ROUND_NOT_COMPLETE'; end if;
 update public.practice_attempts set completed_at=coalesce(completed_at,now()) where id=attempt_id;
 return jsonb_build_object('score',a.score,'correct_count',a.correct_count);
end $$;

revoke all on all functions in schema sj_private from public,anon,authenticated;
revoke all on function public.admin_questions(text,uuid,timestamptz),public.admin_save_question(jsonb),public.admin_save_category(jsonb),
 public.admin_list_users(text),public.admin_set_role(text,text,boolean),public.admin_dashboard(),
 public.start_practice(uuid,uuid,boolean),public.submit_practice_answer(uuid,int,uuid),public.get_practice_question(uuid,int),public.finish_practice(uuid) from public,anon;
grant execute on function public.admin_questions(text,uuid,timestamptz),public.admin_save_question(jsonb),public.admin_save_category(jsonb),
 public.admin_list_users(text),public.admin_set_role(text,text,boolean),public.admin_dashboard(),
 public.start_practice(uuid,uuid,boolean),public.submit_practice_answer(uuid,int,uuid),public.get_practice_question(uuid,int),public.finish_practice(uuid) to authenticated;


-- 202611080003_battles.sql
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


-- 202611080004_daily_progress.sql
create function sj_private.generate_daily(day date) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid; q record; idx int=0;
begin
 perform pg_advisory_xact_lock(hashtext('sj_daily_'||day::text));
 select id into cid from public.daily_challenges where challenge_date=day;
 if cid is not null then return cid; end if;
 if (select count(*) from public.questions where status='published')<10 then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 insert into public.daily_challenges(challenge_date,title,status) values(day,'A little better · '||to_char(day,'DD Mon'),'published') returning id into cid;
 for q in select id from public.questions where status='published' order by row_number() over(partition by category_id,difficulty order by random()),random() limit 10 loop
 insert into public.daily_challenge_questions(challenge_id,question_index,question_id,snapshot) values(cid,idx,q.id,sj_private.question_snapshot(q.id)); idx=idx+1;
 end loop;
 return cid;
end $$;
create function public.get_today_challenge() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); day date=(now() at time zone 'Asia/Kolkata')::date; cid uuid;
begin
 cid=sj_private.generate_daily(day);
 return (select jsonb_build_object('id',c.id,'title',c.title,'challenge_date',c.challenge_date,'question_count',(select count(*) from public.daily_challenge_questions where challenge_id=cid),
 'completed',coalesce(a.completed_at is not null,false),'started',a.id is not null,'score',a.score,'resets_at',(day+1)::timestamp at time zone 'Asia/Kolkata')
 from public.daily_challenges c left join public.daily_attempts a on a.challenge_id=c.id and a.user_id=uid where c.id=cid and c.status in ('published','scheduled'));
end $$;
create function sj_private.daily_question(aid uuid, idx int) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.daily_attempts; q jsonb; start_at timestamptz;
begin
 select * into a from public.daily_attempts where id=aid;
 select snapshot into q from public.daily_challenge_questions where challenge_id=a.challenge_id and question_index=idx;
 if q is null then raise exception 'INVALID_INDEX'; end if;
 select a.started_at+make_interval(secs=>coalesce(sum((snapshot->>'time_limit_seconds')::int),0)::double precision) into start_at
 from public.daily_challenge_questions where challenge_id=a.challenge_id and question_index<idx;
 if now()<start_at then raise exception 'QUESTION_NOT_ACTIVE'; end if;
 return sj_private.safe_question(q)||jsonb_build_object('started_at',start_at,'deadline_at',start_at+make_interval(secs=>(q->>'time_limit_seconds')::int));
end $$;
create function public.start_daily_attempt() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); today jsonb; a public.daily_attempts; idx int=0; n int;
begin
 today=public.get_today_challenge();
 if today is null then raise exception 'CHALLENGE_NOT_AVAILABLE'; end if;
 insert into public.daily_attempts(challenge_id,user_id) values((today->>'id')::uuid,uid) on conflict(challenge_id,user_id) do nothing;
 select * into a from public.daily_attempts where challenge_id=(today->>'id')::uuid and user_id=uid;
 select count(*) into n from public.daily_challenge_questions where challenge_id=a.challenge_id;
 -- Reopening resumes the wall-clock question; it never resets timers or creates another attempt.
 select coalesce(min(question_index),n-1) into idx from (
 select question_index,a.started_at+make_interval(secs=>sum((snapshot->>'time_limit_seconds')::int) over(order by question_index)::double precision) deadline
 from public.daily_challenge_questions where challenge_id=a.challenge_id) q where deadline+interval '500 milliseconds'>now();
 return jsonb_build_object('attempt_id',a.id,'question_count',n,'question_index',idx,'completed',a.completed_at is not null,'score',a.score,'correct_count',a.correct_count,
 'question',case when a.completed_at is null then sj_private.daily_question(a.id,idx) else null end);
end $$;
create function public.get_daily_question(attempt_id uuid, question_index int) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.daily_attempts where id=attempt_id and user_id=sj_private.require_player() and completed_at is null) then raise exception 'ATTEMPT_NOT_FOUND'; end if;
 return sj_private.daily_question(attempt_id,question_index);
end $$;
create function public.submit_daily_answer(attempt_id uuid, question_index int, option_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); a public.daily_attempts; q jsonb; timing jsonb; elapsed int; correct boolean; points int; prior public.daily_attempt_answers; n int;
begin
 perform sj_private.rate_limit('answer',120);
 select * into a from public.daily_attempts where id=attempt_id and user_id=uid for update;
 if not found then raise exception 'ATTEMPT_NOT_FOUND' using errcode='42501'; end if;
 select snapshot into q from public.daily_challenge_questions where challenge_id=a.challenge_id and daily_challenge_questions.question_index=submit_daily_answer.question_index;
 if q is null then raise exception 'INVALID_INDEX'; end if;
 select * into prior from public.daily_attempt_answers where daily_attempt_answers.attempt_id=submit_daily_answer.attempt_id and daily_attempt_answers.question_index=submit_daily_answer.question_index;
 if not found then
 if a.completed_at is not null then raise exception 'ATTEMPT_COMPLETE'; end if;
 timing=sj_private.daily_question(attempt_id,question_index);
 if option_id is not null and not exists(select 1 from jsonb_array_elements(q->'options') where value->>'id'=option_id::text) then raise exception 'INVALID_OPTION'; end if;
 elapsed=greatest(0,floor(extract(epoch from(clock_timestamp()-(timing->>'started_at')::timestamptz))*1000)::int);
 correct=coalesce(option_id::text=q->>'correct_option_id',false) and clock_timestamp()<=(timing->>'deadline_at')::timestamptz+interval '500 milliseconds';
 select count(*) into n from public.daily_challenge_questions where challenge_id=a.challenge_id;
 points=sj_private.score(correct,elapsed,(q->>'time_limit_seconds')::int,question_index=n-1);
 insert into public.daily_attempt_answers(attempt_id,question_index,option_id,is_correct,response_ms,points)
 values(attempt_id,question_index,option_id,correct,least(elapsed,(q->>'time_limit_seconds')::int*1000),points) returning * into prior;
 end if;
 return jsonb_build_object('correct_option_id',q->>'correct_option_id','explanation',q->>'explanation','is_correct',prior.is_correct,'points',prior.points);
end $$;
create function sj_private.finish_daily(aid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.daily_attempts; p public.profiles; total_ms int; day date; streak int; week date; freezes int; answered int; n int;
begin
 select * into a from public.daily_attempts where id=aid for update;
 if not found then raise exception 'ATTEMPT_NOT_FOUND'; end if;
 if a.completed_at is null then
 select sum((snapshot->>'time_limit_seconds')::int)*1000,count(*) into total_ms,n from public.daily_challenge_questions where challenge_id=a.challenge_id;
 select count(*) into answered from public.daily_attempt_answers where attempt_id=aid;
 if answered<n and now()<a.started_at+make_interval(secs=>total_ms::numeric/1000)+interval '500 milliseconds' then raise exception 'ROUND_NOT_COMPLETE'; end if;
 update public.daily_attempts set score=(select coalesce(sum(points),0) from public.daily_attempt_answers where attempt_id=aid),
 correct_count=(select count(*) from public.daily_attempt_answers where attempt_id=aid and is_correct),
 total_time_ms=(select coalesce(sum(coalesce(ans.response_ms,(q.snapshot->>'time_limit_seconds')::int*1000)),0) from public.daily_challenge_questions q left join public.daily_attempt_answers ans on ans.attempt_id=aid and ans.question_index=q.question_index where q.challenge_id=a.challenge_id),
 completed_at=now() where id=aid returning * into a;
 select * into p from public.profiles where id=a.user_id for update;
 select challenge_date into day from public.daily_challenges where id=a.challenge_id;
 week=date_trunc('week',day::timestamp)::date;
 freezes=case when p.freeze_week is distinct from week then 1 else p.streak_freezes end;
 streak=case when p.last_daily_date=day-1 then p.current_streak+1 when p.last_daily_date=day-2 and freezes>0 then p.current_streak+1 else 1 end;
 if p.last_daily_date=day-2 and freezes>0 then freezes=freezes-1; end if;
 if p.last_daily_date is null or p.last_daily_date<day then
 update public.profiles set current_streak=streak,best_streak=greatest(best_streak,streak),last_daily_date=day,streak_freezes=freezes,freeze_week=week,
 xp=xp+30+a.correct_count*5,level=1+(xp+30+a.correct_count*5)/100 where id=a.user_id;
 insert into public.user_badges(user_id,badge_id) select a.user_id,id from public.badges where milestone<=streak on conflict(user_id,badge_id) do nothing;
 end if;
 end if;
 return jsonb_build_object('score',a.score,'correct_count',a.correct_count);
end $$;
create function public.finish_daily_attempt(attempt_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.daily_attempts where id=attempt_id and user_id=sj_private.require_player()) then raise exception 'ATTEMPT_NOT_FOUND'; end if;
 return sj_private.finish_daily(attempt_id);
end $$;
create function public.get_leaderboard(type text default 'all_time', category_id uuid default null, result_limit int default 100) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); rows jsonb;
begin
 if type not in ('all_time','weekly','daily') then raise exception 'INVALID_LEADERBOARD'; end if;
 with ranked as (
 select p.id,p.full_name,p.level,p.rating,
 case when type='daily' then coalesce(d.score,0) when type='weekly' then coalesce(w.points,0) else p.rating end metric,
 rank() over(order by case when type='daily' then coalesce(d.score,0) when type='weekly' then coalesce(w.points,0) else p.rating end desc,coalesce(d.total_time_ms,0)) rank
 from public.profiles p
 left join public.daily_attempts d on d.user_id=p.id and d.completed_at is not null and d.challenge_id=(select id from public.daily_challenges where challenge_date=(now() at time zone 'Asia/Kolkata')::date)
 left join lateral(select sum(mp.score) points from public.match_players mp join public.matches m on m.id=mp.match_id where mp.user_id=p.id and m.status='completed'
 and (get_leaderboard.category_id is null or m.category_id=get_leaderboard.category_id)
 and m.ended_at>=date_trunc('week',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata') w on true
 where p.profile_completed and not p.is_bot and not p.is_banned and (type<>'daily' or d.id is not null)
 ) select coalesce(jsonb_agg(to_jsonb(r) order by rank),'[]') into rows from ranked r where rank<=least(greatest(result_limit,1),100) or id=uid;
 return jsonb_build_object('rows',rows);
end $$;
create function public.get_my_history() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player();
begin return jsonb_build_object('matches',(select coalesce(jsonb_agg(row),'[]') from (
 select m.id,m.mode,m.ended_at,mp.score,mp.result,mp.rating_after-mp.rating_before rating_change,
 (select full_name from public.profiles where id=case when m.player1_id=uid then m.player2_id else m.player1_id end) opponent
 from public.match_players mp join public.matches m on m.id=mp.match_id where mp.user_id=uid and m.status='completed' order by m.ended_at desc limit 50) row)); end $$;
create function public.get_my_stats() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player();
begin return jsonb_build_object('matches',(select count(*) from public.match_players where user_id=uid and result is not null),
 'wins',(select count(*) from public.match_players where user_id=uid and result='win'),
 'categories',(select coalesce(jsonb_agg(jsonb_build_object('name',c.name,'played',s.played,'correct',s.correct)),'[]') from public.user_category_stats s join public.categories c on c.id=s.category_id where user_id=uid),
 'badges',(select coalesce(jsonb_agg(to_jsonb(b)),'[]') from public.user_badges ub join public.badges b on b.id=ub.badge_id where ub.user_id=uid)); end $$;
create function public.report_question(question_id uuid, reason text, note text default '') returns void language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player();
begin
 perform sj_private.rate_limit('report',10);
 if length(reason) not between 3 and 100 or length(note)>1000 then raise exception 'INVALID_REPORT'; end if;
 insert into public.question_reports(question_id,user_id,reason,note) values(question_id,uid,reason,note);
end $$;
create function public.admin_save_setting(key text,value jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin('super_admin');
 if key='questions_per_match' then if (value#>>'{}')::int not between 5 and 20 then raise exception 'INVALID_SETTING'; end if;
 elsif key='search_timeout_seconds' then if (value#>>'{}')::int not between 5 and 60 then raise exception 'INVALID_SETTING'; end if;
 elsif key in ('label_bots','maintenance_mode') then if jsonb_typeof(value)<>'boolean' then raise exception 'INVALID_SETTING'; end if;
 elsif key='min_app_version' then if jsonb_typeof(value)<>'string' then raise exception 'INVALID_SETTING'; end if;
 else raise exception 'INVALID_SETTING'; end if;
 insert into public.app_settings as s(key,value) values(key,value) on conflict on constraint app_settings_pkey do update set value=excluded.value;
 perform sj_private.audit('setting','app_settings',key,value);
end $$;
create function public.admin_set_user(user_id uuid,is_banned boolean,reset_streak boolean default false) returns void language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin('super_admin');
 if user_id=auth.uid() then raise exception 'CANNOT_BAN_SELF'; end if;
 update public.profiles p set is_banned=admin_set_user.is_banned,current_streak=case when reset_streak then 0 else current_streak end where id=user_id and not is_bot;
 delete from public.matchmaking_queue where matchmaking_queue.user_id=admin_set_user.user_id;
 perform sj_private.audit('update','profiles',user_id::text,jsonb_build_object('is_banned',is_banned,'reset_streak',reset_streak));
end $$;
create function public.admin_reports() returns jsonb language plpgsql security definer set search_path='' as $$
begin perform sj_private.require_admin(); return jsonb_build_object('reports',(select coalesce(jsonb_agg(row),'[]') from (select r.*,q.question_text from public.question_reports r join public.questions q on q.id=r.question_id order by r.created_at desc limit 100) row)); end $$;
create function public.admin_resolve_report(report_id uuid,status text) returns void language plpgsql security definer set search_path='' as $$
begin perform sj_private.require_admin('editor'); if status not in ('resolved','dismissed') then raise exception 'INVALID_STATUS'; end if;
 update public.question_reports set status=admin_resolve_report.status,resolved_by=auth.uid() where id=report_id;
 perform sj_private.audit('resolve','question_reports',report_id::text,jsonb_build_object('status',status)); end $$;
create function sj_private.daily_maintenance() returns void language plpgsql security definer set search_path='' as $$
declare a record;
begin
 perform sj_private.generate_daily((now() at time zone 'Asia/Kolkata')::date+1);
 for a in select d.id from public.daily_attempts d where d.completed_at is null and now()>d.started_at+
 make_interval(secs=>(select sum((snapshot->>'time_limit_seconds')::int) from public.daily_challenge_questions where challenge_id=d.challenge_id)::double precision)+interval '1 second'
 loop perform sj_private.finish_daily(a.id); end loop;
end $$;

revoke all on all functions in schema sj_private from public,anon,authenticated;
revoke all on function public.get_today_challenge(),public.start_daily_attempt(),public.get_daily_question(uuid,int),public.submit_daily_answer(uuid,int,uuid),
 public.finish_daily_attempt(uuid),public.get_leaderboard(text,uuid,int),public.get_my_history(),public.get_my_stats(),public.report_question(uuid,text,text),
 public.admin_save_setting(text,jsonb),public.admin_set_user(uuid,boolean,boolean),public.admin_reports(),public.admin_resolve_report(uuid,text) from public,anon;
grant execute on function public.get_today_challenge(),public.start_daily_attempt(),public.get_daily_question(uuid,int),public.submit_daily_answer(uuid,int,uuid),
 public.finish_daily_attempt(uuid),public.get_leaderboard(text,uuid,int),public.get_my_history(),public.get_my_stats(),public.report_question(uuid,text,text),
 public.admin_save_setting(text,jsonb),public.admin_set_user(uuid,boolean,boolean),public.admin_reports(),public.admin_resolve_report(uuid,text) to authenticated;


-- 202611080005_scheduler.sql
-- Supabase Cron runs the game even if every client closes. No client owns advancement.
create extension if not exists pg_cron;
select cron.schedule('sj-match-engine','1 second','select sj_private.tick_all()');
select cron.schedule('sj-daily-resume','* * * * *','select sj_private.daily_maintenance()');
-- 23:55 IST = 18:25 UTC. Ensure tomorrow's common challenge exists.
select cron.schedule('sj-daily-generate','25 18 * * *','select sj_private.generate_daily((now() at time zone ''Asia/Kolkata'')::date+1)');


-- 202611080006_operations.sql
create function public.run_match_tick() returns void language sql security definer set search_path='' as $$ select sj_private.tick_all() $$;
revoke all on function public.run_match_tick() from public,anon,authenticated;
grant execute on function public.run_match_tick() to service_role;
-- Stop new rounds during maintenance, while keeping existing matches playable.
create function sj_private.enforce_maintenance() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (select value='true'::jsonb from public.app_settings where key='maintenance_mode') and not public.is_admin('super_admin')
 then raise exception 'MAINTENANCE_MODE'; end if; return new;
end $$;
create trigger maintenance_queue before insert on public.matchmaking_queue for each row execute function sj_private.enforce_maintenance();
create trigger maintenance_practice before insert on public.practice_attempts for each row execute function sj_private.enforce_maintenance();
create trigger maintenance_daily before insert on public.daily_attempts for each row execute function sj_private.enforce_maintenance();
revoke all on all functions in schema sj_private from public,anon,authenticated;


-- 202611080007_admin_content.sql
create function public.admin_save_subtopic(payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare sid uuid=coalesce((payload->>'id')::uuid,gen_random_uuid());
begin
 perform sj_private.require_admin('editor');
 insert into public.subtopics(id,category_id,name,sort_order,is_active) values(sid,(payload->>'category_id')::uuid,trim(payload->>'name'),coalesce((payload->>'sort_order')::int,0),coalesce((payload->>'is_active')::boolean,true))
 on conflict(id) do update set name=excluded.name,sort_order=excluded.sort_order,is_active=excluded.is_active;
 perform sj_private.audit('save','subtopics',sid::text,payload);return sid;
end $$;
create function public.admin_daily_calendar() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('days',(select coalesce(jsonb_agg(row order by day),'[]') from (
 select day::date,c.id,c.title,c.status,(select count(*) from public.daily_attempts where challenge_id=c.id and completed_at is not null) participation
 from generate_series((now() at time zone 'Asia/Kolkata')::date::timestamp,((now() at time zone 'Asia/Kolkata')::date+29)::timestamp,interval '1 day') day
 left join public.daily_challenges c on c.challenge_date=day::date) row));
end $$;
create function public.admin_schedule_daily(day date,title text,question_ids uuid[] default null) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid; qid uuid; idx int=0;
begin
 perform sj_private.require_admin('editor');
 perform pg_advisory_xact_lock(hashtext('sj_daily_'||day::text));
 if day<(now() at time zone 'Asia/Kolkata')::date or day>(now() at time zone 'Asia/Kolkata')::date+365 or length(trim(title)) not between 2 and 100 then raise exception 'INVALID_CHALLENGE'; end if;
 select id into cid from public.daily_challenges where challenge_date=day for update;
 if exists(select 1 from public.daily_attempts where challenge_id=cid) then raise exception 'CHALLENGE_ALREADY_STARTED'; end if;
 if cid is null then cid=sj_private.generate_daily(day); end if;
 if question_ids is not null then
 if cardinality(question_ids) not between 5 and 20 or (select count(distinct id) from public.questions where id=any(question_ids) and status='published')<>cardinality(question_ids) then raise exception 'INVALID_QUESTIONS'; end if;
 delete from public.daily_challenge_questions where challenge_id=cid;
 foreach qid in array question_ids loop
 insert into public.daily_challenge_questions(challenge_id,question_index,question_id,snapshot) values(cid,idx,qid,sj_private.question_snapshot(qid));idx=idx+1;
 end loop;
 end if;
 update public.daily_challenges set title=trim(admin_schedule_daily.title),status='scheduled',created_by=auth.uid() where id=cid;
 perform sj_private.audit('schedule','daily_challenges',cid::text,jsonb_build_object('day',day,'title',title));return cid;
end $$;
create function public.admin_analytics() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('questions',(select coalesce(jsonb_agg(row),'[]') from (
 select q.id,q.question_text,count(a.id) attempts,round(100.0*count(*) filter(where a.is_correct)/nullif(count(a.id),0),1) accuracy,
 round(avg(a.response_ms)) average_ms from public.questions q join public.match_questions mq on mq.question_id=q.id join public.match_answers a on a.match_id=mq.match_id and a.question_index=mq.question_index
 group by q.id order by count(a.id) desc limit 100) row),
 'categories',(select coalesce(jsonb_agg(row),'[]') from (select c.name,count(m.id) matches from public.categories c left join public.matches m on m.category_id=c.id group by c.id) row),
 'hours',(select coalesce(jsonb_agg(row),'[]') from (select extract(hour from created_at at time zone 'Asia/Kolkata') as "hour",count(*) matches from public.matches group by 1 order by 1) row));
end $$;
revoke all on function public.admin_save_subtopic(jsonb),public.admin_daily_calendar(),public.admin_schedule_daily(date,text,uuid[]),public.admin_analytics() from public,anon;
grant execute on function public.admin_save_subtopic(jsonb),public.admin_daily_calendar(),public.admin_schedule_daily(date,text,uuid[]),public.admin_analytics() to authenticated;


-- 202611080008_account_deletion.sql
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


-- 202611080009_battle_reports.sql
-- Backwards-compatible completed-match review, enriched with real comparison stats.
-- Apply this migration only to existing projects; do not rerun setup.sql.

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


-- 202611080010_player_portraits.sql
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


-- 202611080011_report_portraits.sql
-- Share the current player picture with the two participants in a completed battle report.

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


-- 202611080012_daily_and_admin_workspace.sql
-- Apply once to an existing project after migration 011.

-- Old answers have no receipt timestamp and retain their original time windows.
alter table public.daily_attempt_answers add column answered_at timestamptz;
alter table public.daily_attempt_answers alter column answered_at set default clock_timestamp();

create function sj_private.daily_windows(aid uuid)
returns table(idx int, opens_at timestamptz, closes_at timestamptz, answered boolean)
language sql stable security definer set search_path='' as $$
 with recursive items as (
   select q.question_index i, make_interval(secs=>(q.snapshot->>'time_limit_seconds')::int) duration,
          a.started_at, r.answered_at, r.id is not null answered
   from public.daily_attempts a join public.daily_challenge_questions q on q.challenge_id=a.challenge_id
   left join public.daily_attempt_answers r on r.attempt_id=a.id and r.question_index=q.question_index
   where a.id=aid
 ), windows as (
   select i,started_at opens,started_at+duration closes,answered_at,answered from items where i=0
   union all
   select n.i,t.opens,t.opens+n.duration,n.answered_at,n.answered from windows w join items n on n.i=w.i+1
   cross join lateral (select greatest(w.opens,least(w.closes,w.answered_at)) opens) t
 ) select i,opens,closes,answered from windows;
$$;
revoke all on function sj_private.daily_windows(uuid) from public,anon,authenticated;
create or replace function sj_private.daily_question(aid uuid, idx int) returns jsonb language plpgsql security definer set search_path='' as $$
declare window_row record; question jsonb;
begin
 select * into window_row from sj_private.daily_windows(aid) w where w.idx=daily_question.idx;
 if not found then raise exception 'INVALID_INDEX'; end if;
 if clock_timestamp()<window_row.opens_at then raise exception 'QUESTION_NOT_ACTIVE'; end if;
 select q.snapshot into question from public.daily_attempts a join public.daily_challenge_questions q on q.challenge_id=a.challenge_id
 where a.id=aid and q.question_index=idx;
 return sj_private.safe_question(question)||jsonb_build_object('started_at',window_row.opens_at,'deadline_at',window_row.closes_at);
end $$;
create or replace function sj_private.finish_daily(aid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.daily_attempts; p public.profiles; total_ms int; day date; streak int; week date; freezes int; answered int; n int;
begin
 select * into a from public.daily_attempts where id=aid for update;
 if not found then raise exception 'ATTEMPT_NOT_FOUND'; end if;
 if a.completed_at is null then
 select sum((snapshot->>'time_limit_seconds')::int)*1000,count(*) into total_ms,n from public.daily_challenge_questions where challenge_id=a.challenge_id;
 select count(*) into answered from public.daily_attempt_answers where attempt_id=aid;
 if answered<n and clock_timestamp()<(select max(closes_at) from sj_private.daily_windows(aid))+interval '500 milliseconds' then raise exception 'ROUND_NOT_COMPLETE'; end if;
 update public.daily_attempts set score=(select coalesce(sum(points),0) from public.daily_attempt_answers where attempt_id=aid),
 correct_count=(select count(*) from public.daily_attempt_answers where attempt_id=aid and is_correct),
 total_time_ms=(select coalesce(sum(coalesce(ans.response_ms,(q.snapshot->>'time_limit_seconds')::int*1000)),0) from public.daily_challenge_questions q left join public.daily_attempt_answers ans on ans.attempt_id=aid and ans.question_index=q.question_index where q.challenge_id=a.challenge_id),
 completed_at=now() where id=aid returning * into a;
 select * into p from public.profiles where id=a.user_id for update;
 select challenge_date into day from public.daily_challenges where id=a.challenge_id;
 week=date_trunc('week',day::timestamp)::date;
 freezes=case when p.freeze_week is distinct from week then 1 else p.streak_freezes end;
 streak=case when p.last_daily_date=day-1 then p.current_streak+1 when p.last_daily_date=day-2 and freezes>0 then p.current_streak+1 else 1 end;
 if p.last_daily_date=day-2 and freezes>0 then freezes=freezes-1; end if;
 if p.last_daily_date is null or p.last_daily_date<day then
 update public.profiles set current_streak=streak,best_streak=greatest(best_streak,streak),last_daily_date=day,streak_freezes=freezes,freeze_week=week,
 xp=xp+30+a.correct_count*5,level=1+(xp+30+a.correct_count*5)/100 where id=a.user_id;
 insert into public.user_badges(user_id,badge_id) select a.user_id,id from public.badges where milestone<=streak on conflict(user_id,badge_id) do nothing;
 end if;
 end if;
 return jsonb_build_object('score',a.score,'correct_count',a.correct_count);
end $$;
create or replace function public.start_daily_attempt() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); today jsonb; a public.daily_attempts; idx int=0; n int;
begin
 today=public.get_today_challenge();
 if today is null then raise exception 'CHALLENGE_NOT_AVAILABLE'; end if;
 insert into public.daily_attempts(challenge_id,user_id) values((today->>'id')::uuid,uid) on conflict(challenge_id,user_id) do nothing;
 select * into a from public.daily_attempts where challenge_id=(today->>'id')::uuid and user_id=uid for update;
 select count(*) into n from public.daily_challenge_questions where challenge_id=a.challenge_id;
 if a.completed_at is null then
   select min(w.idx) into idx from sj_private.daily_windows(a.id) w
   where not w.answered and w.closes_at+interval '500 milliseconds'>clock_timestamp();
   if idx is null then
     perform sj_private.finish_daily(a.id);
     select * into a from public.daily_attempts where id=a.id;
   end if;
 end if;
 return jsonb_build_object('attempt_id',a.id,'question_count',n,'question_index',idx,'completed',a.completed_at is not null,'score',a.score,'correct_count',a.correct_count,
 'question',case when a.completed_at is null then sj_private.daily_question(a.id,idx) else null end);
end $$;
create function public.admin_question_groups(search text default '') returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('categories',(select coalesce(jsonb_agg(g order by g.name),'[]') from (
   select c.id,c.name,count(q.id) question_count from public.categories c left join public.questions q
   on q.category_id=c.id and q.question_text ilike '%'||search||'%'
   group by c.id having search='' or count(q.id)>0
 ) g));
end $$;
create function public.admin_question_page(subject_id uuid, search text default '', after_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('rows',(select coalesce(jsonb_agg(r order by r.id),'[]') from (
   select q.*,t.name topic_name,(select jsonb_agg(o order by o.sort_order) from public.question_options o where o.question_id=q.id) options
   from public.questions q left join public.subtopics t on t.id=q.subtopic_id
   where q.category_id=subject_id and q.question_text ilike '%'||search||'%' and (after_id is null or q.id>after_id)
   order by q.id limit 50
 ) r));
end $$;

create function public.admin_user_page(search text default '', after_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('rows',(select coalesce(jsonb_agg(u order by u.id),'[]') from (
   select p.id,p.full_name,p.username,p.email,p.phone,p.target_exam,p.rating,p.xp,p.level,p.current_streak,p.best_streak,
     p.last_daily_date,p.profile_completed,p.is_banned,p.created_at,p.updated_at,
     coalesce((select a.role from public.admin_users a where a.is_active and a.email=p.email),'student') role
   from public.profiles p where not p.is_bot and p.deleted_at is null and (after_id is null or p.id>after_id)
     and (search='' or concat_ws(' ',p.full_name,p.email,p.phone) ilike '%'||search||'%')
   order by p.id limit 100
 ) u));
end $$;
create table sj_private.question_imports (batch_hash text primary key, item_count int not null);
revoke all on sj_private.question_imports from public,anon,authenticated;
create function public.admin_import_questions(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb; row_num int=0; category uuid; topic uuid; topic_name text; choice text; difficulty text; opts jsonb;
 fingerprint text=md5(payload::text); previous int; column_name text;
begin
 perform sj_private.require_admin('editor');
 if jsonb_typeof(payload->'questions') is distinct from 'array' then raise exception 'Expected a questions array'; end if;
 if jsonb_array_length(payload->'questions') not between 1 and 500 then raise exception 'Use 1–500 questions per file'; end if;
 perform pg_advisory_xact_lock(hashtext('sj_question_import'));
 select item_count into previous from sj_private.question_imports where batch_hash=fingerprint;
 if found then return jsonb_build_object('imported',previous,'already_imported',true); end if;
 for item in select value from jsonb_array_elements(payload->'questions') loop
   row_num=row_num+1;
   foreach column_name in array array['question','option_a','option_b','option_c','option_d','correct_answer','subject','difficulty','explanation'] loop
     if jsonb_typeof(item->column_name) is distinct from 'string' or trim(item->>column_name)='' then
       raise exception 'Question %: supply %',row_num,column_name;
     end if;
   end loop;
   choice=upper(trim(item->>'correct_answer')); difficulty=lower(trim(item->>'difficulty'));
   if choice not in ('A','B','C','D') or difficulty not in ('easy','medium','hard') or length(trim(item->>'question'))<4 then
     raise exception 'Question %: check question text, correct_answer (A–D) and difficulty',row_num;
   end if;
   select c.id into category from public.categories c where lower(trim(item->>'subject')) in (lower(c.name),lower(c.slug)) order by c.sort_order,c.id limit 1;
   if category is null then raise exception 'Question %: unknown subject "%". Add the category first',row_num,item->>'subject'; end if;
   topic=null; topic_name=nullif(trim(item->>'topic'),'');
   if topic_name is not null then
     select s.id into topic from public.subtopics s where s.category_id=category and lower(s.name)=lower(topic_name) order by s.id limit 1;
     if topic is null then insert into public.subtopics(category_id,name) values(category,topic_name) on conflict(category_id,name) do update set name=excluded.name returning id into topic; end if;
   end if;
   select jsonb_agg(jsonb_build_object('option_text',trim(item->>('option_'||l)),'is_correct',upper(l)=choice) order by l) into opts from unnest(array['a','b','c','d']) l;
   if (select count(distinct lower(o->>'option_text')) from jsonb_array_elements(opts) o)<>4 then raise exception 'Question %: options must be different',row_num; end if;
   perform public.admin_save_question(jsonb_build_object('category_id',category,'subtopic_id',topic,'question_text',trim(item->>'question'),
      'difficulty',difficulty,'time_limit_seconds',coalesce((item->>'time_limit_seconds')::int,15),'explanation',trim(item->>'explanation'),'status','draft','options',opts));
 end loop;
 insert into sj_private.question_imports values(fingerprint,row_num);
 return jsonb_build_object('imported',row_num,'already_imported',false);
end $$;
revoke all on function public.admin_question_groups(text),public.admin_question_page(uuid,text,uuid),public.admin_user_page(text,uuid),public.admin_import_questions(jsonb) from public,anon;
grant execute on function public.admin_question_groups(text),public.admin_question_page(uuid,text,uuid),public.admin_user_page(text,uuid),public.admin_import_questions(jsonb) to authenticated;


-- 202611080013_finish_resumed_daily.sql
create or replace function sj_private.finish_daily(aid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.daily_attempts; p public.profiles; day date; streak int; week date; freezes int;
begin
 select * into a from public.daily_attempts where id=aid for update;
 if not found then raise exception 'ATTEMPT_NOT_FOUND'; end if;
 if a.completed_at is null then
 -- An answered final question is complete even when earlier questions timed out while the app was closed.
 if exists(select 1 from sj_private.daily_windows(aid) w
   where not w.answered and w.closes_at+interval '500 milliseconds'>clock_timestamp())
 then raise exception 'ROUND_NOT_COMPLETE'; end if;
 update public.daily_attempts set score=(select coalesce(sum(points),0) from public.daily_attempt_answers where attempt_id=aid),
 correct_count=(select count(*) from public.daily_attempt_answers where attempt_id=aid and is_correct),
 total_time_ms=(select coalesce(sum(coalesce(ans.response_ms,(q.snapshot->>'time_limit_seconds')::int*1000)),0) from public.daily_challenge_questions q left join public.daily_attempt_answers ans on ans.attempt_id=aid and ans.question_index=q.question_index where q.challenge_id=a.challenge_id),
 completed_at=now() where id=aid returning * into a;
 select * into p from public.profiles where id=a.user_id for update;
 select challenge_date into day from public.daily_challenges where id=a.challenge_id;
 week=date_trunc('week',day::timestamp)::date;
 freezes=case when p.freeze_week is distinct from week then 1 else p.streak_freezes end;
 streak=case when p.last_daily_date=day-1 then p.current_streak+1 when p.last_daily_date=day-2 and freezes>0 then p.current_streak+1 else 1 end;
 if p.last_daily_date=day-2 and freezes>0 then freezes=freezes-1; end if;
 if p.last_daily_date is null or p.last_daily_date<day then
 update public.profiles set current_streak=streak,best_streak=greatest(best_streak,streak),last_daily_date=day,streak_freezes=freezes,freeze_week=week,
 xp=xp+30+a.correct_count*5,level=1+(xp+30+a.correct_count*5)/100 where id=a.user_id;
 insert into public.user_badges(user_id,badge_id) select a.user_id,id from public.badges where milestone<=streak on conflict(user_id,badge_id) do nothing;
 end if;
 end if;
 return jsonb_build_object('score',a.score,'correct_count',a.correct_count);
end $$;


-- 202611090014_four_round_battles.sql
-- Additive rules v2. Existing snapshots and legacy scoring remain intact.

alter table public.matches add column rules_version int not null default 1;
alter table public.matches add column bot_style text;
alter table public.match_players alter column score type numeric(12,4);
alter table public.match_answers alter column points type numeric(12,4);
alter table public.subtopics add column topic_group text;
alter table public.questions add column exam text;
create index questions_exam_pool on public.questions(exam,category_id,difficulty,id) where status='published';
create index practice_owner_history on public.practice_attempts(user_id,started_at desc,id);
create index daily_owner_history on public.daily_attempts(user_id,started_at desc,id);
insert into public.app_settings(key,value) values ('search_timeout_seconds','10'),('questions_per_match','4'),('daily_question_count','10'),('label_bots','false')
on conflict(key) do update set value=excluded.value;

create table public.battle_rounds (
 round_index int primary key check(round_index between 0 and 3),
 subject_slug text not null unique,
 duration_seconds int not null check(duration_seconds between 5 and 120)
);
insert into public.battle_rounds values (0,'reasoning',40),(1,'general-awareness',15),(2,'quant',40),(3,'english',15);
alter table public.battle_rounds enable row level security;
create policy read_rounds on public.battle_rounds for select to authenticated using(true);
grant select on public.battle_rounds to authenticated;
create table sj_private.bot_names(name text primary key);
insert into sj_private.bot_names select unnest(array[
 'Aarav Sharma','Vivaan Patel','Aditya Nair','Vihaan Singh','Arjun Menon','Sai Kumar','Reyansh Gupta','Ayaan Khan',
 'Krishna Rao','Ishaan Shah','Shaurya Das','Atharv Joshi','Dhruv Reddy','Kabir Verma','Ritvik Iyer','Ansh Jain',
 'Rohan Mishra','Rahul Bose','Karan Mehta','Varun Pillai','Nikhil Bhat','Siddharth Roy','Pranav Sinha','Akash Sen',
 'Abhinav Yadav','Harsh Chauhan','Manish Tiwari','Deepak Pandey','Vikram Sethi','Sanjay Kapoor','Ajay Kulkarni','Vijay Desai',
 'Ravi Prasad','Suresh Naidu','Amit Saxena','Ankit Agarwal','Mohit Bansal','Gaurav Chawla','Piyush Goel','Yash Malhotra',
 'Aadhya Sharma','Ananya Nair','Diya Patel','Saanvi Singh','Myra Menon','Aarohi Shah','Anika Gupta','Isha Rao',
 'Kiara Joshi','Avni Reddy','Riya Das','Navya Jain','Sara Khan','Meera Iyer','Tara Bose','Nitya Verma',
 'Priya Mishra','Sneha Mehta','Pooja Pillai','Kavya Bhat','Neha Roy','Shreya Sinha','Aditi Sen','Swati Yadav',
 'Divya Chauhan','Rashmi Tiwari','Anjali Pandey','Nandini Sethi','Shruti Kapoor','Sakshi Kulkarni','Tanvi Desai','Kriti Prasad',
 'Lakshmi Naidu','Simran Saxena','Ishita Agarwal','Palak Bansal','Ritika Chawla','Vani Goel','Juhi Malhotra','Fathima Ali',
 'Aravind Raj','Keerthana Ravi','Muhammed Faris','Aparna Krishnan','Devika Suresh','Aswin Prakash','Amal Thomas','Anu Mathew'
]);
create function sj_private.battle_score(correct boolean, elapsed_ms int, duration_seconds int) returns numeric
language sql immutable set search_path='' as $$
 select case when correct then round(2 + .5 * greatest(0,least(1,1-elapsed_ms::numeric/(duration_seconds*1000))),4) else 0 end
$$;
create function sj_private.pick_questions(n int, subject uuid default null, topic uuid default null, exam_filter text default null, difficulty_filter text default null)
returns uuid[] language plpgsql security definer set search_path='' as $$
declare picked uuid[];
begin
 if n not between 1 and 100 or (difficulty_filter is not null and difficulty_filter not in ('easy','medium','hard')) then raise exception 'INVALID_FILTER'; end if;
 select array_agg(id) into picked from (
 select q.id from public.questions q join public.categories c on c.id=q.category_id and c.is_active
 where q.status='published' and (subject is null or q.category_id=subject) and (topic is null or q.subtopic_id=topic)
 and (exam_filter is null or q.exam=exam_filter) and (difficulty_filter is null or q.difficulty=difficulty_filter)
 and (select count(*) from public.question_options o where o.question_id=q.id)=4
 order by random() limit n) pool;
 if coalesce(cardinality(picked),0)<>n then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 return picked;
end $$;
create or replace function sj_private.new_match(p1 uuid, p2 uuid, category uuid, topic uuid, mode text) returns uuid
language plpgsql security definer set search_path='' as $$
declare mid uuid; r record; qid uuid; snap jsonb; correct_rounds int[]; target int; style text; delay numeric; short boolean;
begin
 style=(array['Speedster','Analytical','Balanced','Wildcard'])[1+floor(random()*4)::int];
 target=2+floor(random()*3)::int;
 select array_agg(i) into correct_rounds from (select i from generate_series(0,3) i order by random() limit target) t;
 insert into public.matches(category_id,mode,player1_id,player2_id,started_at,next_tick_at,rules_version,bot_style)
 values(null,mode,p1,p2,now()+interval '3 seconds',now()+interval '3 seconds',2,case when mode='bot' then style end) returning id into mid;
 insert into public.match_players(match_id,user_id,rating_before) select mid,id,rating from public.profiles where id in(p1,p2);
 for r in select b.*,c.id category from public.battle_rounds b join public.categories c on c.slug=b.subject_slug and c.is_active order by b.round_index loop
  qid=(sj_private.pick_questions(1,r.category))[1];
  snap=sj_private.question_snapshot(qid)||jsonb_build_object('time_limit_seconds',r.duration_seconds);
  insert into public.match_questions(match_id,question_index,question_id,snapshot,option_order) values(mid,r.round_index,qid,snap,snap->'options');
  if mode='bot' then
   short=r.duration_seconds=15;
   delay=case style when 'Speedster' then case when short then 2+random()*4 else 8+random()*8 end
     when 'Analytical' then case when short then 5+random()*6 else 20+random()*14 end
     when 'Balanced' then case when short then 3+random()*5 else 12+random()*12 end
     else 2+random()*(r.duration_seconds-3) end;
   insert into public.bot_plans(match_id,question_index,will_be_correct,response_ms) values(mid,r.round_index,r.round_index=any(correct_rounds),floor(delay*1000)::int);
  end if;
 end loop;
 if (select count(*) from public.match_questions where match_id=mid)<>4 then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 delete from public.matchmaking_queue where user_id in(p1,p2);
 perform realtime.send(jsonb_build_object('match_id',mid),'match_found','user:'||p1::text,true);
 if mode='live' then perform realtime.send(jsonb_build_object('match_id',mid),'match_found','user:'||p2::text,true); end if;
 return mid;
end $$;
create or replace function public.join_matchmaking(category_id uuid default null, subtopic_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); myrating int; opponent public.matchmaking_queue; mine public.matchmaking_queue; mid uuid;
begin
 perform sj_private.rate_limit('join',30);
 perform 1 from public.profiles where id=uid for update;
 select id into mid from public.matches where (player1_id=uid or player2_id=uid) and status in ('pending','in_progress') limit 1;
 if mid is not null then return jsonb_build_object('match_id',mid); end if;
 -- All new battles share the same four-subject queue.
 if exists(select 1 from public.battle_rounds b left join public.categories c on c.slug=b.subject_slug and c.is_active
 where c.id is null or not exists(select 1 from public.questions q where q.category_id=c.id and q.status='published'
 and (select count(*) from public.question_options o where o.question_id=q.id)=4)) then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 select rating into myrating from public.profiles where id=uid;
 insert into public.matchmaking_queue(user_id,category_id,subtopic_id,rating) values(uid,null,null,myrating)
 on conflict(user_id) do nothing;
 select * into mine from public.matchmaking_queue where user_id=uid for update;
 select * into opponent from public.matchmaking_queue q where q.user_id<>uid and q.category_id is not distinct from mine.category_id
 and (q.subtopic_id is not distinct from mine.subtopic_id or least(q.joined_at,mine.joined_at)<now()-interval '8 seconds')
 and q.joined_at>now()-interval '60 seconds'
 and abs(q.rating-myrating)<=100+100*floor(extract(epoch from(now()-least(q.joined_at,mine.joined_at)))/5)
 order by abs(q.rating-myrating),q.joined_at for update skip locked limit 1;
 if found then mid=sj_private.new_match(uid,opponent.user_id,mine.category_id,case when mine.subtopic_id is not distinct from opponent.subtopic_id then mine.subtopic_id else null end,'live'); end if;
 return jsonb_build_object('match_id',mid,'joined_at',mine.joined_at,'server_now',clock_timestamp(),
 'search_timeout_seconds',coalesce((select value from public.app_settings where key='search_timeout_seconds'),'10'::jsonb));
end $$;
create or replace function public.start_bot_match() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); mine public.matchmaking_queue; bot uuid; mid uuid; timeout int;
begin
 perform 1 from public.profiles where id=uid for update;
 select id into mid from public.matches where (player1_id=uid or player2_id=uid) and status in ('pending','in_progress') limit 1;
 if mid is not null then return jsonb_build_object('match_id',mid); end if;
 select * into mine from public.matchmaking_queue where user_id=uid for update;
 if not found then raise exception 'NOT_QUEUED'; end if;
 timeout=coalesce((select (value#>>'{}')::int from public.app_settings where key='search_timeout_seconds'),10);
 if now()<mine.joined_at+make_interval(secs=>timeout) then raise exception 'SEARCH_NOT_EXPIRED'; end if;
 insert into public.profiles(full_name,is_bot,rating,level,avatar_url)
 select name,true,mine.rating,8+floor(random()*28)::int,'color:'||(array['#5B4CFF','#087E83','#376BD6','#B66A13'])[1+floor(random()*4)::int]
 from sj_private.bot_names order by random() limit 1 returning id into bot;
 mid=sj_private.new_match(uid,bot,mine.category_id,case when mine.joined_at<now()-interval '8 seconds' then null else mine.subtopic_id end,'bot');
 return jsonb_build_object('match_id',mid);
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
 if now()>=mq.started_at+make_interval(secs=>bp.response_ms::numeric/1000) then
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
create or replace function public.submit_answer(match_id uuid, question_index int, option_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); m public.matches; mq public.match_questions; elapsed int; correct boolean; points numeric;
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
 points=case when m.rules_version=2 then sj_private.battle_score(correct,elapsed,(mq.snapshot->>'time_limit_seconds')::int) else sj_private.score(correct,elapsed,(mq.snapshot->>'time_limit_seconds')::int,question_index=(select max(q.question_index) from public.match_questions q where q.match_id=submit_answer.match_id)) end;
 insert into public.match_answers(match_id,question_index,user_id,option_id,is_correct,response_ms,points) values(match_id,question_index,uid,option_id,correct,elapsed,points);
 perform sj_private.emit(match_id,'opponent_answered',jsonb_build_object('user_id',uid,'question_index',question_index));
 perform sj_private.tick_match(match_id);
 return jsonb_build_object('accepted',true);
end $$;
create or replace function sj_private.finalize_match(mid uuid, forced_winner uuid default null, abandoned boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare m public.matches; p record; winner uuid; s1 numeric; s2 numeric; t1 bigint; t2 bigint; actual numeric; expected numeric; delta int; reward int; ncorrect int;
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
 coalesce(sum(case when ans.is_correct then case when (select rules_version from public.matches where id=mid)=2 then 2 else 10*case when ans.question_index=(select max(x.question_index) from public.match_questions x where x.match_id=mid) then 2 else 1 end end else 0 end),0)::int base_points
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
 'multiplier',case when m.rules_version=2 then 1 when q.question_index=(select max(x.question_index) from public.match_questions x where x.match_id=m.id) then 2 else 1 end
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
create or replace function sj_private.option_integrity() returns trigger language plpgsql security definer set search_path='' as $$
declare qid uuid; n int; correct int;
begin
 qid=case when TG_OP='DELETE' then old.question_id else new.question_id end;
 if not exists(select 1 from public.questions where id=qid) then return null; end if;
 select count(*),count(*) filter(where is_correct) into n,correct from public.question_options where question_id=qid;
 if n <>4 or correct<>1 then raise exception 'QUESTION_NEEDS_FOUR_OPTIONS_AND_ONE_CORRECT'; end if;
 return null;
end $$;
create or replace function sj_private.published_integrity() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='published' and (select count(*) from public.question_options where question_id=new.id) <>4
 then raise exception 'QUESTION_NEEDS_OPTIONS'; end if; return null;
end $$;
create or replace function public.admin_save_question(payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare qid uuid=coalesce((payload->>'id')::uuid,gen_random_uuid()); before_data jsonb; opt jsonb; idx int=0; n int;
begin
 perform sj_private.require_admin('editor');
 select to_jsonb(q) into before_data from public.questions q where id=qid for update;
 if exists(select 1 from public.match_questions where question_id=qid) or exists(select 1 from public.daily_challenge_questions where question_id=qid)
 then raise exception 'QUESTION_ALREADY_USED_DUPLICATE_INSTEAD'; end if;
 if jsonb_typeof(payload->'options')<>'array' or jsonb_array_length(payload->'options') <>4 then raise exception 'INVALID_OPTIONS'; end if;
 select count(*) filter(where (value->>'is_correct')::boolean),count(distinct lower(trim(value->>'option_text')))
 into idx,n from jsonb_array_elements(payload->'options');
 if idx<>1 or n<>jsonb_array_length(payload->'options') or exists(select 1 from jsonb_array_elements(payload->'options') where length(trim(value->>'option_text'))=0)
 then raise exception 'ONE_CORRECT_AND_UNIQUE_OPTIONS_REQUIRED'; end if;
 insert into public.questions(id,category_id,subtopic_id,question_text,image_url,difficulty,time_limit_seconds,explanation,status,created_by)
 values(qid,(payload->>'category_id')::uuid,(payload->>'subtopic_id')::uuid,trim(payload->>'question_text'),payload->>'image_url',payload->>'difficulty',
 (payload->>'time_limit_seconds')::int,payload->>'explanation',payload->>'status',auth.uid())
 on conflict(id) do update set category_id=excluded.category_id,subtopic_id=excluded.subtopic_id,question_text=excluded.question_text,image_url=excluded.image_url,
 difficulty=excluded.difficulty,time_limit_seconds=excluded.time_limit_seconds,explanation=excluded.explanation,status=excluded.status;
 delete from public.question_options where question_id=qid;
 idx=0;
 for opt in select value from jsonb_array_elements(payload->'options') loop
 insert into public.question_options(question_id,option_text,image_url,is_correct,sort_order)
 values(qid,trim(opt->>'option_text'),opt->>'image_url',(opt->>'is_correct')::boolean,idx); idx=idx+1;
 end loop;
 perform sj_private.audit('save','questions',qid::text,jsonb_build_object('before',before_data,'after',payload));
 return qid;
end $$;
create or replace function public.admin_schedule_daily(day date,title text,question_ids uuid[] default null) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid; qid uuid; idx int=0;
begin
 perform sj_private.require_admin('editor');
 perform pg_advisory_xact_lock(hashtext('sj_daily_'||day::text));
 if day<(now() at time zone 'Asia/Kolkata')::date or day>(now() at time zone 'Asia/Kolkata')::date+365 or length(trim(title)) not between 2 and 100 then raise exception 'INVALID_CHALLENGE'; end if;
 select id into cid from public.daily_challenges where challenge_date=day for update;
 if exists(select 1 from public.daily_attempts where challenge_id=cid) then raise exception 'CHALLENGE_ALREADY_STARTED'; end if;
 if cid is null then cid=sj_private.generate_daily(day); end if;
 if question_ids is not null then
 if cardinality(question_ids) <>10 or (select count(distinct id) from public.questions where id=any(question_ids) and status='published')<>cardinality(question_ids) then raise exception 'INVALID_QUESTIONS'; end if;
 delete from public.daily_challenge_questions where challenge_id=cid;
 foreach qid in array question_ids loop
 insert into public.daily_challenge_questions(challenge_id,question_index,question_id,snapshot) values(cid,idx,qid,sj_private.question_snapshot(qid));idx=idx+1;
 end loop;
 end if;
 update public.daily_challenges set title=trim(admin_schedule_daily.title),status='scheduled',created_by=auth.uid() where id=cid;
 perform sj_private.audit('schedule','daily_challenges',cid::text,jsonb_build_object('day',day,'title',title));return cid;
end $$;

revoke all on all functions in schema sj_private from public,anon,authenticated;
revoke all on sj_private.bot_names from public,anon,authenticated;


-- 202611090015_cloud_data.sql

insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('668395b5-5411-5b0b-99a5-5efa80c18faf','Quantitative Aptitude','quant','calculate','#376BD6',0) on conflict(id) do nothing;
insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('d2c9217b-d3a7-5a4a-9815-c33704a25aff','English','english','translate','#087E83',1) on conflict(id) do nothing;
insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('09f88e78-88be-547c-9eb8-ef644b66db02','Reasoning','reasoning','psychology','#8051C5',2) on conflict(id) do nothing;
insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','General Awareness','general-awareness','public','#B66A13',3) on conflict(id) do nothing;
insert into public.subtopics(id,category_id,name,topic_group) select '0c965966-8a76-5cac-bc5d-0fac4c740c9d'::uuid,id,'Percentages','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select 'd8a04e6b-647a-5cfa-b2f2-2fbd91ef400d'::uuid,id,'Profit & Loss','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Ratio','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select '378d3bba-e539-57d4-9450-68034b1df9f7'::uuid,id,'Time & Work','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Speed & Distance','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'SI/CI','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Averages','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Number Systems','Arithmetic' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Algebra','Advanced Maths' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Geometry','Advanced Maths' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Trigonometry','Advanced Maths' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Mensuration','Advanced Maths' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Data Interpretation','Advanced Maths' from public.categories where slug='quant' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Coding-Decoding','Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Blood Relations','Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Direction','Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Syllogisms','Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Analogies','Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Series','Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Mirror Images','Non-Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Paper Folding','Non-Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Puzzles','Non-Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Seating Arrangements','Non-Verbal' from public.categories where slug='reasoning' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Static GK','General Awareness' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'History','General Awareness' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Polity','General Awareness' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select 'c48ff9f3-c397-56fe-8ffd-e8af52ca6db0'::uuid,id,'Geography','General Awareness' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Economics','General Awareness' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Computer Awareness','General Awareness' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Current Affairs','General Awareness' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Physics','General Science' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Chemistry','General Science' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Biology','General Science' from public.categories where slug='general-awareness' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Grammar rules','English' from public.categories where slug='english' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select '15ce5c00-e6c7-57c7-90b8-666779e61e99'::uuid,id,'Vocabulary','English' from public.categories where slug='english' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Idioms & Phrases','English' from public.categories where slug='english' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'One Word Substitution','English' from public.categories where slug='english' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Synonyms/Antonyms','English' from public.categories where slug='english' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Cloze Test','English' from public.categories where slug='english' on conflict(category_id,name) do update set topic_group=excluded.topic_group;
insert into public.subtopics(id,category_id,name,topic_group) select gen_random_uuid(),id,'Reading Comprehension','English' from public.categories where slug='english' on conflict(category_id,name) do update set topic_group=excluded.topic_group;

create table public.user_preferences (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 settings jsonb not null default '{}' check(jsonb_typeof(settings)='object'),
 updated_at timestamptz not null default now()
);
alter table public.user_preferences enable row level security;
create policy own_preferences on public.user_preferences for select to authenticated using(user_id=auth.uid());
grant select on public.user_preferences to authenticated;
create function public.save_preferences(patch jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); result jsonb; k text;
begin
 if uid is null or not exists(select 1 from public.profiles where id=uid and not is_banned) then raise exception 'AUTH_REQUIRED'; end if;
 if jsonb_typeof(patch) is distinct from 'object' then raise exception 'INVALID_SETTINGS'; end if;
 for k in select jsonb_object_keys(patch) loop
 if k in ('haptics','sound_effects','music_enabled','notifications') then
 if jsonb_typeof(patch->k)<>'boolean' then raise exception 'INVALID_SETTINGS'; end if;
 elsif k in ('effects_volume','music_volume') then
 if jsonb_typeof(patch->k)<>'number' or (patch->>k)::numeric not between 0 and 1 then raise exception 'INVALID_SETTINGS'; end if;
 elsif k='theme' then
 if patch->>k not in ('0','1','2') then raise exception 'INVALID_SETTINGS'; end if;
 elsif k='category' then
 if patch->>k<>'mixed' and not exists(select 1 from public.categories where id::text=patch->>k and is_active) then raise exception 'INVALID_SETTINGS'; end if;
 else raise exception 'UNKNOWN_SETTING'; end if;
 end loop;
 insert into public.user_preferences(user_id,settings) values(uid,patch) on conflict(user_id)
 do update set settings=user_preferences.settings||excluded.settings,updated_at=clock_timestamp() returning settings into result;
 return result;
end $$;
revoke all on function public.save_preferences(jsonb) from public,anon;
grant execute on function public.save_preferences(jsonb) to authenticated;

-- Lightweight invalidations: never broadcast question text, answers, or personal data.
create function sj_private.notify_data_change() returns trigger language plpgsql security definer set search_path='' as $$
declare row_data jsonb=case when TG_OP='DELETE' then to_jsonb(old) else to_jsonb(new) end; owner text;
begin
 if TG_TABLE_NAME='match_players' and TG_OP='UPDATE' and (to_jsonb(old)-'heartbeat_at'-'updated_at')=(to_jsonb(new)-'heartbeat_at'-'updated_at') then return null; end if;
 if TG_TABLE_NAME in ('categories','subtopics','app_settings','battle_rounds','daily_challenges') then
 perform realtime.send(jsonb_build_object('table',TG_TABLE_NAME),'changed','data:catalog',true);
 elsif TG_TABLE_NAME='admin_users' then
 select id::text into owner from public.profiles where email=row_data->>'email';
 if owner is not null then perform realtime.send(jsonb_build_object('table',TG_TABLE_NAME),'changed','data:user:'||owner,true); end if;
 elsif TG_TABLE_NAME in ('profiles','user_preferences','practice_attempts','daily_attempts','match_players') then
 owner=case when TG_TABLE_NAME='profiles' then row_data->>'id' else row_data->>'user_id' end;
 perform realtime.send(jsonb_build_object('table',TG_TABLE_NAME),'changed','data:user:'||owner,true);
 end if;
 perform realtime.send(jsonb_build_object('table',TG_TABLE_NAME),'changed','data:admin',true);
 return null;
end $$;
do $$ declare t text; begin
 foreach t in array array['categories','subtopics','app_settings','battle_rounds','profiles','user_preferences','practice_attempts','daily_attempts','match_players','questions','admin_users'] loop
 execute format('create trigger data_changed after insert or update or delete on public.%I for each row execute function sj_private.notify_data_change()',t);
 end loop;
end $$;
create policy data_receive on realtime.messages for select to authenticated using(
 realtime.topic()='data:catalog' or realtime.topic()='data:user:'||auth.uid()::text or (realtime.topic()='data:admin' and public.is_admin())
);

create function public.get_practice_history(before_at timestamptz default null, before_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare uid uuid=sj_private.require_player();
begin
 return jsonb_build_object('attempts',(select coalesce(jsonb_agg(r order by r.started_at desc,r.id desc),'[]') from (
 select id,score,correct_count,started_at,jsonb_array_length(questions) question_count from public.practice_attempts
 where user_id=uid and completed_at is not null and (before_at is null or (started_at,id)<(before_at,before_id))
 order by started_at desc,id desc limit 30) r));
end $$;
create function public.get_practice_review(attempt_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); a public.practice_attempts;
begin
 select * into a from public.practice_attempts where id=attempt_id and user_id=uid and completed_at is not null;
 if not found then raise exception 'REVIEW_UNAVAILABLE'; end if;
 return jsonb_build_object('questions',(select jsonb_agg(q||coalesce(a.answers->(i::int-1),'{}') order by i) from jsonb_array_elements(a.questions) with ordinality t(q,i)));
end $$;
revoke all on function public.get_practice_history(timestamptz,uuid),public.get_practice_review(uuid) from public,anon;
grant execute on function public.get_practice_history(timestamptz,uuid),public.get_practice_review(uuid) to authenticated;
drop function public.start_practice(uuid,uuid,boolean);
create or replace function public.start_practice(category_id uuid default null, subtopic_id uuid default null, timed boolean default true, exam_filter text default null, difficulty_filter text default null, question_count int default 10) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); aid uuid; qs jsonb;
begin
 perform sj_private.rate_limit('practice',15);
 select jsonb_agg(sj_private.question_snapshot(qid) order by ord) into qs
 from unnest(sj_private.pick_questions(question_count,category_id,subtopic_id,exam_filter,difficulty_filter)) with ordinality t(qid,ord);
 insert into public.practice_attempts(user_id,timed,questions) values(uid,timed,qs) returning id into aid;
 return jsonb_build_object('attempt_id',aid,'question_count',jsonb_array_length(qs),'question_index',0,
 'question',sj_private.safe_question(qs->0)||jsonb_build_object('deadline_at',case when timed then now()+make_interval(secs=>(qs->0->>'time_limit_seconds')::int) else null end));
end $$;

revoke all on function public.start_practice(uuid,uuid,boolean,text,text,int) from public,anon;
grant execute on function public.start_practice(uuid,uuid,boolean,text,text,int) to authenticated;
create or replace function public.admin_save_question(payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare qid uuid=coalesce((payload->>'id')::uuid,gen_random_uuid()); before_data jsonb; opt jsonb; idx int=0; n int;
begin
 perform sj_private.require_admin('editor');
 select to_jsonb(q) into before_data from public.questions q where id=qid for update;
 if exists(select 1 from public.match_questions where question_id=qid) or exists(select 1 from public.daily_challenge_questions where question_id=qid)
 then raise exception 'QUESTION_ALREADY_USED_DUPLICATE_INSTEAD'; end if;
 if jsonb_typeof(payload->'options')<>'array' or jsonb_array_length(payload->'options') <>4 then raise exception 'INVALID_OPTIONS'; end if;
 select count(*) filter(where (value->>'is_correct')::boolean),count(distinct lower(trim(value->>'option_text')))
 into idx,n from jsonb_array_elements(payload->'options');
 if idx<>1 or n<>jsonb_array_length(payload->'options') or exists(select 1 from jsonb_array_elements(payload->'options') where length(trim(value->>'option_text'))=0)
 then raise exception 'ONE_CORRECT_AND_UNIQUE_OPTIONS_REQUIRED'; end if;
 insert into public.questions(id,category_id,subtopic_id,question_text,image_url,difficulty,time_limit_seconds,explanation,status,created_by)
 values(qid,(payload->>'category_id')::uuid,(payload->>'subtopic_id')::uuid,trim(payload->>'question_text'),payload->>'image_url',payload->>'difficulty',
 (payload->>'time_limit_seconds')::int,payload->>'explanation',payload->>'status',auth.uid())
 on conflict(id) do update set category_id=excluded.category_id,subtopic_id=excluded.subtopic_id,question_text=excluded.question_text,image_url=excluded.image_url,
 difficulty=excluded.difficulty,time_limit_seconds=excluded.time_limit_seconds,explanation=excluded.explanation,status=excluded.status;
 delete from public.question_options where question_id=qid;
 idx=0;
 for opt in select value from jsonb_array_elements(payload->'options') loop
 insert into public.question_options(question_id,option_text,image_url,is_correct,sort_order)
 values(qid,trim(opt->>'option_text'),opt->>'image_url',(opt->>'is_correct')::boolean,idx); idx=idx+1;
 end loop;
 update public.questions set exam=nullif(trim(payload->>'exam'),'') where id=qid;
 perform sj_private.audit('save','questions',qid::text,jsonb_build_object('before',before_data,'after',payload));
 return qid;
end $$;
create or replace function public.admin_import_questions(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb; row_num int=0; category uuid; topic uuid; topic_name text; choice text; difficulty text; opts jsonb;
 fingerprint text=md5(payload::text); previous int; column_name text;
begin
 perform sj_private.require_admin('editor');
 if jsonb_typeof(payload->'questions') is distinct from 'array' then raise exception 'Expected a questions array'; end if;
 if jsonb_array_length(payload->'questions') not between 1 and 500 then raise exception 'Use 1–500 questions per file'; end if;
 perform pg_advisory_xact_lock(hashtext('sj_question_import'));
 select item_count into previous from sj_private.question_imports where batch_hash=fingerprint;
 if found then return jsonb_build_object('imported',previous,'already_imported',true); end if;
 for item in select value from jsonb_array_elements(payload->'questions') loop
   row_num=row_num+1;
   foreach column_name in array array['question','option_a','option_b','option_c','option_d','correct_answer','subject','difficulty','explanation'] loop
     if jsonb_typeof(item->column_name) is distinct from 'string' or trim(item->>column_name)='' then
       raise exception 'Question %: supply %',row_num,column_name;
     end if;
   end loop;
   choice=upper(trim(item->>'correct_answer')); difficulty=lower(trim(item->>'difficulty'));
   if choice not in ('A','B','C','D') or difficulty not in ('easy','medium','hard') or length(trim(item->>'question'))<4 then
     raise exception 'Question %: check question text, correct_answer (A–D) and difficulty',row_num;
   end if;
   select c.id into category from public.categories c where lower(trim(item->>'subject')) in (lower(c.name),lower(c.slug)) order by c.sort_order,c.id limit 1;
   if category is null then raise exception 'Question %: unknown subject "%". Add the category first',row_num,item->>'subject'; end if;
   topic=null; topic_name=nullif(trim(item->>'topic'),'');
   if topic_name is not null then
     select s.id into topic from public.subtopics s where s.category_id=category and lower(s.name)=lower(topic_name) order by s.id limit 1;
     if topic is null then insert into public.subtopics(category_id,name) values(category,topic_name) on conflict(category_id,name) do update set name=excluded.name returning id into topic; end if;
   end if;
   select jsonb_agg(jsonb_build_object('option_text',trim(item->>('option_'||l)),'is_correct',upper(l)=choice) order by l) into opts from unnest(array['a','b','c','d']) l;
   if (select count(distinct lower(o->>'option_text')) from jsonb_array_elements(opts) o)<>4 then raise exception 'Question %: options must be different',row_num; end if;
   perform public.admin_save_question(jsonb_build_object('category_id',category,'subtopic_id',topic,'question_text',trim(item->>'question'),
      'difficulty',difficulty,'time_limit_seconds',coalesce((item->>'time_limit_seconds')::int,15),'explanation',trim(item->>'explanation'),'status','draft','exam',item->>'exam','options',opts));
 end loop;
 insert into sj_private.question_imports values(fingerprint,row_num);
 return jsonb_build_object('imported',row_num,'already_imported',false);
end $$;
revoke all on all functions in schema sj_private from public,anon,authenticated;


-- 202611090016_rule_guards.sql

create or replace function public.admin_save_setting(key text,value jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin('super_admin');
 if key='questions_per_match' then if (value#>>'{}')::int <>4 then raise exception 'INVALID_SETTING'; end if;
 elsif key='search_timeout_seconds' then if (value#>>'{}')::int <>10 then raise exception 'INVALID_SETTING'; end if;
 elsif key in ('label_bots','maintenance_mode') then if jsonb_typeof(value)<>'boolean' then raise exception 'INVALID_SETTING'; end if;
 elsif key='min_app_version' then if jsonb_typeof(value)<>'string' then raise exception 'INVALID_SETTING'; end if;
 else raise exception 'INVALID_SETTING'; end if;
 insert into public.app_settings as s(key,value) values(key,value) on conflict on constraint app_settings_pkey do update set value=excluded.value;
 perform sj_private.audit('setting','app_settings',key,value);
end $$;
create or replace function public.get_match_state(match_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); m public.matches; mq public.match_questions;
begin
 select * into m from public.matches where id=match_id and (player1_id=uid or player2_id=uid);
 if not found then raise exception 'MATCH_NOT_FOUND' using errcode='42501'; end if;
 update public.match_players set heartbeat_at=now() where match_players.match_id=get_match_state.match_id and user_id=uid;
 select * into mq from public.match_questions where match_questions.match_id=get_match_state.match_id and question_index=m.current_question_index;
 return jsonb_build_object('match_id',m.id,'status',m.status,'rules_version',m.rules_version,'phase',m.phase,'mode',m.mode,'question_index',m.current_question_index,
 'question_count',(select count(*) from public.match_questions q where q.match_id=m.id),'server_now',clock_timestamp(),'starts_at',m.started_at,
 'label_bots',coalesce((select value from public.app_settings where key='label_bots'),'true'::jsonb),
 'players',(select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'level',p.level,'avatar_url',case when p.avatar_url like 'preset:%' or p.avatar_url like 'photo:%' or p.avatar_url like 'color:%' then p.avatar_url end,'rating',mp.rating_before,'score',coalesce((select sum(points) from public.match_answers a join public.match_questions q on q.match_id=a.match_id and q.question_index=a.question_index where a.match_id=m.id and a.user_id=p.id and q.revealed_at is not null),0),
 'rating_after',mp.rating_after,'xp_gained',mp.xp_gained,'result',mp.result,'connected',p.is_bot or mp.heartbeat_at>now()-interval '5 seconds')) from public.match_players mp join public.profiles p on p.id=mp.user_id where mp.match_id=m.id),
 'question',case when mq.started_at is null then null else sj_private.safe_question(mq.snapshot)||jsonb_build_object('started_at',mq.started_at,'deadline_at',mq.deadline_at) end,
 'answered',(select coalesce(jsonb_agg(a.user_id),'[]') from public.match_answers a where a.match_id=m.id and a.question_index=m.current_question_index),
 'result',case when mq.revealed_at is not null then jsonb_build_object('correct_option_id',mq.snapshot->>'correct_option_id','explanation',mq.snapshot->>'explanation',
 'answers',(select coalesce(jsonb_agg(jsonb_build_object('user_id',a.user_id,'option_id',a.option_id,'points',a.points)),'[]') from public.match_answers a where a.match_id=m.id and a.question_index=m.current_question_index)) else null end);
end $$;
create or replace function sj_private.match_player_report(mid uuid, participant uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',p.id,'full_name',p.full_name,'is_bot',p.is_bot,
 'avatar_url',case when p.avatar_url like 'preset:%' or p.avatar_url like 'photo:%' or p.avatar_url like 'color:%' then p.avatar_url end,
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
 coalesce(sum(case when ans.is_correct then case when (select rules_version from public.matches where id=mid)=2 then 2 else 10*case when ans.question_index=(select max(x.question_index) from public.match_questions x where x.match_id=mid) then 2 else 1 end end else 0 end),0)::int base_points
 from public.match_answers ans join public.match_questions mq on mq.match_id=ans.match_id and mq.question_index=ans.question_index
 where ans.match_id=mid and ans.user_id=participant and mq.started_at is not null) a
 where mp.match_id=mid and mp.user_id=participant
$$;
create or replace function public.admin_save_question(payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare qid uuid=coalesce((payload->>'id')::uuid,gen_random_uuid()); before_data jsonb; opt jsonb; idx int=0; n int; topic uuid; topic_name text;
begin
 perform sj_private.require_admin('editor');
 select to_jsonb(q) into before_data from public.questions q where id=qid for update;
 if exists(select 1 from public.match_questions where question_id=qid) or exists(select 1 from public.daily_challenge_questions where question_id=qid)
 then raise exception 'QUESTION_ALREADY_USED_DUPLICATE_INSTEAD'; end if;
 if jsonb_typeof(payload->'options')<>'array' or jsonb_array_length(payload->'options') <>4 then raise exception 'INVALID_OPTIONS'; end if;
 select count(*) filter(where (value->>'is_correct')::boolean),count(distinct lower(trim(value->>'option_text')))
 into idx,n from jsonb_array_elements(payload->'options');
 if idx<>1 or n<>jsonb_array_length(payload->'options') or exists(select 1 from jsonb_array_elements(payload->'options') where length(trim(value->>'option_text'))=0)
 then raise exception 'ONE_CORRECT_AND_UNIQUE_OPTIONS_REQUIRED'; end if;
 topic=(payload->>'subtopic_id')::uuid;
 topic_name=nullif(trim(payload->>'topic_name'),'');
 if topic is null and topic_name is not null then
 select id into topic from public.subtopics where category_id=(payload->>'category_id')::uuid and lower(name)=lower(topic_name) limit 1;
 if topic is null then insert into public.subtopics(category_id,name) values((payload->>'category_id')::uuid,topic_name) on conflict(category_id,name) do update set name=excluded.name returning id into topic; end if;
 end if;
 if topic is null or length(trim(coalesce(payload->>'explanation','')))=0 then raise exception 'TOPIC_AND_EXPLANATION_REQUIRED'; end if;
 insert into public.questions(id,category_id,subtopic_id,question_text,image_url,difficulty,time_limit_seconds,explanation,status,created_by)
 values(qid,(payload->>'category_id')::uuid,topic,trim(payload->>'question_text'),payload->>'image_url',payload->>'difficulty',
 (payload->>'time_limit_seconds')::int,payload->>'explanation',payload->>'status',auth.uid())
 on conflict(id) do update set category_id=excluded.category_id,subtopic_id=excluded.subtopic_id,question_text=excluded.question_text,image_url=excluded.image_url,
 difficulty=excluded.difficulty,time_limit_seconds=excluded.time_limit_seconds,explanation=excluded.explanation,status=excluded.status;
 delete from public.question_options where question_id=qid;
 idx=0;
 for opt in select value from jsonb_array_elements(payload->'options') loop
 insert into public.question_options(question_id,option_text,image_url,is_correct,sort_order)
 values(qid,trim(opt->>'option_text'),opt->>'image_url',(opt->>'is_correct')::boolean,idx); idx=idx+1;
 end loop;
 update public.questions set exam=nullif(trim(payload->>'exam'),'') where id=qid;
 perform sj_private.audit('save','questions',qid::text,jsonb_build_object('before',before_data,'after',payload));
 return qid;
end $$;

create function sj_private.notify_standings() returns trigger language plpgsql security definer set search_path='' as $$
begin perform realtime.send('{}','standings','data:catalog',true); return null; end $$;
create trigger standings_changed after update of rating,xp on public.profiles for each statement execute function sj_private.notify_standings();
create trigger daily_standings_changed after update of completed_at on public.daily_attempts for each statement execute function sj_private.notify_standings();
create trigger daily_catalog_changed after insert or update or delete on public.daily_challenges for each row execute function sj_private.notify_data_change();
create index matches_player1_history on public.matches(player1_id,created_at desc,id);
create index matches_player2_history on public.matches(player2_id,created_at desc,id);
revoke all on all functions in schema sj_private from public,anon,authenticated;


-- 202611090017_history_pages.sql

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


-- 202611090018_live_bot_progress.sql

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


-- 202611100019_bot_identities.sql

-- Keep one private identity pool for all newly created bot opponents.
alter table sj_private.bot_names
 add column avatar_color text not null default '#5B4CFF' check (avatar_color ~ '^#[0-9A-Fa-f]{6}$'),
 add column experience_level integer not null default 8 check (experience_level between 8 and 35),
 add column play_style text not null default 'Balanced' check (play_style in ('Speedster','Analytical','Balanced','Wildcard'));

delete from sj_private.bot_names;
with requested(name) as (
 select unnest(array[
  'Arjun','Akhil','Vishnu','Rahul','Gokul','Abhijith','Nikhil','Kiran','Anand','Pranav',
  'Aswin','Harikrishnan','Sreehari','Adithyan','Rohith','Sreejith','Abhinav','Adarsh','Deepak','Mithun',
  'Vivek','Amal','Jishnu','Sandeep','Anoop','Sarath','Ranjith','Ajith',
  'Athira','Anjana','Devika','Lakshmi','Parvathy','Anagha','Sreelakshmi','Kavya','Aparna','Arya',
  'Nandana','Meera','Aswathy','Gopika','Keerthana','Sreedevi','Anjali','Amritha','Gayathri','Haritha',
  'Malavika','Reshma','Neethu','Aiswarya','Sreya','Archana','Soumya','Krishnapriya','Akshaya',
  'Joseph','Thomas','Mathew','John','George','Jithin','Albin','Alan','Joel','Kevin',
  'Robin','Abel','Jaison','Melvin','Jibin','Jomon','Tijo','Rony','Bibin','Tony',
  'Justin','Don','Antony','Sebastian','Jerin','Jijo','Biju','Shijo','Christo',
  'Maria','Ann','Ancy','Merin','Aleena','Elizabeth','Christina','Liya','Anna','Mary',
  'Angel','Sneha','Neena','Blessy','Teena','Jessy','Anju','Anitta','Rose','Riya',
  'Teresa','Dona','Diya','Sharon','Elsa','Stephy','Nisha','Jincy','Rincy','Rosy',
  'Ashiq','Shamil','Niyas','Fasil','Shafi','Rashid','Farhan','Riyas','Junaid','Favas',
  'Asif','Afsal','Praveen',
  'Fathima','Ayesha','Shahana','Safna','Hiba','Shahina','Nida','Liya','Diya','Fidha','Aliya','Roobie'
 ])
), names as (
 select distinct initcap(btrim(name)) as name from requested where btrim(name) <> ''
), numbered as (
 select name, row_number() over (order by name) - 1 as n from names
)
insert into sj_private.bot_names(name,avatar_color,experience_level,play_style)
select name,
 (array['#5B4CFF','#087E83','#376BD6','#B66A13','#C25181','#3B8C64','#7055A5','#B86B4A'])[1+(n%8)::integer],
 8+(n%28)::integer,
 (array['Speedster','Analytical','Balanced','Wildcard'])[1+(n%4)::integer]
from numbered;

do $$ begin
 if (select count(*) from sj_private.bot_names) < 130 then
  raise exception 'BOT_IDENTITY_POOL_INCOMPLETE';
 end if;
end $$;

-- Existing match rows keep their bot IDs, scores and stored play styles.
-- Refresh their visible names, levels and avatar colors to the new pool.
with existing as (
 select id, row_number() over (order by id) as n from public.profiles where is_bot
), pool as (
 select name,avatar_color,experience_level,row_number() over (order by name) as n
 from sj_private.bot_names
)
update public.profiles p
set full_name=b.name,level=b.experience_level,avatar_url='color:'||b.avatar_color
from existing e join pool b on b.n=1+((e.n-1)%(select count(*) from pool))
where p.id=e.id;

create or replace function sj_private.new_match(p1 uuid, p2 uuid, category uuid, topic uuid, mode text) returns uuid
language plpgsql security definer set search_path='' as $$
declare mid uuid; r record; qid uuid; snap jsonb; correct_rounds int[]; target int; style text; delay numeric; short boolean;
begin
 if mode='bot' then
  select b.play_style into style from sj_private.bot_names b
  join public.profiles p on p.full_name=b.name where p.id=p2;
 end if;
 style=coalesce(style,(array['Speedster','Analytical','Balanced','Wildcard'])[1+floor(random()*4)::int]);
 target=2+floor(random()*3)::int;
 select array_agg(i) into correct_rounds from (select i from generate_series(0,3) i order by random() limit target) t;
 insert into public.matches(category_id,mode,player1_id,player2_id,started_at,next_tick_at,rules_version,bot_style)
 values(null,mode,p1,p2,now()+interval '3 seconds',now()+interval '3 seconds',2,case when mode='bot' then style end) returning id into mid;
 insert into public.match_players(match_id,user_id,rating_before) select mid,id,rating from public.profiles where id in(p1,p2);
 for r in select b.*,c.id category from public.battle_rounds b join public.categories c on c.slug=b.subject_slug and c.is_active order by b.round_index loop
  qid=(sj_private.pick_questions(1,r.category))[1];
  snap=sj_private.question_snapshot(qid)||jsonb_build_object('time_limit_seconds',r.duration_seconds);
  insert into public.match_questions(match_id,question_index,question_id,snapshot,option_order) values(mid,r.round_index,qid,snap,snap->'options');
  if mode='bot' then
   short=r.duration_seconds=15;
   delay=case style when 'Speedster' then case when short then 2+random()*4 else 8+random()*8 end
     when 'Analytical' then case when short then 5+random()*6 else 20+random()*14 end
     when 'Balanced' then case when short then 3+random()*5 else 12+random()*12 end
     else 2+random()*(r.duration_seconds-3) end;
   insert into public.bot_plans(match_id,question_index,will_be_correct,response_ms) values(mid,r.round_index,r.round_index=any(correct_rounds),floor(delay*1000)::int);
  end if;
 end loop;
 if (select count(*) from public.match_questions where match_id=mid)<>4 then raise exception 'NOT_ENOUGH_QUESTIONS'; end if;
 delete from public.matchmaking_queue where user_id in(p1,p2);
 perform realtime.send(jsonb_build_object('match_id',mid),'match_found','user:'||p1::text,true);
 if mode='live' then perform realtime.send(jsonb_build_object('match_id',mid),'match_found','user:'||p2::text,true); end if;
 return mid;
end $$;

create or replace function public.start_bot_match() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); mine public.matchmaking_queue; bot uuid; mid uuid; timeout int;
begin
 perform 1 from public.profiles where id=uid for update;
 select id into mid from public.matches where (player1_id=uid or player2_id=uid) and status in ('pending','in_progress') limit 1;
 if mid is not null then return jsonb_build_object('match_id',mid); end if;
 select * into mine from public.matchmaking_queue where user_id=uid for update;
 if not found then raise exception 'NOT_QUEUED'; end if;
 timeout=coalesce((select (value#>>'{}')::int from public.app_settings where key='search_timeout_seconds'),10);
 if now()<mine.joined_at+make_interval(secs=>timeout) then raise exception 'SEARCH_NOT_EXPIRED'; end if;
 insert into public.profiles(full_name,is_bot,rating,level,avatar_url)
 select name,true,mine.rating,experience_level,'color:'||avatar_color
 from sj_private.bot_names order by random() limit 1 returning id into bot;
 mid=sj_private.new_match(uid,bot,mine.category_id,case when mine.joined_at<now()-interval '8 seconds' then null else mine.subtopic_id end,'bot');
 return jsonb_build_object('match_id',mid);
end $$;

revoke all on sj_private.bot_names from public,anon,authenticated;


-- 202611100020_weekly_podium_portraits.sql

-- A stable tie order makes the portrait endpoint and visible podium agree.
create or replace function public.get_leaderboard(type text default 'all_time', category_id uuid default null, result_limit int default 100) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); rows jsonb;
begin
 if type not in ('all_time','weekly','daily') then raise exception 'INVALID_LEADERBOARD'; end if;
 with ranked as (
 select p.id,p.full_name,p.level,p.rating,
 case when type='daily' then coalesce(d.score,0) when type='weekly' then coalesce(w.points,0) else p.rating end metric,
 rank() over(order by case when type='daily' then coalesce(d.score,0) when type='weekly' then coalesce(w.points,0) else p.rating end desc,coalesce(d.total_time_ms,0)) rank
 from public.profiles p
 left join public.daily_attempts d on d.user_id=p.id and d.completed_at is not null and d.challenge_id=(select id from public.daily_challenges where challenge_date=(now() at time zone 'Asia/Kolkata')::date)
 left join lateral(select sum(mp.score) points from public.match_players mp join public.matches m on m.id=mp.match_id where mp.user_id=p.id and m.status='completed'
 and (get_leaderboard.category_id is null or m.category_id=get_leaderboard.category_id)
 and m.ended_at>=date_trunc('week',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata') w on true
 where p.profile_completed and not p.is_bot and not p.is_banned and (type<>'daily' or d.id is not null)
 ) select coalesce(jsonb_agg(to_jsonb(r) order by rank,id),'[]') into rows from ranked r where rank<=least(greatest(result_limit,1),100) or id=uid;
 return jsonb_build_object('rows',rows);
end $$;

-- Return portraits only for the three weekly leaders. Gallery bytes stay in
-- the private table and are never included in the general leaderboard query.
create function public.get_weekly_podium_portraits() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  perform sj_private.require_player();
  select jsonb_build_object('rows',coalesce(jsonb_agg(
    jsonb_build_object(
      'id',leaders.id,
      'avatar_url',leaders.avatar_url,
      'photo_png',case when leaders.avatar_url='photo:'||photos.photo_id::text
        then replace(encode(photos.thumbnail,'base64'),chr(10),'') end
    ) order by leaders.points desc,leaders.id
  ),'[]'::jsonb)) into result
  from (
    select p.id,p.avatar_url,coalesce(w.points,0) points
    from public.profiles p
    left join lateral (
      select sum(mp.score) points
      from public.match_players mp join public.matches m on m.id=mp.match_id
      where mp.user_id=p.id and m.status='completed'
        and m.ended_at>=date_trunc('week',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'
    ) w on true
    where p.profile_completed and not p.is_bot and not p.is_banned
    order by coalesce(w.points,0) desc,p.id
    limit 3
  ) leaders
  left join sj_private.player_photos photos on photos.owner_id=leaders.id;
  return result;
end $$;

revoke all on function public.get_weekly_podium_portraits() from public,anon,authenticated;
grant execute on function public.get_weekly_podium_portraits() to authenticated;

create trigger podium_identity_changed
after update of avatar_url,full_name on public.profiles
for each statement execute function sj_private.notify_standings();



-- 202611100021_battle_trophies.sql

-- Reset all players to zero as requested. The old rating column remains a
-- compatibility source for matchmaking; trophies is its stored alias.
alter table public.profiles alter column rating set default 0;
update public.profiles set rating=0 where rating<>0;
update public.matchmaking_queue set rating=0 where rating<>0;
update public.match_players set rating_before=0
where match_id in (select id from public.matches where status in ('pending','in_progress'));
alter table public.profiles add column trophies integer generated always as (rating) stored;
alter table public.profiles add constraint profiles_trophies_nonnegative check (trophies >= 0);
grant select(trophies) on public.profiles to authenticated;

create function sj_private.trophy_delta(outcome numeric) returns integer
language sql immutable set search_path='' as $$
  select case outcome when 1 then 15 when 0 then -5 else 0 end;
$$;

-- Battle points select the winner; the trophy payout is fixed for both live
-- and bot matches. The completed/abandoned guard makes finalization idempotent.
create or replace function sj_private.finalize_match(mid uuid, forced_winner uuid default null, abandoned boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare m public.matches; p record; winner uuid; s1 numeric; s2 numeric; t1 bigint; t2 bigint; actual numeric; delta int; reward int; ncorrect int;
begin
 select * into m from public.matches where id=mid for update;
 if m.status in ('completed','abandoned') then return; end if;
 if abandoned then update public.matches set status='abandoned',phase='finished',ended_at=now() where id=mid; return; end if;
 select coalesce(sum(points),0),coalesce(sum(response_ms) filter(where is_correct),0) into s1,t1 from public.match_answers where match_id=mid and user_id=m.player1_id;
 select coalesce(sum(points),0),coalesce(sum(response_ms) filter(where is_correct),0) into s2,t2 from public.match_answers where match_id=mid and user_id=m.player2_id;
 winner=coalesce(forced_winner,case when s1>s2 or (s1=s2 and t1<t2) then m.player1_id when s2>s1 or (s1=s2 and t2<t1) then m.player2_id else null end);
 for p in select mp.*,pr.is_bot from public.match_players mp join public.profiles pr on pr.id=mp.user_id where match_id=mid order by mp.user_id loop
 actual=case when winner is null then .5 when winner=p.user_id then 1 else 0 end;
 delta=sj_private.trophy_delta(actual);
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

-- The account and all-time ranking now expose the trophy count explicitly.
create or replace function public.get_leaderboard(type text default 'all_time', category_id uuid default null, result_limit int default 100) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); rows jsonb;
begin
 if type not in ('all_time','weekly','daily') then raise exception 'INVALID_LEADERBOARD'; end if;
 with ranked as (
 select p.id,p.full_name,p.level,p.rating,p.trophies,
 case when type='daily' then coalesce(d.score,0) when type='weekly' then coalesce(w.points,0) else p.trophies end metric,
 rank() over(order by case when type='daily' then coalesce(d.score,0) when type='weekly' then coalesce(w.points,0) else p.trophies end desc,coalesce(d.total_time_ms,0)) rank
 from public.profiles p
 left join public.daily_attempts d on d.user_id=p.id and d.completed_at is not null and d.challenge_id=(select id from public.daily_challenges where challenge_date=(now() at time zone 'Asia/Kolkata')::date)
 left join lateral(select sum(mp.score) points from public.match_players mp join public.matches m on m.id=mp.match_id where mp.user_id=p.id and m.status='completed'
 and (get_leaderboard.category_id is null or m.category_id=get_leaderboard.category_id)
 and m.ended_at>=date_trunc('week',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata') w on true
 where p.profile_completed and not p.is_bot and not p.is_banned and (type<>'daily' or d.id is not null)
 ) select coalesce(jsonb_agg(to_jsonb(r) order by rank,id),'[]') into rows from ranked r where rank<=least(greatest(result_limit,1),100) or id=uid;
 return jsonb_build_object('rows',rows);
end $$;

revoke all on function sj_private.trophy_delta(numeric) from public,anon,authenticated;



-- Seed
-- Generated by tools/generate_seed.py. Development examples: review before publishing to students.
begin;
insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('668395b5-5411-5b0b-99a5-5efa80c18faf','Quantitative Aptitude','quant','calculate','#376BD6',0) on conflict(id) do nothing;
insert into public.subtopics(id,category_id,name,sort_order) values ('0c965966-8a76-5cac-bc5d-0fac4c740c9d','668395b5-5411-5b0b-99a5-5efa80c18faf','Percentages',0) on conflict(id) do nothing;
insert into public.subtopics(id,category_id,name,sort_order) values ('378d3bba-e539-57d4-9450-68034b1df9f7','668395b5-5411-5b0b-99a5-5efa80c18faf','Time & Work',1) on conflict(id) do nothing;
insert into public.subtopics(id,category_id,name,sort_order) values ('d8a04e6b-647a-5cfa-b2f2-2fbd91ef400d','668395b5-5411-5b0b-99a5-5efa80c18faf','Profit & Loss',2) on conflict(id) do nothing;
insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('d2c9217b-d3a7-5a4a-9815-c33704a25aff','English','english','translate','#087E83',1) on conflict(id) do nothing;
insert into public.subtopics(id,category_id,name,sort_order) values ('15ce5c00-e6c7-57c7-90b8-666779e61e99','d2c9217b-d3a7-5a4a-9815-c33704a25aff','Vocabulary',0) on conflict(id) do nothing;
insert into public.subtopics(id,category_id,name,sort_order) values ('acf1d39a-0793-5fc6-b20e-ababc6f69306','d2c9217b-d3a7-5a4a-9815-c33704a25aff','Grammar',1) on conflict(id) do nothing;
insert into public.subtopics(id,category_id,name,sort_order) values ('9d7380b8-75fd-5049-92b0-3c4314429881','d2c9217b-d3a7-5a4a-9815-c33704a25aff','Comprehension',2) on conflict(id) do nothing;
insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('09f88e78-88be-547c-9eb8-ef644b66db02','Reasoning','reasoning','psychology','#8051C5',2) on conflict(id) do nothing;
insert into public.subtopics(id,category_id,name,sort_order) values ('07408f66-e1b7-5ee6-81b0-ff377f4d0a76','09f88e78-88be-547c-9eb8-ef644b66db02','Number Series',0) on conflict(id) do nothing;
insert into public.subtopics(id,category_id,name,sort_order) values ('be920bfe-9ab3-5311-b419-1385df5f325e','09f88e78-88be-547c-9eb8-ef644b66db02','Coding & Decoding',1) on conflict(id) do nothing;
insert into public.subtopics(id,category_id,name,sort_order) values ('263a42f4-b1ed-5327-90c0-cd36ab8eb9f3','09f88e78-88be-547c-9eb8-ef644b66db02','Logical Reasoning',2) on conflict(id) do nothing;
insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','General Awareness','general-awareness','public','#B66A13',3) on conflict(id) do nothing;
insert into public.subtopics(id,category_id,name,sort_order) values ('cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','Indian Polity',0) on conflict(id) do nothing;
insert into public.subtopics(id,category_id,name,sort_order) values ('c48ff9f3-c397-56fe-8ffd-e8af52ca6db0','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','Geography',1) on conflict(id) do nothing;
insert into public.subtopics(id,category_id,name,sort_order) values ('1898f5a5-af8f-5e22-b21f-bb51f1e6fb2c','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','Science',2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('4bb4d0fa-c5fb-52f5-8ebc-92bdc247d29f','668395b5-5411-5b0b-99a5-5efa80c18faf','0c965966-8a76-5cac-bc5d-0fac4c740c9d','What is 5% of 100?','easy',15,'5% of 100 = 100 × 5/100 = 5.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ea91a9a0-844d-5771-a853-a92ca5d3f4f5','4bb4d0fa-c5fb-52f5-8ebc-92bdc247d29f','5',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('42feb420-2273-5a6f-9979-14e3a1c1c5bf','4bb4d0fa-c5fb-52f5-8ebc-92bdc247d29f','10',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0c137281-79df-5fdf-8277-35ee7f7368bb','4bb4d0fa-c5fb-52f5-8ebc-92bdc247d29f','15',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('81aab510-8f27-53e2-8a25-a425e13a1605','4bb4d0fa-c5fb-52f5-8ebc-92bdc247d29f','20',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('cbc457be-febe-59ab-84b6-5d7d5ab52a4a','668395b5-5411-5b0b-99a5-5efa80c18faf','378d3bba-e539-57d4-9450-68034b1df9f7','What is 10% of 120?','medium',15,'10% of 120 = 120 × 10/100 = 12.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1bf31a21-92fc-5c77-944f-128c44e1c873','cbc457be-febe-59ab-84b6-5d7d5ab52a4a','12',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('97fee308-dbd4-5218-9736-52c4e41104b4','cbc457be-febe-59ab-84b6-5d7d5ab52a4a','17',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1ec0b00a-540a-5a6a-b959-c3fc20347516','cbc457be-febe-59ab-84b6-5d7d5ab52a4a','22',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('749d3eea-2bc0-59fd-84e7-df57ad367d07','cbc457be-febe-59ab-84b6-5d7d5ab52a4a','27',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('061aa163-ce05-5892-8cf5-8fccf14b9318','668395b5-5411-5b0b-99a5-5efa80c18faf','d8a04e6b-647a-5cfa-b2f2-2fbd91ef400d','What is 15% of 140?','hard',15,'15% of 140 = 140 × 15/100 = 21.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('18f5f69d-020b-58f0-9017-2e8ffb698e57','061aa163-ce05-5892-8cf5-8fccf14b9318','21',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6bc91624-697c-58ea-b952-8fa6a7a56a6d','061aa163-ce05-5892-8cf5-8fccf14b9318','26',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('bddea05e-0f1e-5320-90c8-75b9db337d27','061aa163-ce05-5892-8cf5-8fccf14b9318','31',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('57012bd7-e0ad-5e5a-a71e-0024f7707732','061aa163-ce05-5892-8cf5-8fccf14b9318','36',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('7d1525c1-b378-57aa-8b29-48b1e5e3a0be','668395b5-5411-5b0b-99a5-5efa80c18faf','0c965966-8a76-5cac-bc5d-0fac4c740c9d','What is 20% of 160?','easy',15,'20% of 160 = 160 × 20/100 = 32.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('24deee89-a890-5a23-b427-cb5b8d02b55b','7d1525c1-b378-57aa-8b29-48b1e5e3a0be','32',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c9cdc5f3-f5cb-5158-bfeb-08fcf8e92931','7d1525c1-b378-57aa-8b29-48b1e5e3a0be','37',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e6ab269f-dd93-5f8c-9742-a724a9d19af7','7d1525c1-b378-57aa-8b29-48b1e5e3a0be','42',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('054fea01-1e5c-5fa5-9b40-4ad15b42b49a','7d1525c1-b378-57aa-8b29-48b1e5e3a0be','47',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('404d5104-1988-5d16-8453-78bdfa0f53ae','668395b5-5411-5b0b-99a5-5efa80c18faf','378d3bba-e539-57d4-9450-68034b1df9f7','What is 25% of 180?','medium',15,'25% of 180 = 180 × 25/100 = 45.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2456e3d1-8910-57d1-90e5-355801f19c1c','404d5104-1988-5d16-8453-78bdfa0f53ae','45',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('78d02efb-136d-5d9a-85f6-8ea2e11e1e29','404d5104-1988-5d16-8453-78bdfa0f53ae','50',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ac4bb62c-5237-5e7b-8a58-3ff2256b7fb4','404d5104-1988-5d16-8453-78bdfa0f53ae','55',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f2babbe0-a415-578c-98d6-4b8b782e02b6','404d5104-1988-5d16-8453-78bdfa0f53ae','60',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('67bf3bef-d7e0-5eb7-a6f4-e9f72a86f007','668395b5-5411-5b0b-99a5-5efa80c18faf','d8a04e6b-647a-5cfa-b2f2-2fbd91ef400d','What is 5% of 200?','easy',15,'5% of 200 = 200 × 5/100 = 10.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ff70f1bf-b6e5-545f-a820-6c50b878c182','67bf3bef-d7e0-5eb7-a6f4-e9f72a86f007','10',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9ff73de3-f259-5aff-a77f-a5cb1890f7cc','67bf3bef-d7e0-5eb7-a6f4-e9f72a86f007','15',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f7775c67-9d5a-579e-a2c1-592b7b5406cb','67bf3bef-d7e0-5eb7-a6f4-e9f72a86f007','20',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e1209a1b-72c0-5ca6-9676-f9425ae47443','67bf3bef-d7e0-5eb7-a6f4-e9f72a86f007','25',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('4efa57be-715e-56bc-8438-f3bacf78a12d','668395b5-5411-5b0b-99a5-5efa80c18faf','0c965966-8a76-5cac-bc5d-0fac4c740c9d','What is 10% of 220?','medium',15,'10% of 220 = 220 × 10/100 = 22.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('37883225-f908-57eb-a873-a5735343ba5d','4efa57be-715e-56bc-8438-f3bacf78a12d','22',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e4a46cf0-f936-5c00-9e85-2b1c0ec79cf8','4efa57be-715e-56bc-8438-f3bacf78a12d','27',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('56f1bb94-c0b5-58fa-a795-43b84ea8704c','4efa57be-715e-56bc-8438-f3bacf78a12d','32',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('5791378d-6b9f-551a-8c8e-e02f17273baa','4efa57be-715e-56bc-8438-f3bacf78a12d','37',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('f4eb972e-76ac-5ee9-b1e6-220d5267934b','668395b5-5411-5b0b-99a5-5efa80c18faf','378d3bba-e539-57d4-9450-68034b1df9f7','What is 15% of 240?','hard',15,'15% of 240 = 240 × 15/100 = 36.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ca4f87b5-c554-5740-bb47-8cbfdad52b56','f4eb972e-76ac-5ee9-b1e6-220d5267934b','36',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7c25030a-86e0-5121-a06e-d1275ccedd65','f4eb972e-76ac-5ee9-b1e6-220d5267934b','41',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3f45796e-6ca5-501e-8607-bd4d670e01a6','f4eb972e-76ac-5ee9-b1e6-220d5267934b','46',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9f5a871f-2e64-550c-9747-416a72eab10e','f4eb972e-76ac-5ee9-b1e6-220d5267934b','51',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('261f4e22-d18d-52b6-9728-838997596be2','668395b5-5411-5b0b-99a5-5efa80c18faf','d8a04e6b-647a-5cfa-b2f2-2fbd91ef400d','What is 20% of 260?','easy',15,'20% of 260 = 260 × 20/100 = 52.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('49bf33ed-d43e-5bf8-901f-055f854c63da','261f4e22-d18d-52b6-9728-838997596be2','52',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f9bc5919-84fe-51fa-8260-235b4ebb4d42','261f4e22-d18d-52b6-9728-838997596be2','57',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e42f26a8-7ee7-5666-bdf4-e31607cf8111','261f4e22-d18d-52b6-9728-838997596be2','62',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('83525645-2f1a-5876-8e44-a9a651e48d82','261f4e22-d18d-52b6-9728-838997596be2','67',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('2230d79b-7f8e-560c-ac52-9fd11056821c','668395b5-5411-5b0b-99a5-5efa80c18faf','0c965966-8a76-5cac-bc5d-0fac4c740c9d','What is 25% of 280?','medium',15,'25% of 280 = 280 × 25/100 = 70.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b5f53c41-bf3f-53ad-9d95-204d59614876','2230d79b-7f8e-560c-ac52-9fd11056821c','70',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('92b41ffe-8ccb-56fe-86a9-3c2e187605b1','2230d79b-7f8e-560c-ac52-9fd11056821c','75',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('af841d37-934b-5a74-8161-0befc6d61ab8','2230d79b-7f8e-560c-ac52-9fd11056821c','80',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('95505956-d8b6-5e67-b1b3-2c5ac2764628','2230d79b-7f8e-560c-ac52-9fd11056821c','85',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('8e47c351-44f2-5d09-8d7a-41885c22f7a9','668395b5-5411-5b0b-99a5-5efa80c18faf','378d3bba-e539-57d4-9450-68034b1df9f7','What is 5% of 300?','easy',15,'5% of 300 = 300 × 5/100 = 15.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f4d8a309-8fd0-57a5-ba7d-a2db7d9fd90b','8e47c351-44f2-5d09-8d7a-41885c22f7a9','15',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b662646a-f225-5575-980f-d56c8097536e','8e47c351-44f2-5d09-8d7a-41885c22f7a9','20',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0bb99375-a2d2-5355-9140-e589a082ccde','8e47c351-44f2-5d09-8d7a-41885c22f7a9','25',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b73e56db-2bff-5e11-8432-3909264311a3','8e47c351-44f2-5d09-8d7a-41885c22f7a9','30',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('1fb699dc-3bee-5954-813e-73fa1b12497c','668395b5-5411-5b0b-99a5-5efa80c18faf','d8a04e6b-647a-5cfa-b2f2-2fbd91ef400d','What is 10% of 320?','medium',15,'10% of 320 = 320 × 10/100 = 32.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7919a95a-a9b2-5efe-b12a-126fa096fec1','1fb699dc-3bee-5954-813e-73fa1b12497c','32',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('833f7593-0d1e-5b9c-b2c3-93b4ffe6a1a5','1fb699dc-3bee-5954-813e-73fa1b12497c','37',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f0e2049e-f372-5049-9894-dd8c7be2f7ae','1fb699dc-3bee-5954-813e-73fa1b12497c','42',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a50213bb-2594-5367-9785-ce11104f77e0','1fb699dc-3bee-5954-813e-73fa1b12497c','47',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('d899c48b-a9b6-59ec-8a21-8e1db5f95913','668395b5-5411-5b0b-99a5-5efa80c18faf','0c965966-8a76-5cac-bc5d-0fac4c740c9d','What is 15% of 340?','hard',15,'15% of 340 = 340 × 15/100 = 51.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7f8e2ed6-e5cb-5f3c-b60c-46d22a1ac836','d899c48b-a9b6-59ec-8a21-8e1db5f95913','51',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c08dd58f-e862-552d-be5e-976889324b20','d899c48b-a9b6-59ec-8a21-8e1db5f95913','56',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('04882cd5-b661-5862-a8e9-6b5f56a8e54f','d899c48b-a9b6-59ec-8a21-8e1db5f95913','61',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('07d2416f-611d-59e1-8ae7-c85267c88810','d899c48b-a9b6-59ec-8a21-8e1db5f95913','66',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('fba08c4c-8f7f-51b1-9e22-1834b93f52b6','668395b5-5411-5b0b-99a5-5efa80c18faf','378d3bba-e539-57d4-9450-68034b1df9f7','What is 20% of 360?','easy',15,'20% of 360 = 360 × 20/100 = 72.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('89bea77f-0104-539e-8ed9-2d1b45ea50cd','fba08c4c-8f7f-51b1-9e22-1834b93f52b6','72',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('fc624376-1698-5cdb-914c-0270beed458f','fba08c4c-8f7f-51b1-9e22-1834b93f52b6','77',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('cb975e2e-7e9f-5abe-a4a6-ced16f4c2699','fba08c4c-8f7f-51b1-9e22-1834b93f52b6','82',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4895164b-0cab-5a06-a41b-3f0a958bc88f','fba08c4c-8f7f-51b1-9e22-1834b93f52b6','87',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('a288a953-019f-50b3-8d9c-757cdde47168','668395b5-5411-5b0b-99a5-5efa80c18faf','d8a04e6b-647a-5cfa-b2f2-2fbd91ef400d','What is 25% of 380?','medium',15,'25% of 380 = 380 × 25/100 = 95.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('104fb023-797f-5f88-9bb3-bd2e317a600f','a288a953-019f-50b3-8d9c-757cdde47168','95',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9b00b7ac-4407-5182-8de4-8e35a08467d5','a288a953-019f-50b3-8d9c-757cdde47168','100',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2cdcf05a-e5c5-5a8d-8824-a90b2cb5a674','a288a953-019f-50b3-8d9c-757cdde47168','105',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('338de263-c4f2-5bca-a948-46a8e203b62f','a288a953-019f-50b3-8d9c-757cdde47168','110',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('23f8ae20-412c-527b-8f78-7dee55003476','668395b5-5411-5b0b-99a5-5efa80c18faf','0c965966-8a76-5cac-bc5d-0fac4c740c9d','What is 5% of 400?','easy',15,'5% of 400 = 400 × 5/100 = 20.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('517ee5af-6efa-5b17-b91a-5c4860a451aa','23f8ae20-412c-527b-8f78-7dee55003476','20',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('018bc867-06b2-588c-81da-880f516c01c1','23f8ae20-412c-527b-8f78-7dee55003476','25',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('089b7640-ad72-5e4f-aeb4-f4b5f09ecf2a','23f8ae20-412c-527b-8f78-7dee55003476','30',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('691b0b1f-e8ee-5df4-a482-c963d583c293','23f8ae20-412c-527b-8f78-7dee55003476','35',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('44d8dbef-399b-5e35-af91-e3de2b12088e','668395b5-5411-5b0b-99a5-5efa80c18faf','378d3bba-e539-57d4-9450-68034b1df9f7','What is 10% of 420?','medium',15,'10% of 420 = 420 × 10/100 = 42.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0d54adc8-8bf5-5645-b0c5-36cb9e9befd9','44d8dbef-399b-5e35-af91-e3de2b12088e','42',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a7f9077b-fa32-5f73-a7c0-12c8e6a4f8c9','44d8dbef-399b-5e35-af91-e3de2b12088e','47',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('582d9600-14e3-5564-a385-113f79231fe9','44d8dbef-399b-5e35-af91-e3de2b12088e','52',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('896c6238-dd4b-5252-9176-a84bd87eafb5','44d8dbef-399b-5e35-af91-e3de2b12088e','57',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('fa18402c-000b-5b16-b5c5-fce645967ed8','668395b5-5411-5b0b-99a5-5efa80c18faf','d8a04e6b-647a-5cfa-b2f2-2fbd91ef400d','What is 15% of 440?','hard',15,'15% of 440 = 440 × 15/100 = 66.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('322d7b83-98d8-56c5-8b63-cd0fc91b5b2d','fa18402c-000b-5b16-b5c5-fce645967ed8','66',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8c12f957-9a04-5089-990a-37791e0a7e49','fa18402c-000b-5b16-b5c5-fce645967ed8','71',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('14303c2c-aa9a-5c77-a30c-0c744e8a77aa','fa18402c-000b-5b16-b5c5-fce645967ed8','76',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a1183552-4a84-50b9-8aeb-344da16767e3','fa18402c-000b-5b16-b5c5-fce645967ed8','81',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('9d6f6f8f-6419-583d-b1c4-720f0c8c3b2c','668395b5-5411-5b0b-99a5-5efa80c18faf','0c965966-8a76-5cac-bc5d-0fac4c740c9d','What is 20% of 460?','easy',15,'20% of 460 = 460 × 20/100 = 92.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('cb381376-7801-5863-9b13-22d45238b76f','9d6f6f8f-6419-583d-b1c4-720f0c8c3b2c','92',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1a7921a1-2a28-5eba-b110-f8bc7d365acb','9d6f6f8f-6419-583d-b1c4-720f0c8c3b2c','97',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0c92b65d-83c1-5340-a94d-a97385eb76ed','9d6f6f8f-6419-583d-b1c4-720f0c8c3b2c','102',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('32f9f70b-12e0-5f43-b664-3ab26f37b12b','9d6f6f8f-6419-583d-b1c4-720f0c8c3b2c','107',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('355970ec-c9f5-5828-b645-b55c11144d01','668395b5-5411-5b0b-99a5-5efa80c18faf','378d3bba-e539-57d4-9450-68034b1df9f7','What is 25% of 480?','medium',15,'25% of 480 = 480 × 25/100 = 120.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('83f927c5-a61b-569f-9140-b5f1770dbc83','355970ec-c9f5-5828-b645-b55c11144d01','120',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('577ef2d1-39e0-52e6-8e15-94054faebb3d','355970ec-c9f5-5828-b645-b55c11144d01','125',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9f9b915e-2f4d-5cfb-bf15-c4c4cf3b52fc','355970ec-c9f5-5828-b645-b55c11144d01','130',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6e51883c-fd10-54d2-bc76-dd4301780267','355970ec-c9f5-5828-b645-b55c11144d01','135',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('ad1bfb58-df4e-5fb7-b637-a1de90226bfc','668395b5-5411-5b0b-99a5-5efa80c18faf','d8a04e6b-647a-5cfa-b2f2-2fbd91ef400d','What is 5% of 500?','easy',15,'5% of 500 = 500 × 5/100 = 25.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f9c69995-c6a0-5262-b352-d59d6a218b95','ad1bfb58-df4e-5fb7-b637-a1de90226bfc','25',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9cdc13d0-e29d-5f02-a3b8-c0cebfae68aa','ad1bfb58-df4e-5fb7-b637-a1de90226bfc','30',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('98724017-a106-5abf-91cf-a2d467ef5105','ad1bfb58-df4e-5fb7-b637-a1de90226bfc','35',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('71d67ded-0bd4-50ca-a759-e349231260eb','ad1bfb58-df4e-5fb7-b637-a1de90226bfc','40',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('582e4c52-5c90-5853-9f0a-0781dd5bdd9e','668395b5-5411-5b0b-99a5-5efa80c18faf','0c965966-8a76-5cac-bc5d-0fac4c740c9d','What is 10% of 520?','medium',15,'10% of 520 = 520 × 10/100 = 52.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('958fde50-0a2d-5c7e-a6be-53926e08ecfd','582e4c52-5c90-5853-9f0a-0781dd5bdd9e','52',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2accb85a-3d32-5f16-bb6e-77e77eb5f40b','582e4c52-5c90-5853-9f0a-0781dd5bdd9e','57',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('87ded474-6f39-53c9-be36-5b2a7b3dfb6c','582e4c52-5c90-5853-9f0a-0781dd5bdd9e','62',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8d43b0fb-0e7d-5eac-9e32-8e38b19702e9','582e4c52-5c90-5853-9f0a-0781dd5bdd9e','67',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('c3f6acb0-e6db-5e2f-bd1b-1f7adc7ab16a','668395b5-5411-5b0b-99a5-5efa80c18faf','378d3bba-e539-57d4-9450-68034b1df9f7','What is 15% of 540?','hard',15,'15% of 540 = 540 × 15/100 = 81.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('12cd08f0-2ce0-598f-8289-d0c72bce51b7','c3f6acb0-e6db-5e2f-bd1b-1f7adc7ab16a','81',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4a9c53bd-2277-595b-82b2-5ff16a475fd8','c3f6acb0-e6db-5e2f-bd1b-1f7adc7ab16a','86',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('77569edc-8baf-5578-b97a-2c5c9981158a','c3f6acb0-e6db-5e2f-bd1b-1f7adc7ab16a','91',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c6adb81a-4d9a-5659-8270-637af4be005c','c3f6acb0-e6db-5e2f-bd1b-1f7adc7ab16a','96',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('b5b3b97b-d192-5c3c-a4e4-a6a04cf3bf15','668395b5-5411-5b0b-99a5-5efa80c18faf','d8a04e6b-647a-5cfa-b2f2-2fbd91ef400d','What is 20% of 560?','easy',15,'20% of 560 = 560 × 20/100 = 112.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e642a8b4-f14f-535a-9472-e18427bdd86e','b5b3b97b-d192-5c3c-a4e4-a6a04cf3bf15','112',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7d027b32-d5e1-552f-959e-9706a0ecf11b','b5b3b97b-d192-5c3c-a4e4-a6a04cf3bf15','117',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b0bd7835-6793-5d2f-bd88-2a72be3fa7dd','b5b3b97b-d192-5c3c-a4e4-a6a04cf3bf15','122',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3124bc6f-f5a7-5a8d-88e4-612d569f069f','b5b3b97b-d192-5c3c-a4e4-a6a04cf3bf15','127',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('32c4f672-2f0c-5d86-96ec-1871f215ecc0','668395b5-5411-5b0b-99a5-5efa80c18faf','0c965966-8a76-5cac-bc5d-0fac4c740c9d','What is 25% of 580?','medium',15,'25% of 580 = 580 × 25/100 = 145.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('60c586e5-619a-5663-a1ef-c1e0a77a11a4','32c4f672-2f0c-5d86-96ec-1871f215ecc0','145',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('641ae5fb-ac22-5ca3-b7be-c85005c5a895','32c4f672-2f0c-5d86-96ec-1871f215ecc0','150',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('5c1e6a89-4227-5137-a7dc-a34dffbce183','32c4f672-2f0c-5d86-96ec-1871f215ecc0','155',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0fb01874-b64c-5d45-974f-27e744292d59','32c4f672-2f0c-5d86-96ec-1871f215ecc0','160',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('ab8644be-4431-553a-b443-9d5102ab1516','668395b5-5411-5b0b-99a5-5efa80c18faf','378d3bba-e539-57d4-9450-68034b1df9f7','What is 5% of 600?','easy',15,'5% of 600 = 600 × 5/100 = 30.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ed4fb380-4d65-5957-8f92-fa7f05f5ffd2','ab8644be-4431-553a-b443-9d5102ab1516','30',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6756e9f4-63f1-5182-b2f8-13121a13645f','ab8644be-4431-553a-b443-9d5102ab1516','35',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('90c2292c-c8f3-53f7-8151-ed2d07cda0f8','ab8644be-4431-553a-b443-9d5102ab1516','40',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('85dfbb86-6287-5aef-9c59-ee9fcd2e9fa3','ab8644be-4431-553a-b443-9d5102ab1516','45',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('3e0896c9-b751-5939-85c1-b01cf5a4e21c','668395b5-5411-5b0b-99a5-5efa80c18faf','d8a04e6b-647a-5cfa-b2f2-2fbd91ef400d','What is 10% of 620?','medium',15,'10% of 620 = 620 × 10/100 = 62.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('cb3333d0-5baf-5808-bece-c664b29a4683','3e0896c9-b751-5939-85c1-b01cf5a4e21c','62',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('66ec0084-a088-555a-9136-1cf84dd49ea4','3e0896c9-b751-5939-85c1-b01cf5a4e21c','67',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('cd3926b2-26ad-5508-ab4b-bf9cac348844','3e0896c9-b751-5939-85c1-b01cf5a4e21c','72',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4e6b9e6a-dc7e-547b-8f58-b85f6001f4de','3e0896c9-b751-5939-85c1-b01cf5a4e21c','77',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('a00791e5-a252-5ab6-9501-914ac04cb591','668395b5-5411-5b0b-99a5-5efa80c18faf','0c965966-8a76-5cac-bc5d-0fac4c740c9d','What is 15% of 640?','hard',15,'15% of 640 = 640 × 15/100 = 96.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('444bb62a-6e96-500d-bf05-cf0d43c79048','a00791e5-a252-5ab6-9501-914ac04cb591','96',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c6c803c5-7b01-5596-bec9-598e7eb3c2d3','a00791e5-a252-5ab6-9501-914ac04cb591','101',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8cfa8a97-f31e-520c-a925-afbbe0b73915','a00791e5-a252-5ab6-9501-914ac04cb591','106',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1242b1a5-7e22-5768-8939-5381f00d8b20','a00791e5-a252-5ab6-9501-914ac04cb591','111',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('babba8db-5868-5e39-aaa9-d6a6b1818a1d','668395b5-5411-5b0b-99a5-5efa80c18faf','378d3bba-e539-57d4-9450-68034b1df9f7','What is 20% of 660?','easy',15,'20% of 660 = 660 × 20/100 = 132.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d21ff00f-9aaf-5534-9067-bb1b097cde9e','babba8db-5868-5e39-aaa9-d6a6b1818a1d','132',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('41ed9242-2789-5ba5-9d77-bd60e45d809e','babba8db-5868-5e39-aaa9-d6a6b1818a1d','137',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2de47128-ae30-590f-825b-bbc229f84dd5','babba8db-5868-5e39-aaa9-d6a6b1818a1d','142',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4db935d2-4403-58a3-ada8-70d8d122f7e4','babba8db-5868-5e39-aaa9-d6a6b1818a1d','147',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('2c13c1f7-e4ea-5b16-86e4-a83a369e600c','668395b5-5411-5b0b-99a5-5efa80c18faf','d8a04e6b-647a-5cfa-b2f2-2fbd91ef400d','What is 25% of 680?','medium',15,'25% of 680 = 680 × 25/100 = 170.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8088406f-1f34-52a4-abae-eb44880933a4','2c13c1f7-e4ea-5b16-86e4-a83a369e600c','170',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3d4f9107-3d4c-5f89-8508-818cc179f92d','2c13c1f7-e4ea-5b16-86e4-a83a369e600c','175',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6c27b828-0d7a-5ee2-ab25-bfb9ddd02d2a','2c13c1f7-e4ea-5b16-86e4-a83a369e600c','180',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a7e2bbbc-92b8-5bc4-8ce0-5bbb07464ddd','2c13c1f7-e4ea-5b16-86e4-a83a369e600c','185',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('f3e6b8a8-90de-54ad-9ed2-49e675b85122','668395b5-5411-5b0b-99a5-5efa80c18faf','0c965966-8a76-5cac-bc5d-0fac4c740c9d','What is 5% of 700?','easy',15,'5% of 700 = 700 × 5/100 = 35.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7a8968c6-dc01-5ee3-96b5-50c4c2908ba7','f3e6b8a8-90de-54ad-9ed2-49e675b85122','35',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f57329a4-ca7e-5683-bc0f-ad258efb5dde','f3e6b8a8-90de-54ad-9ed2-49e675b85122','40',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c544237d-0bfd-5286-8389-42bab4c854d7','f3e6b8a8-90de-54ad-9ed2-49e675b85122','45',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('886f2d7d-2dc4-54c7-9dc1-8a8f44e2d544','f3e6b8a8-90de-54ad-9ed2-49e675b85122','50',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('525a7127-95e1-5001-b655-0bf9bb420d4d','668395b5-5411-5b0b-99a5-5efa80c18faf','378d3bba-e539-57d4-9450-68034b1df9f7','What is 10% of 720?','medium',15,'10% of 720 = 720 × 10/100 = 72.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('39c1d88c-047e-511c-8d93-70aab27d2180','525a7127-95e1-5001-b655-0bf9bb420d4d','72',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6ea1756b-1ca7-510b-8666-5c071c4588fc','525a7127-95e1-5001-b655-0bf9bb420d4d','77',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9c67fe34-564c-5584-a9f1-fdd16bb692a6','525a7127-95e1-5001-b655-0bf9bb420d4d','82',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1562a261-5918-53a9-bf0f-c5e464435364','525a7127-95e1-5001-b655-0bf9bb420d4d','87',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('728bd1a3-d12e-5364-a84c-cfb1b46d6d3d','668395b5-5411-5b0b-99a5-5efa80c18faf','d8a04e6b-647a-5cfa-b2f2-2fbd91ef400d','What is 15% of 740?','hard',15,'15% of 740 = 740 × 15/100 = 111.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9c453008-233c-5d39-b6d5-96f70bfc73a0','728bd1a3-d12e-5364-a84c-cfb1b46d6d3d','111',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a8925d0f-3f3c-5281-9ec7-c12e178411fb','728bd1a3-d12e-5364-a84c-cfb1b46d6d3d','116',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('41aca3b5-2272-55ed-9f0f-725061002674','728bd1a3-d12e-5364-a84c-cfb1b46d6d3d','121',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('03e8782a-516b-511f-aa12-a780a5cfde55','728bd1a3-d12e-5364-a84c-cfb1b46d6d3d','126',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('6f18fcdd-f7d9-50d2-827b-510957b80fdc','668395b5-5411-5b0b-99a5-5efa80c18faf','0c965966-8a76-5cac-bc5d-0fac4c740c9d','What is 20% of 760?','easy',15,'20% of 760 = 760 × 20/100 = 152.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1470cf12-9533-5736-9155-79be59f3b252','6f18fcdd-f7d9-50d2-827b-510957b80fdc','152',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7bbb326e-d992-5568-b5aa-d127bb99958d','6f18fcdd-f7d9-50d2-827b-510957b80fdc','157',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('797f0724-370b-5e60-bf7d-737126d2b494','6f18fcdd-f7d9-50d2-827b-510957b80fdc','162',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ab17481a-cee4-5b3b-b8a1-fe83948145a9','6f18fcdd-f7d9-50d2-827b-510957b80fdc','167',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('0fa37ee1-6ce3-50e8-89c3-4f67645ef443','668395b5-5411-5b0b-99a5-5efa80c18faf','378d3bba-e539-57d4-9450-68034b1df9f7','What is 25% of 780?','medium',15,'25% of 780 = 780 × 25/100 = 195.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b76ef405-ba59-569a-9ca1-dc6e56d2f75c','0fa37ee1-6ce3-50e8-89c3-4f67645ef443','195',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e6444905-adb8-5b1e-babe-56aaa9d9ffc5','0fa37ee1-6ce3-50e8-89c3-4f67645ef443','200',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a3a2a389-e158-50ff-9087-3d37d7a1717f','0fa37ee1-6ce3-50e8-89c3-4f67645ef443','205',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f041eca9-d7b6-5615-a626-60b73aa28faf','0fa37ee1-6ce3-50e8-89c3-4f67645ef443','210',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('de208ac8-45e5-5127-b257-14ed581b6f4e','668395b5-5411-5b0b-99a5-5efa80c18faf','d8a04e6b-647a-5cfa-b2f2-2fbd91ef400d','What is 5% of 800?','easy',15,'5% of 800 = 800 × 5/100 = 40.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('191cce85-62c9-52c9-a452-06867eefcd15','de208ac8-45e5-5127-b257-14ed581b6f4e','40',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('55db15b3-27a0-5cbb-b588-8bf2c1f86605','de208ac8-45e5-5127-b257-14ed581b6f4e','45',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e7c6dd04-e1d0-5756-a8e0-d36fe7effab2','de208ac8-45e5-5127-b257-14ed581b6f4e','50',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3f511487-985e-53b9-9701-d4f2e1f5efba','de208ac8-45e5-5127-b257-14ed581b6f4e','55',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('631b052e-8067-5d2e-a180-7602c89c7e04','668395b5-5411-5b0b-99a5-5efa80c18faf','0c965966-8a76-5cac-bc5d-0fac4c740c9d','What is 10% of 820?','medium',15,'10% of 820 = 820 × 10/100 = 82.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('312e94cb-b119-51c9-86f9-e833e135edf1','631b052e-8067-5d2e-a180-7602c89c7e04','82',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c9f84955-a594-5a7f-9a55-a1712265ce44','631b052e-8067-5d2e-a180-7602c89c7e04','87',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f2b925b1-90a6-5670-9262-27b2591a8ec7','631b052e-8067-5d2e-a180-7602c89c7e04','92',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e77e6b09-d45d-5ce4-8eba-dfecd0328352','631b052e-8067-5d2e-a180-7602c89c7e04','97',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('849681c3-c7bf-5b18-8323-6d9ec5cba50d','668395b5-5411-5b0b-99a5-5efa80c18faf','378d3bba-e539-57d4-9450-68034b1df9f7','What is 15% of 840?','hard',15,'15% of 840 = 840 × 15/100 = 126.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('aaa715f5-b5c4-5563-bc11-6fa578521bcf','849681c3-c7bf-5b18-8323-6d9ec5cba50d','126',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('78fabaa5-9e38-5d51-9097-1f79eac22b8e','849681c3-c7bf-5b18-8323-6d9ec5cba50d','131',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f5efc4c2-12e5-5f6b-a154-9240b47c6f9c','849681c3-c7bf-5b18-8323-6d9ec5cba50d','136',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('59f335ad-2726-515c-9f2b-f377d1349d91','849681c3-c7bf-5b18-8323-6d9ec5cba50d','141',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('f0954a9f-fdc3-5c66-9e32-1bffd92e8b93','668395b5-5411-5b0b-99a5-5efa80c18faf','d8a04e6b-647a-5cfa-b2f2-2fbd91ef400d','What is 20% of 860?','easy',15,'20% of 860 = 860 × 20/100 = 172.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9d8052d8-2102-511e-a30f-73605f5dcf3d','f0954a9f-fdc3-5c66-9e32-1bffd92e8b93','172',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4c77eb56-c089-5300-8ddf-7300ed360b7a','f0954a9f-fdc3-5c66-9e32-1bffd92e8b93','177',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('085a8464-0144-592a-9dc6-322e7faa17db','f0954a9f-fdc3-5c66-9e32-1bffd92e8b93','182',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d53a7472-bede-5bbb-b0ec-d9db85480de1','f0954a9f-fdc3-5c66-9e32-1bffd92e8b93','187',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('cef8e321-d613-5208-aedb-b94dfa25fdc8','668395b5-5411-5b0b-99a5-5efa80c18faf','0c965966-8a76-5cac-bc5d-0fac4c740c9d','What is 25% of 880?','medium',15,'25% of 880 = 880 × 25/100 = 220.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('bf368852-4684-57b3-85e2-d18d4f6cf5c3','cef8e321-d613-5208-aedb-b94dfa25fdc8','220',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ff7f6f1c-6003-5695-85da-61fe35fb2edd','cef8e321-d613-5208-aedb-b94dfa25fdc8','225',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('28b49872-358e-5c70-a932-a4cbd3b934cf','cef8e321-d613-5208-aedb-b94dfa25fdc8','230',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4e17cff6-3e86-55be-9ea9-0ec93aa5c753','cef8e321-d613-5208-aedb-b94dfa25fdc8','235',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('7f7cf251-b2ac-5a18-b8ad-9a52eae8787a','09f88e78-88be-547c-9eb8-ef644b66db02','07408f66-e1b7-5ee6-81b0-ff377f4d0a76','Find the next number: 2, 5, 8, 11, …','easy',15,'The sequence increases by 3 each time. 11 + 3 = 14.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f4a72d5b-d874-5f2f-b0f8-d644ef8af5b4','7f7cf251-b2ac-5a18-b8ad-9a52eae8787a','14',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8b02a05a-0ee1-59e1-982f-ae4a0ff778d5','7f7cf251-b2ac-5a18-b8ad-9a52eae8787a','15',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('dcdbe6f2-317e-5ba2-8831-0c6049e4e056','7f7cf251-b2ac-5a18-b8ad-9a52eae8787a','17',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d5a74940-5023-5344-97be-556421c6f960','7f7cf251-b2ac-5a18-b8ad-9a52eae8787a','20',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('0683bf37-9da7-568b-a1fe-ed1a49f4809b','09f88e78-88be-547c-9eb8-ef644b66db02','be920bfe-9ab3-5311-b419-1385df5f325e','Find the next number: 3, 7, 11, 15, …','medium',15,'The sequence increases by 4 each time. 15 + 4 = 19.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0b58d54f-682d-5c1a-87df-2fcdbdebdf31','0683bf37-9da7-568b-a1fe-ed1a49f4809b','19',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1e6b1e6e-c891-5c1d-bf73-5c3ea56c4935','0683bf37-9da7-568b-a1fe-ed1a49f4809b','20',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('effe2e20-1288-5d1f-bae7-f55424fdd45c','0683bf37-9da7-568b-a1fe-ed1a49f4809b','23',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9f8650c7-afde-5407-9cd8-fdf3dd412ac5','0683bf37-9da7-568b-a1fe-ed1a49f4809b','27',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('bd410340-d375-5512-b181-1aef03081124','09f88e78-88be-547c-9eb8-ef644b66db02','263a42f4-b1ed-5327-90c0-cd36ab8eb9f3','Find the next number: 4, 9, 14, 19, …','hard',15,'The sequence increases by 5 each time. 19 + 5 = 24.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2f61abeb-73cd-5f05-8d9d-eb3331d7d92e','bd410340-d375-5512-b181-1aef03081124','24',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6d532802-e751-5fa1-bfee-95d052c3c15e','bd410340-d375-5512-b181-1aef03081124','25',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4a811597-33ff-524b-8c3a-9de43d12fa85','bd410340-d375-5512-b181-1aef03081124','29',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('bd52aab6-ca68-5f5a-a2c2-916311d5d4e8','bd410340-d375-5512-b181-1aef03081124','34',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('11d8ca13-c571-517e-8c31-11ba92a0bf6a','09f88e78-88be-547c-9eb8-ef644b66db02','07408f66-e1b7-5ee6-81b0-ff377f4d0a76','Find the next number: 5, 11, 17, 23, …','easy',15,'The sequence increases by 6 each time. 23 + 6 = 29.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7c7ed977-6dbd-5298-9d5e-845164430aa1','11d8ca13-c571-517e-8c31-11ba92a0bf6a','29',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('30c050ed-4c4f-5e29-87fa-1267071f9ca7','11d8ca13-c571-517e-8c31-11ba92a0bf6a','30',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a0fa3d0b-4490-5983-824a-089e997b2bbd','11d8ca13-c571-517e-8c31-11ba92a0bf6a','35',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('615e00e3-9ef6-514d-a14e-d85b9510c49d','11d8ca13-c571-517e-8c31-11ba92a0bf6a','41',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('ec3f226a-f3a2-5bc2-9ed3-f55bd1edec15','09f88e78-88be-547c-9eb8-ef644b66db02','be920bfe-9ab3-5311-b419-1385df5f325e','Find the next number: 6, 13, 20, 27, …','medium',15,'The sequence increases by 7 each time. 27 + 7 = 34.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e4b31166-0b47-5d7d-bdbe-1b6dad257bac','ec3f226a-f3a2-5bc2-9ed3-f55bd1edec15','34',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('96207d4b-8a9e-5357-8399-e8585506f199','ec3f226a-f3a2-5bc2-9ed3-f55bd1edec15','35',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('07da9305-b30e-5679-8a17-185bb63b99e3','ec3f226a-f3a2-5bc2-9ed3-f55bd1edec15','41',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('829ab593-fefd-5e8b-af44-d67e399b1be1','ec3f226a-f3a2-5bc2-9ed3-f55bd1edec15','48',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('d8f1ab31-1733-57c7-a017-e04fc93e6ecc','09f88e78-88be-547c-9eb8-ef644b66db02','263a42f4-b1ed-5327-90c0-cd36ab8eb9f3','Find the next number: 7, 15, 23, 31, …','easy',15,'The sequence increases by 8 each time. 31 + 8 = 39.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0b23da9b-2497-5cf9-b2f0-6d6daa6ea740','d8f1ab31-1733-57c7-a017-e04fc93e6ecc','39',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('083822c4-a920-5cb4-b11d-b929a8c0a206','d8f1ab31-1733-57c7-a017-e04fc93e6ecc','40',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e9ca44bf-77fb-54dc-b10e-2c83113cf7a2','d8f1ab31-1733-57c7-a017-e04fc93e6ecc','47',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('16c70617-36b4-55ec-8f03-30b5158afd57','d8f1ab31-1733-57c7-a017-e04fc93e6ecc','55',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('de44f911-5e8e-50e3-861b-6ac0dc979ad4','09f88e78-88be-547c-9eb8-ef644b66db02','07408f66-e1b7-5ee6-81b0-ff377f4d0a76','Find the next number: 8, 17, 26, 35, …','medium',15,'The sequence increases by 9 each time. 35 + 9 = 44.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('07305f08-6bc3-5cfc-bc85-2277f5ebb3f6','de44f911-5e8e-50e3-861b-6ac0dc979ad4','44',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('df4cc31f-1c60-530b-a910-218e8de13190','de44f911-5e8e-50e3-861b-6ac0dc979ad4','45',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ef35e5d8-95e6-5fe1-81ba-1494ad76bb11','de44f911-5e8e-50e3-861b-6ac0dc979ad4','53',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('84d31a3d-8a99-5681-9508-b30ab4ece474','de44f911-5e8e-50e3-861b-6ac0dc979ad4','62',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('89185c7d-d8eb-5a20-9c26-7645effee657','09f88e78-88be-547c-9eb8-ef644b66db02','be920bfe-9ab3-5311-b419-1385df5f325e','Find the next number: 9, 12, 15, 18, …','hard',15,'The sequence increases by 3 each time. 18 + 3 = 21.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ec6648e5-41ae-57d0-b5b4-d4427e979020','89185c7d-d8eb-5a20-9c26-7645effee657','21',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('34511942-44ba-5904-a87d-e7a450627bc3','89185c7d-d8eb-5a20-9c26-7645effee657','22',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2b2c3d5b-67d9-5f79-b678-07c8107ea81e','89185c7d-d8eb-5a20-9c26-7645effee657','24',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c0113567-7a7b-597c-8c17-05a79b7706c4','89185c7d-d8eb-5a20-9c26-7645effee657','27',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('5a359e98-2fbf-5307-837b-0f6476f169ec','09f88e78-88be-547c-9eb8-ef644b66db02','263a42f4-b1ed-5327-90c0-cd36ab8eb9f3','Find the next number: 10, 14, 18, 22, …','easy',15,'The sequence increases by 4 each time. 22 + 4 = 26.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6335b1af-449c-543e-ae6c-6997397466bc','5a359e98-2fbf-5307-837b-0f6476f169ec','26',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4a5a72e3-a815-516f-8d15-8e07c363b2bd','5a359e98-2fbf-5307-837b-0f6476f169ec','27',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('592f0c20-8dc7-5f8e-9e8f-ed49606b7139','5a359e98-2fbf-5307-837b-0f6476f169ec','30',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('29b0574c-abbf-5ec1-9473-68cc57c2a31c','5a359e98-2fbf-5307-837b-0f6476f169ec','34',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('ab1a4597-f02e-5e00-8e07-20c1b226af81','09f88e78-88be-547c-9eb8-ef644b66db02','07408f66-e1b7-5ee6-81b0-ff377f4d0a76','Find the next number: 11, 16, 21, 26, …','medium',15,'The sequence increases by 5 each time. 26 + 5 = 31.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d7b20712-0ffc-5844-9fb2-39db79fd532a','ab1a4597-f02e-5e00-8e07-20c1b226af81','31',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('814b6971-dc24-5d9c-a630-4f0ef3ff8473','ab1a4597-f02e-5e00-8e07-20c1b226af81','32',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b01c3125-0787-5c3d-9672-a53450b80d18','ab1a4597-f02e-5e00-8e07-20c1b226af81','36',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('5593cb56-4bcc-5f78-9346-aac487603d1e','ab1a4597-f02e-5e00-8e07-20c1b226af81','41',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('b57430f1-1ca5-50cf-896c-e931c8078243','09f88e78-88be-547c-9eb8-ef644b66db02','be920bfe-9ab3-5311-b419-1385df5f325e','Find the next number: 12, 18, 24, 30, …','easy',15,'The sequence increases by 6 each time. 30 + 6 = 36.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3f50995b-ab2e-565f-bf76-1731ee7ab15b','b57430f1-1ca5-50cf-896c-e931c8078243','36',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ff0eaa34-970a-568d-8e7f-0384445ccc32','b57430f1-1ca5-50cf-896c-e931c8078243','37',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('01d136b6-adeb-5be2-86e5-7cbca0e74471','b57430f1-1ca5-50cf-896c-e931c8078243','42',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0b85fc91-09eb-5a4d-98aa-7b2dde2ec97b','b57430f1-1ca5-50cf-896c-e931c8078243','48',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('2fec180d-917a-55f0-86f1-70c35dc2a7aa','09f88e78-88be-547c-9eb8-ef644b66db02','263a42f4-b1ed-5327-90c0-cd36ab8eb9f3','Find the next number: 13, 20, 27, 34, …','medium',15,'The sequence increases by 7 each time. 34 + 7 = 41.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6e5b8ae7-a429-5c10-a1b2-3dd5741dc7cc','2fec180d-917a-55f0-86f1-70c35dc2a7aa','41',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4355c92b-4d8f-5082-b6b5-142b6062d25e','2fec180d-917a-55f0-86f1-70c35dc2a7aa','42',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('94c4f78b-649d-5495-b1c4-1d01426ec2fe','2fec180d-917a-55f0-86f1-70c35dc2a7aa','48',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('092c0aa6-57e6-599f-9653-80b5d095d5dd','2fec180d-917a-55f0-86f1-70c35dc2a7aa','55',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('b2c167d7-7e5d-5c83-b936-5fc37b3012d2','09f88e78-88be-547c-9eb8-ef644b66db02','07408f66-e1b7-5ee6-81b0-ff377f4d0a76','Find the next number: 14, 22, 30, 38, …','hard',15,'The sequence increases by 8 each time. 38 + 8 = 46.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('de33708d-57f7-5ff4-a6eb-d8011e0aafcb','b2c167d7-7e5d-5c83-b936-5fc37b3012d2','46',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d7fe2b93-fc99-5f32-990c-c2af72373a1e','b2c167d7-7e5d-5c83-b936-5fc37b3012d2','47',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('12f73a66-8263-54bc-beaf-192b5a7f94bd','b2c167d7-7e5d-5c83-b936-5fc37b3012d2','54',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a8c5da3d-07b6-5332-b8f8-143cc4aaa34f','b2c167d7-7e5d-5c83-b936-5fc37b3012d2','62',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('4b0617e1-43d8-5da4-ae9e-1258742f90fc','09f88e78-88be-547c-9eb8-ef644b66db02','be920bfe-9ab3-5311-b419-1385df5f325e','Find the next number: 15, 24, 33, 42, …','easy',15,'The sequence increases by 9 each time. 42 + 9 = 51.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ed4a6377-3244-51d6-8109-fa560457d4b8','4b0617e1-43d8-5da4-ae9e-1258742f90fc','51',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0593e36c-f36f-5a16-a489-cb8cd852e1ef','4b0617e1-43d8-5da4-ae9e-1258742f90fc','52',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2e06c614-36f6-5cc2-a213-fcc94e484642','4b0617e1-43d8-5da4-ae9e-1258742f90fc','60',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1354968b-ff3f-5caf-a20b-fd6501b51920','4b0617e1-43d8-5da4-ae9e-1258742f90fc','69',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('e42d1062-e8de-5425-b76c-cb06cd61fbaa','09f88e78-88be-547c-9eb8-ef644b66db02','263a42f4-b1ed-5327-90c0-cd36ab8eb9f3','Find the next number: 16, 19, 22, 25, …','medium',15,'The sequence increases by 3 each time. 25 + 3 = 28.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('301d45b3-5edd-5b1a-9b4d-9798ba966db8','e42d1062-e8de-5425-b76c-cb06cd61fbaa','28',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6af0afbd-81de-5b51-b1d4-9a5ee60aafb3','e42d1062-e8de-5425-b76c-cb06cd61fbaa','29',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('cc3ce869-f081-5612-b245-68b41c11e40a','e42d1062-e8de-5425-b76c-cb06cd61fbaa','31',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('68b393fc-6340-5303-a594-0b6381e7aa19','e42d1062-e8de-5425-b76c-cb06cd61fbaa','34',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('31939858-c918-5eb1-8dd0-50a2ad0adbc3','09f88e78-88be-547c-9eb8-ef644b66db02','07408f66-e1b7-5ee6-81b0-ff377f4d0a76','Find the next number: 17, 21, 25, 29, …','easy',15,'The sequence increases by 4 each time. 29 + 4 = 33.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('03c8d777-a2c3-5c46-9647-ea7f4f04f15b','31939858-c918-5eb1-8dd0-50a2ad0adbc3','33',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b7ad0ebf-c3b7-528b-bae3-d5639a743877','31939858-c918-5eb1-8dd0-50a2ad0adbc3','34',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9f0aa02a-324c-51ea-8669-3ca005d0afd5','31939858-c918-5eb1-8dd0-50a2ad0adbc3','37',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6171fb21-6d1e-5793-a03a-271bfd5ae8f2','31939858-c918-5eb1-8dd0-50a2ad0adbc3','41',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('2fa57590-e305-5ec2-93db-9f50ec61a133','09f88e78-88be-547c-9eb8-ef644b66db02','be920bfe-9ab3-5311-b419-1385df5f325e','Find the next number: 18, 23, 28, 33, …','medium',15,'The sequence increases by 5 each time. 33 + 5 = 38.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4d12b5be-5c4b-5d50-b2cd-faeca07c13a7','2fa57590-e305-5ec2-93db-9f50ec61a133','38',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('416877dd-b168-5a65-871a-2938cd799c33','2fa57590-e305-5ec2-93db-9f50ec61a133','39',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0d69885f-9518-51a3-a5ca-cd4452b2eeda','2fa57590-e305-5ec2-93db-9f50ec61a133','43',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('91fa3e7f-3c99-57d4-b875-bcc2a91b5ebf','2fa57590-e305-5ec2-93db-9f50ec61a133','48',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('1428bc50-400d-5b43-92b2-ba3177cf4259','09f88e78-88be-547c-9eb8-ef644b66db02','263a42f4-b1ed-5327-90c0-cd36ab8eb9f3','Find the next number: 19, 25, 31, 37, …','hard',15,'The sequence increases by 6 each time. 37 + 6 = 43.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('33475b4d-fc47-5dfd-8cc6-9d7dceea3d5b','1428bc50-400d-5b43-92b2-ba3177cf4259','43',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('770e2d28-0a41-5f1e-917f-04207b98b359','1428bc50-400d-5b43-92b2-ba3177cf4259','44',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('bbb70959-1830-528c-9a36-9fafcbb631f8','1428bc50-400d-5b43-92b2-ba3177cf4259','49',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6dde3b89-7733-53dc-bd7d-229eb2cbe7ec','1428bc50-400d-5b43-92b2-ba3177cf4259','55',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('1bc98b82-3b34-5ab0-9e9b-bededb96969f','09f88e78-88be-547c-9eb8-ef644b66db02','07408f66-e1b7-5ee6-81b0-ff377f4d0a76','Find the next number: 20, 27, 34, 41, …','easy',15,'The sequence increases by 7 each time. 41 + 7 = 48.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4b789c3e-fcea-56a7-a359-b010c2b68bcb','1bc98b82-3b34-5ab0-9e9b-bededb96969f','48',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d49a7923-2fec-5595-ad44-20287646143f','1bc98b82-3b34-5ab0-9e9b-bededb96969f','49',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d00eb15d-5610-5cc8-b65e-7be00ac9025c','1bc98b82-3b34-5ab0-9e9b-bededb96969f','55',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('bc0ec134-c32e-58a6-9ef8-6f194ebebaff','1bc98b82-3b34-5ab0-9e9b-bededb96969f','62',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('d952e219-253e-5b2c-a440-a8ed7de11330','09f88e78-88be-547c-9eb8-ef644b66db02','be920bfe-9ab3-5311-b419-1385df5f325e','Find the next number: 21, 29, 37, 45, …','medium',15,'The sequence increases by 8 each time. 45 + 8 = 53.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('17450c72-eccb-5bcc-95b0-27d2ae806aef','d952e219-253e-5b2c-a440-a8ed7de11330','53',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d20ad4f2-a892-5434-a741-0446c04f95a9','d952e219-253e-5b2c-a440-a8ed7de11330','54',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0fa14d9a-9d80-5515-9b4e-948d8455a7d1','d952e219-253e-5b2c-a440-a8ed7de11330','61',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e521cb45-a628-5f0b-b273-e5ad17c9132a','d952e219-253e-5b2c-a440-a8ed7de11330','69',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('a62a67d6-6241-5a07-a63c-b64b47840a45','09f88e78-88be-547c-9eb8-ef644b66db02','263a42f4-b1ed-5327-90c0-cd36ab8eb9f3','Find the next number: 22, 31, 40, 49, …','easy',15,'The sequence increases by 9 each time. 49 + 9 = 58.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f5514581-8a0d-52e7-8452-cc73b358e393','a62a67d6-6241-5a07-a63c-b64b47840a45','58',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('314457dd-6d02-57c1-afa8-167a75531fd3','a62a67d6-6241-5a07-a63c-b64b47840a45','59',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b5268d76-2e6b-5402-ae48-5d09944a9052','a62a67d6-6241-5a07-a63c-b64b47840a45','67',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2efaa4f4-d5a7-54eb-9b83-065e64d499e9','a62a67d6-6241-5a07-a63c-b64b47840a45','76',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('9542eed0-61bc-5b44-ba50-6476220a2772','09f88e78-88be-547c-9eb8-ef644b66db02','07408f66-e1b7-5ee6-81b0-ff377f4d0a76','Find the next number: 23, 26, 29, 32, …','medium',15,'The sequence increases by 3 each time. 32 + 3 = 35.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c6a3a275-3bc5-5b80-820e-2b6564e1ea3b','9542eed0-61bc-5b44-ba50-6476220a2772','35',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6b9317b4-f463-561a-93c1-fafe67e21ad4','9542eed0-61bc-5b44-ba50-6476220a2772','36',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('41185c0d-f983-56dc-a8ae-c1c33616b27b','9542eed0-61bc-5b44-ba50-6476220a2772','38',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b146a20d-345f-5d00-948d-cfdfb9e84228','9542eed0-61bc-5b44-ba50-6476220a2772','41',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('b95dfbec-d585-5de5-8f5d-b309f512313c','09f88e78-88be-547c-9eb8-ef644b66db02','be920bfe-9ab3-5311-b419-1385df5f325e','Find the next number: 24, 28, 32, 36, …','hard',15,'The sequence increases by 4 each time. 36 + 4 = 40.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f42387c9-6457-5622-96c9-0f218bc50ee2','b95dfbec-d585-5de5-8f5d-b309f512313c','40',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8cdc2857-0b4e-5f4e-897c-a73b47cd9f06','b95dfbec-d585-5de5-8f5d-b309f512313c','41',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0721bea2-3442-532e-abc4-f7895ad54b57','b95dfbec-d585-5de5-8f5d-b309f512313c','44',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('490ec38a-4fbd-5eab-88c2-eec908b28796','b95dfbec-d585-5de5-8f5d-b309f512313c','48',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('5a252901-39ed-5d58-be16-9e2e72d3ad37','09f88e78-88be-547c-9eb8-ef644b66db02','263a42f4-b1ed-5327-90c0-cd36ab8eb9f3','Find the next number: 25, 30, 35, 40, …','easy',15,'The sequence increases by 5 each time. 40 + 5 = 45.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3f04c7cd-11bc-5cef-9d04-b01c996a1ab6','5a252901-39ed-5d58-be16-9e2e72d3ad37','45',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b6c81465-5b82-57a2-812e-0f35d9d8682c','5a252901-39ed-5d58-be16-9e2e72d3ad37','46',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d7ff381e-02e2-5214-8db1-d299b126bf42','5a252901-39ed-5d58-be16-9e2e72d3ad37','50',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('5656e7ad-4e86-5c22-9b30-7794b5e37627','5a252901-39ed-5d58-be16-9e2e72d3ad37','55',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('52716646-6913-5251-838b-b49f5b4e2a5b','09f88e78-88be-547c-9eb8-ef644b66db02','07408f66-e1b7-5ee6-81b0-ff377f4d0a76','Find the next number: 26, 32, 38, 44, …','medium',15,'The sequence increases by 6 each time. 44 + 6 = 50.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0dfd03fc-2285-52ec-8581-70fc41ba6c1a','52716646-6913-5251-838b-b49f5b4e2a5b','50',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ff8e5a81-9aec-5c44-ac0b-d06fb904fff1','52716646-6913-5251-838b-b49f5b4e2a5b','51',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1f6251b8-9ec8-52b1-b416-7d0e6c9c0cc0','52716646-6913-5251-838b-b49f5b4e2a5b','56',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('41afa070-e996-5657-9aa8-969a00f040a7','52716646-6913-5251-838b-b49f5b4e2a5b','62',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('de564f9d-4e26-5968-bf2a-6065b8567950','09f88e78-88be-547c-9eb8-ef644b66db02','be920bfe-9ab3-5311-b419-1385df5f325e','Find the next number: 27, 34, 41, 48, …','easy',15,'The sequence increases by 7 each time. 48 + 7 = 55.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('15282ef0-2873-53f1-bc35-5c1670e0685c','de564f9d-4e26-5968-bf2a-6065b8567950','55',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c690e055-ef03-5942-a645-d0e11d831ff0','de564f9d-4e26-5968-bf2a-6065b8567950','56',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b59e934a-9b52-5a71-8873-376b88fcffa7','de564f9d-4e26-5968-bf2a-6065b8567950','62',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('77f0ea24-f1b6-5f89-8599-042e14e92b65','de564f9d-4e26-5968-bf2a-6065b8567950','69',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('2a15025d-801b-5915-ad91-8aa6ab74a0cf','09f88e78-88be-547c-9eb8-ef644b66db02','263a42f4-b1ed-5327-90c0-cd36ab8eb9f3','Find the next number: 28, 36, 44, 52, …','medium',15,'The sequence increases by 8 each time. 52 + 8 = 60.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9e1b94c3-acc8-5d29-9aba-512081657dbd','2a15025d-801b-5915-ad91-8aa6ab74a0cf','60',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ca9a087f-eb46-56f2-a388-dba57d23b840','2a15025d-801b-5915-ad91-8aa6ab74a0cf','61',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a349d82e-d524-52e2-b08d-2065c3d70209','2a15025d-801b-5915-ad91-8aa6ab74a0cf','68',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('24566869-1014-5798-bd98-a376d4998478','2a15025d-801b-5915-ad91-8aa6ab74a0cf','76',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('180da965-00a2-5e20-a78a-6d972a633dae','09f88e78-88be-547c-9eb8-ef644b66db02','07408f66-e1b7-5ee6-81b0-ff377f4d0a76','Find the next number: 29, 38, 47, 56, …','hard',15,'The sequence increases by 9 each time. 56 + 9 = 65.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('98fc6c6a-5592-5e99-9201-faaf8b16e2e4','180da965-00a2-5e20-a78a-6d972a633dae','65',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ba12e9a0-5781-5bf9-9ab3-9cf0e52656e6','180da965-00a2-5e20-a78a-6d972a633dae','66',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('273802c1-198e-57d5-8a60-c23028da49e7','180da965-00a2-5e20-a78a-6d972a633dae','74',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('39f3dbb2-4490-55ca-8389-32aeb663bdbb','180da965-00a2-5e20-a78a-6d972a633dae','83',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('dbce3cfe-c1a9-534f-9d94-f7bb760d8525','09f88e78-88be-547c-9eb8-ef644b66db02','be920bfe-9ab3-5311-b419-1385df5f325e','Find the next number: 30, 33, 36, 39, …','easy',15,'The sequence increases by 3 each time. 39 + 3 = 42.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a32252da-fe55-534b-ac2a-4e4f98b4981e','dbce3cfe-c1a9-534f-9d94-f7bb760d8525','42',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0732f203-d5ba-5430-b81f-c6ecadeed2c2','dbce3cfe-c1a9-534f-9d94-f7bb760d8525','43',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2df0f697-99b0-5aca-9d1b-9b4a57b0ba81','dbce3cfe-c1a9-534f-9d94-f7bb760d8525','45',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8025914f-629d-504a-acb5-717a7bf87c79','dbce3cfe-c1a9-534f-9d94-f7bb760d8525','48',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('b98d9de9-4c18-595c-8bb5-c0f2bacdef05','09f88e78-88be-547c-9eb8-ef644b66db02','263a42f4-b1ed-5327-90c0-cd36ab8eb9f3','Find the next number: 31, 35, 39, 43, …','medium',15,'The sequence increases by 4 each time. 43 + 4 = 47.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a6a73479-63f0-5117-a0b5-56ced12813e7','b98d9de9-4c18-595c-8bb5-c0f2bacdef05','47',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('06e02e4d-e35e-569f-bfb1-f53dcceb3f90','b98d9de9-4c18-595c-8bb5-c0f2bacdef05','48',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('aa63c6ca-bd33-5d4b-880c-9291055d55ca','b98d9de9-4c18-595c-8bb5-c0f2bacdef05','51',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f675d201-2dcc-58d0-8392-3f000bbcaa11','b98d9de9-4c18-595c-8bb5-c0f2bacdef05','55',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('2841dcd0-006a-5dcf-a23e-7667efa94833','09f88e78-88be-547c-9eb8-ef644b66db02','07408f66-e1b7-5ee6-81b0-ff377f4d0a76','Find the next number: 32, 37, 42, 47, …','easy',15,'The sequence increases by 5 each time. 47 + 5 = 52.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('dff57c40-e702-5e7b-99d5-a45845e9a4fc','2841dcd0-006a-5dcf-a23e-7667efa94833','52',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('fa479051-1b5d-5c2b-baa4-d0ab14a8899d','2841dcd0-006a-5dcf-a23e-7667efa94833','53',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d16681de-55dd-5e69-83c8-d78fc1bd4ce2','2841dcd0-006a-5dcf-a23e-7667efa94833','57',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f50f58ce-1c4d-5174-80be-bde038f95fca','2841dcd0-006a-5dcf-a23e-7667efa94833','62',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('a8bc3b8f-284e-52ce-9b9b-ad51385809ba','09f88e78-88be-547c-9eb8-ef644b66db02','be920bfe-9ab3-5311-b419-1385df5f325e','Find the next number: 33, 39, 45, 51, …','medium',15,'The sequence increases by 6 each time. 51 + 6 = 57.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d0638613-6524-5e3f-a868-0b739b0f7ece','a8bc3b8f-284e-52ce-9b9b-ad51385809ba','57',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('46088f25-6117-5b50-9d52-636c8731abd2','a8bc3b8f-284e-52ce-9b9b-ad51385809ba','58',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('10203650-1419-524e-9ae1-5299fa60c3ad','a8bc3b8f-284e-52ce-9b9b-ad51385809ba','63',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('37d227b5-372b-574d-8fff-eae5de594fc5','a8bc3b8f-284e-52ce-9b9b-ad51385809ba','69',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('e9157207-5a17-5e67-869d-52f0530e623d','09f88e78-88be-547c-9eb8-ef644b66db02','263a42f4-b1ed-5327-90c0-cd36ab8eb9f3','Find the next number: 34, 41, 48, 55, …','hard',15,'The sequence increases by 7 each time. 55 + 7 = 62.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2c9eb755-3ddb-5c2b-81be-70bbfa3aeecd','e9157207-5a17-5e67-869d-52f0530e623d','62',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('78ee520a-fbdd-546f-aec1-47da72ac1f60','e9157207-5a17-5e67-869d-52f0530e623d','63',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a3d879e3-b413-5d6a-b487-e01f8ab95533','e9157207-5a17-5e67-869d-52f0530e623d','69',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8dcc6c2e-7ee6-5f66-942e-0920c6d90a35','e9157207-5a17-5e67-869d-52f0530e623d','76',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('005c2a60-a41e-5b74-9a06-0fd47e1024b6','09f88e78-88be-547c-9eb8-ef644b66db02','07408f66-e1b7-5ee6-81b0-ff377f4d0a76','Find the next number: 35, 43, 51, 59, …','easy',15,'The sequence increases by 8 each time. 59 + 8 = 67.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('85988593-0948-5d76-9069-cc63e0e44313','005c2a60-a41e-5b74-9a06-0fd47e1024b6','67',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a12eeda2-ad33-590d-96d7-964a60bd1e6e','005c2a60-a41e-5b74-9a06-0fd47e1024b6','68',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('534ce7e5-a015-5296-91f3-cc6ce43ca798','005c2a60-a41e-5b74-9a06-0fd47e1024b6','75',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('51f1b48a-fe64-5212-a922-8ce0124a384a','005c2a60-a41e-5b74-9a06-0fd47e1024b6','83',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('f6eaa68d-c73f-5edf-9109-d057896134ae','09f88e78-88be-547c-9eb8-ef644b66db02','be920bfe-9ab3-5311-b419-1385df5f325e','Find the next number: 36, 45, 54, 63, …','medium',15,'The sequence increases by 9 each time. 63 + 9 = 72.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('da8ece94-2bfd-5f2c-8f22-74a24b38d685','f6eaa68d-c73f-5edf-9109-d057896134ae','72',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2e2787c3-fe59-5792-a066-e11b8817838e','f6eaa68d-c73f-5edf-9109-d057896134ae','73',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7355d825-bd99-563a-b810-fdd986027cc0','f6eaa68d-c73f-5edf-9109-d057896134ae','81',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6f3e3039-2016-5c3d-b804-9e2e5253f26a','f6eaa68d-c73f-5edf-9109-d057896134ae','90',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('16d5a70d-2623-5f2b-b0bc-e1989585a2d4','09f88e78-88be-547c-9eb8-ef644b66db02','263a42f4-b1ed-5327-90c0-cd36ab8eb9f3','Find the next number: 37, 40, 43, 46, …','easy',15,'The sequence increases by 3 each time. 46 + 3 = 49.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a98b70a0-6e38-5789-a9f3-ffe86a8b595c','16d5a70d-2623-5f2b-b0bc-e1989585a2d4','49',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6db93865-b45c-555d-ab2f-b57861a3aa71','16d5a70d-2623-5f2b-b0bc-e1989585a2d4','50',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('30133504-8228-575a-9a8b-53188ae491f8','16d5a70d-2623-5f2b-b0bc-e1989585a2d4','52',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f52b98da-2aab-53ba-ad84-fe89892a630b','16d5a70d-2623-5f2b-b0bc-e1989585a2d4','55',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('f8155e2b-abca-5351-b516-a63c4384bb76','09f88e78-88be-547c-9eb8-ef644b66db02','07408f66-e1b7-5ee6-81b0-ff377f4d0a76','Find the next number: 38, 42, 46, 50, …','medium',15,'The sequence increases by 4 each time. 50 + 4 = 54.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e265c807-7b46-5a76-bc98-8c69f7d60093','f8155e2b-abca-5351-b516-a63c4384bb76','54',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4b71cc2d-9e9d-5fea-a56e-e57080324329','f8155e2b-abca-5351-b516-a63c4384bb76','55',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('690f5819-2ebd-5256-8838-9d8819f0a2a7','f8155e2b-abca-5351-b516-a63c4384bb76','58',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('5fcfcf39-7702-5432-a41a-525fb72164ff','f8155e2b-abca-5351-b516-a63c4384bb76','62',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('e900d2b9-74d9-5609-a867-b3f56408e3ff','09f88e78-88be-547c-9eb8-ef644b66db02','be920bfe-9ab3-5311-b419-1385df5f325e','Find the next number: 39, 44, 49, 54, …','hard',15,'The sequence increases by 5 each time. 54 + 5 = 59.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4354851f-eff1-5b5d-9305-4e32b3560fbc','e900d2b9-74d9-5609-a867-b3f56408e3ff','59',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('946c3027-71d3-5593-86cd-352918558013','e900d2b9-74d9-5609-a867-b3f56408e3ff','60',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b093845d-37be-5bb3-9597-68b3111cd469','e900d2b9-74d9-5609-a867-b3f56408e3ff','64',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('83f4d67d-17fa-5a00-a086-14ae3ce5ffb2','e900d2b9-74d9-5609-a867-b3f56408e3ff','69',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('3e5e1e3c-408a-5ced-b9d9-207d90084e29','09f88e78-88be-547c-9eb8-ef644b66db02','263a42f4-b1ed-5327-90c0-cd36ab8eb9f3','Find the next number: 40, 46, 52, 58, …','easy',15,'The sequence increases by 6 each time. 58 + 6 = 64.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('cda443e6-1f7c-58e1-a8d6-a9079b1cfb58','3e5e1e3c-408a-5ced-b9d9-207d90084e29','64',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a2a8f7ef-d2cc-5b84-a7ab-76711ef7ce1f','3e5e1e3c-408a-5ced-b9d9-207d90084e29','65',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('69d541e9-3226-5d13-a9b0-c1ac40db081d','3e5e1e3c-408a-5ced-b9d9-207d90084e29','70',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('52ee54b5-2dd6-50c1-ba14-3e1daa307210','3e5e1e3c-408a-5ced-b9d9-207d90084e29','76',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('4823d918-68b8-5ecf-a4b3-106889d801ef','09f88e78-88be-547c-9eb8-ef644b66db02','07408f66-e1b7-5ee6-81b0-ff377f4d0a76','Find the next number: 41, 48, 55, 62, …','medium',15,'The sequence increases by 7 each time. 62 + 7 = 69.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c3f1b980-03aa-50e5-b295-c43a282461ab','4823d918-68b8-5ecf-a4b3-106889d801ef','69',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('af209c3c-d1ad-5d64-a978-a32178d60776','4823d918-68b8-5ecf-a4b3-106889d801ef','70',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2ba8c7e4-6a82-5cee-8f43-b7fb7bb71e53','4823d918-68b8-5ecf-a4b3-106889d801ef','76',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('98f08e1d-34b9-5fed-84a8-f111a4134f32','4823d918-68b8-5ecf-a4b3-106889d801ef','83',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('878842c8-12c7-577c-9102-9939e149bca8','d2c9217b-d3a7-5a4a-9815-c33704a25aff','15ce5c00-e6c7-57c7-90b8-666779e61e99','Choose the word closest in meaning to “abundant”.','easy',15,'“Abundant” means plentiful.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1e7e230a-9238-530a-a9ed-9a5be5bdad92','878842c8-12c7-577c-9102-9939e149bca8','Plentiful',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2529e6de-3f17-545e-aa19-3727a037b90f','878842c8-12c7-577c-9102-9939e149bca8','Capable',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d657acdc-6dba-591e-93c5-a1e62ed4daa1','878842c8-12c7-577c-9102-9939e149bca8','Unfriendly',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f4d40354-ae52-5b83-bd00-08b29225a304','878842c8-12c7-577c-9102-9939e149bca8','Beginner',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('4cd85b16-10cc-50b0-9737-493e85aeb030','d2c9217b-d3a7-5a4a-9815-c33704a25aff','acf1d39a-0793-5fc6-b20e-ababc6f69306','Choose the word closest in meaning to “accurate”.','medium',15,'“Accurate” means precise.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('03a04fd3-ffda-551f-8cc2-d310c6934947','4cd85b16-10cc-50b0-9737-493e85aeb030','Precise',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8b59cb1f-132d-5d2a-875d-69e5f30e2a4f','4cd85b16-10cc-50b0-9737-493e85aeb030','Hardworking',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('cec74169-6beb-5496-9211-1e8ba4f1b7b4','4cd85b16-10cc-50b0-9737-493e85aeb030','Modest',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('da402099-7b8d-5ef1-bf5b-6677a8bf5073','4cd85b16-10cc-50b0-9737-493e85aeb030','Outdated',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('da22261e-c577-5d2f-87a3-a113190ca595','d2c9217b-d3a7-5a4a-9815-c33704a25aff','9d7380b8-75fd-5049-92b0-3c4314429881','Choose the word closest in meaning to “benevolent”.','hard',15,'“Benevolent” means kind.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('97a9b4b6-1b54-5bb9-9f64-52fca72d4156','da22261e-c577-5d2f-87a3-a113190ca595','Kind',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('875a8ad7-11db-59dd-9c02-24da75127407','da22261e-c577-5d2f-87a3-a113190ca595','Varied',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b969949f-11cc-505d-96bd-06b29399d225','da22261e-c577-5d2f-87a3-a113190ca595','Enormous',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e5fd6b56-44df-5ee7-af73-c7d2afb83a1c','da22261e-c577-5d2f-87a3-a113190ca595','Hopeful',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('b4e6b8f1-1e73-589b-bcb5-58c744f98f4d','d2c9217b-d3a7-5a4a-9815-c33704a25aff','15ce5c00-e6c7-57c7-90b8-666779e61e99','Choose the word closest in meaning to “brief”.','easy',15,'“Brief” means concise.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('fa9350f4-7a93-5811-a9e9-0a0e69133305','b4e6b8f1-1e73-589b-bcb5-58c744f98f4d','Concise',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3e895117-7147-5002-986b-4574f6c58ff5','b4e6b8f1-1e73-589b-bcb5-58c744f98f4d','Keen',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c6eb8306-d22f-5651-9c3e-cc1f23770135','b4e6b8f1-1e73-589b-bcb5-58c744f98f4d','Unbiased',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('69073600-0b8f-5882-9a92-0b4c0e258cec','b4e6b8f1-1e73-589b-bcb5-58c744f98f4d','Determined',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('1bba6d6e-c780-5b5a-ab3d-a0da46ed35ba','d2c9217b-d3a7-5a4a-9815-c33704a25aff','acf1d39a-0793-5fc6-b20e-ababc6f69306','Choose the word closest in meaning to “candid”.','medium',15,'“Candid” means frank.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e1fc2e37-1a69-563f-bc24-a8b304141807','1bba6d6e-c780-5b5a-ab3d-a0da46ed35ba','Frank',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9f42ed6d-2579-5d8f-a80d-214ceadd61a2','1bba6d6e-c780-5b5a-ab3d-a0da46ed35ba','Obvious',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f72502ba-4359-5cf3-a34d-5bc8a2eacf77','1bba6d6e-c780-5b5a-ab3d-a0da46ed35ba','Unavoidable',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('33aeb083-b5fa-56d3-a35f-a3cdb298f6a7','1bba6d6e-c780-5b5a-ab3d-a0da46ed35ba','Sensible',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('c99f8b5b-d84e-5686-8326-90f0ee88de03','d2c9217b-d3a7-5a4a-9815-c33704a25aff','9d7380b8-75fd-5049-92b0-3c4314429881','Choose the word closest in meaning to “cautious”.','easy',15,'“Cautious” means careful.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('000ea097-efa6-574d-80c3-7a12e4cfee2b','c99f8b5b-d84e-5686-8326-90f0ee88de03','Careful',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e73fa817-49d9-5da0-9273-5aa222e4da2f','c99f8b5b-d84e-5686-8326-90f0ee88de03','Practical',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('32cc1374-db72-57f5-b206-ea6ae9bc7458','c99f8b5b-d84e-5686-8326-90f0ee88de03','Inventive',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6fc3545c-cee0-5b82-aaac-9b667d7ab2ea','c99f8b5b-d84e-5686-8326-90f0ee88de03','Unwilling',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('2fc554fc-9f2b-51ef-8af3-48110ba36bce','d2c9217b-d3a7-5a4a-9815-c33704a25aff','15ce5c00-e6c7-57c7-90b8-666779e61e99','Choose the word closest in meaning to “coherent”.','medium',15,'“Coherent” means logical.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d4feb96b-4075-5861-8f0f-7d4094d08937','2fc554fc-9f2b-51ef-8af3-48110ba36bce','Logical',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3c7cbd44-f730-5d34-8ace-2ade0bc6ad21','2fc554fc-9f2b-51ef-8af3-48110ba36bce','Delicate',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('95af6600-6920-568f-9715-ff402fa26672','2fc554fc-9f2b-51ef-8af3-48110ba36bce','Clear',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('85b1c2b7-7500-596a-8c11-c6bbfcde40b6','2fc554fc-9f2b-51ef-8af3-48110ba36bce','Rare',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('ffe1661a-d592-5fbb-aad7-682e6a3d769c','d2c9217b-d3a7-5a4a-9815-c33704a25aff','acf1d39a-0793-5fc6-b20e-ababc6f69306','Choose the word closest in meaning to “competent”.','hard',15,'“Competent” means capable.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2a1dd8a8-410c-5f31-bf14-78ef0e390a68','ffe1661a-d592-5fbb-aad7-682e6a3d769c','Capable',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c8564879-d137-5916-8f20-56bd70fae7d3','ffe1661a-d592-5fbb-aad7-682e6a3d769c','Thrifty',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('bfca4a50-9599-552e-88b4-56a4a5550c47','ffe1661a-d592-5fbb-aad7-682e6a3d769c','Thorough',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d8f24bf6-b556-51c1-9147-eb68f013b113','ffe1661a-d592-5fbb-aad7-682e6a3d769c','Calm',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('2e9db97c-02b8-58f5-936d-3934d6e7fb47','d2c9217b-d3a7-5a4a-9815-c33704a25aff','9d7380b8-75fd-5049-92b0-3c4314429881','Choose the word closest in meaning to “diligent”.','easy',15,'“Diligent” means hardworking.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('37f5df21-cb35-5a92-83b6-1d566547bf0a','2e9db97c-02b8-58f5-936d-3934d6e7fb47','Hardworking',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4b1c5389-dee3-5b6e-bf69-4c8a9712b27f','2e9db97c-02b8-58f5-936d-3934d6e7fb47','Unfriendly',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0b294c2a-7b6c-5485-a502-88d2bd750f00','2e9db97c-02b8-58f5-936d-3934d6e7fb47','Beginner',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('08954fbf-4fc4-5386-8cf6-b519ddf03d86','2e9db97c-02b8-58f5-936d-3934d6e7fb47','Honest',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('21387fce-8873-597a-a915-6d57e5af4eb3','d2c9217b-d3a7-5a4a-9815-c33704a25aff','15ce5c00-e6c7-57c7-90b8-666779e61e99','Choose the word closest in meaning to “diverse”.','medium',15,'“Diverse” means varied.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0a74fc0d-3118-5096-b28e-6d65f11ea3ab','21387fce-8873-597a-a915-6d57e5af4eb3','Varied',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9fc4a2ad-001f-5c0f-ad2e-1b3b4fcb2804','21387fce-8873-597a-a915-6d57e5af4eb3','Modest',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('aa9eaa0a-631d-5f8c-817d-c2410b350f66','21387fce-8873-597a-a915-6d57e5af4eb3','Outdated',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d92e34d3-f9ed-5a09-a60e-7e302ce14dc5','21387fce-8873-597a-a915-6d57e5af4eb3','Doubtful',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('450cd9d5-9db0-5c54-8288-a54ed41cfaca','d2c9217b-d3a7-5a4a-9815-c33704a25aff','acf1d39a-0793-5fc6-b20e-ababc6f69306','Choose the word closest in meaning to “eager”.','easy',15,'“Eager” means keen.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('5376985d-8474-53a3-bc4c-5aad89c2db15','450cd9d5-9db0-5c54-8288-a54ed41cfaca','Keen',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b59f64a5-425f-5196-b9ad-3ab15c925cb1','450cd9d5-9db0-5c54-8288-a54ed41cfaca','Enormous',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('caca2eab-ea01-5017-ace8-554e50d814da','450cd9d5-9db0-5c54-8288-a54ed41cfaca','Hopeful',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ae3dd540-f19b-5d78-9128-b387d5c6365b','450cd9d5-9db0-5c54-8288-a54ed41cfaca','Quick',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('b14f4359-8e27-5858-9941-f62ebb5848a4','d2c9217b-d3a7-5a4a-9815-c33704a25aff','9d7380b8-75fd-5049-92b0-3c4314429881','Choose the word closest in meaning to “evident”.','medium',15,'“Evident” means obvious.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('deeb5b28-d13c-5e40-8df3-a4333a0a8559','b14f4359-8e27-5858-9941-f62ebb5848a4','Obvious',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('5c50bd46-0929-56a1-b542-d8de6c8e5004','b14f4359-8e27-5858-9941-f62ebb5848a4','Unbiased',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('fd674561-fa19-567e-b3b8-d0bbfff75276','b14f4359-8e27-5858-9941-f62ebb5848a4','Determined',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e71654c4-e90c-5694-82e5-ca78ab5ef4b8','b14f4359-8e27-5858-9941-f62ebb5848a4','Boring',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('ce0503d0-de5d-5cc3-a567-fce372dfffc6','d2c9217b-d3a7-5a4a-9815-c33704a25aff','15ce5c00-e6c7-57c7-90b8-666779e61e99','Choose the word closest in meaning to “feasible”.','hard',15,'“Feasible” means practical.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('aac74e15-4dc6-5983-93ac-e66c07d998eb','ce0503d0-de5d-5cc3-a567-fce372dfffc6','Practical',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3e5bfa40-718e-5394-b24c-880e6bda5913','ce0503d0-de5d-5cc3-a567-fce372dfffc6','Unavoidable',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7dc7fcdf-e988-590a-b087-86fc37dff7f4','ce0503d0-de5d-5cc3-a567-fce372dfffc6','Sensible',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a3c04054-0344-5069-bb1c-3822e713e54a','ce0503d0-de5d-5cc3-a567-fce372dfffc6','Peaceful',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('55c0637a-c870-5702-b72d-0e89045a1991','d2c9217b-d3a7-5a4a-9815-c33704a25aff','acf1d39a-0793-5fc6-b20e-ababc6f69306','Choose the word closest in meaning to “fragile”.','easy',15,'“Fragile” means delicate.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('de96a819-48b6-51a0-abc8-3239a95c3006','55c0637a-c870-5702-b72d-0e89045a1991','Delicate',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c2e082de-290d-587a-b4e8-875dffef5697','55c0637a-c870-5702-b72d-0e89045a1991','Inventive',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('13b6f9eb-f582-5319-a029-c231f2a4a8d2','55c0637a-c870-5702-b72d-0e89045a1991','Unwilling',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('93067125-4ac8-54f2-bc96-765bb4877e26','55c0637a-c870-5702-b72d-0e89045a1991','Unclear',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('01d74527-b077-579f-a27e-1b280dea999c','d2c9217b-d3a7-5a4a-9815-c33704a25aff','9d7380b8-75fd-5049-92b0-3c4314429881','Choose the word closest in meaning to “frugal”.','medium',15,'“Frugal” means thrifty.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a55e791c-8b38-5276-acf7-ca9fa89b698b','01d74527-b077-579f-a27e-1b280dea999c','Thrifty',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f95b8281-b16a-5a88-8b67-61475b548f70','01d74527-b077-579f-a27e-1b280dea999c','Clear',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('397ebe7e-b9e5-5406-80d6-e61bd5a35715','01d74527-b077-579f-a27e-1b280dea999c','Rare',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8d548571-65ee-5135-983b-6560949dd791','01d74527-b077-579f-a27e-1b280dea999c','Adaptable',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('69ec3489-f467-59ff-8cc8-055676a305dd','d2c9217b-d3a7-5a4a-9815-c33704a25aff','15ce5c00-e6c7-57c7-90b8-666779e61e99','Choose the word closest in meaning to “hostile”.','easy',15,'“Hostile” means unfriendly.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('de38979f-2ce5-5748-a44d-61f16e21cab9','69ec3489-f467-59ff-8cc8-055676a305dd','Unfriendly',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6c75780e-8233-5a2a-8234-615990411b2b','69ec3489-f467-59ff-8cc8-055676a305dd','Thorough',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3ed5f560-a512-5705-90fc-cda43f35ca48','69ec3489-f467-59ff-8cc8-055676a305dd','Calm',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('5f76bed7-5576-5f86-b3e1-75c8e5b0bce4','69ec3489-f467-59ff-8cc8-055676a305dd','Essential',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('15ae83da-6f26-536b-9fea-59019bff91d2','d2c9217b-d3a7-5a4a-9815-c33704a25aff','acf1d39a-0793-5fc6-b20e-ababc6f69306','Choose the word closest in meaning to “humble”.','medium',15,'“Humble” means modest.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b94241e4-21c0-5b6b-9b6f-4ba54facd692','15ae83da-6f26-536b-9fea-59019bff91d2','Modest',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a251f1ab-9e35-53cf-a1e2-e33460c58856','15ae83da-6f26-536b-9fea-59019bff91d2','Beginner',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f02670b4-1d11-5c97-a646-14e69b43d76f','15ae83da-6f26-536b-9fea-59019bff91d2','Honest',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('bbc6c996-834b-5fa4-8f30-fcbcf86c7dba','15ae83da-6f26-536b-9fea-59019bff91d2','Tired',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('9a981205-1e83-5713-a38d-19520c210ef2','d2c9217b-d3a7-5a4a-9815-c33704a25aff','9d7380b8-75fd-5049-92b0-3c4314429881','Choose the word closest in meaning to “immense”.','hard',15,'“Immense” means enormous.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ef8fabe4-4e25-58f9-beb5-44d8f9c92ad5','9a981205-1e83-5713-a38d-19520c210ef2','Enormous',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9b02dfd4-07a1-5d15-a365-437536cf00e1','9a981205-1e83-5713-a38d-19520c210ef2','Outdated',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d61b4aed-f34b-5c9a-bc79-b3aac575a6e5','9a981205-1e83-5713-a38d-19520c210ef2','Doubtful',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b98ad88c-c508-52a9-9fee-7330377bba4d','9a981205-1e83-5713-a38d-19520c210ef2','Plentiful',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('92a26f91-0517-534b-8f56-cbf0acb51cf9','d2c9217b-d3a7-5a4a-9815-c33704a25aff','15ce5c00-e6c7-57c7-90b8-666779e61e99','Choose the word closest in meaning to “impartial”.','easy',15,'“Impartial” means unbiased.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b7d11a49-4307-5fdc-a722-511579f7f319','92a26f91-0517-534b-8f56-cbf0acb51cf9','Unbiased',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ec387b57-044d-53c8-a133-470f74b50d7d','92a26f91-0517-534b-8f56-cbf0acb51cf9','Hopeful',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3def69d9-6232-59be-9fd0-6bea8e8b4fd8','92a26f91-0517-534b-8f56-cbf0acb51cf9','Quick',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b919aaed-9f68-5e51-bc06-1290a504af37','92a26f91-0517-534b-8f56-cbf0acb51cf9','Precise',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('ff122efc-a254-5638-83e4-017123c5a859','d2c9217b-d3a7-5a4a-9815-c33704a25aff','acf1d39a-0793-5fc6-b20e-ababc6f69306','Choose the word closest in meaning to “inevitable”.','medium',15,'“Inevitable” means unavoidable.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a58ef448-b60a-526c-befe-8f38f09747ef','ff122efc-a254-5638-83e4-017123c5a859','Unavoidable',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('bf68e2bd-d0b1-5c45-93c0-783c80c54273','ff122efc-a254-5638-83e4-017123c5a859','Determined',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('16b64cc1-bb90-5603-b41f-d9d152b8dde1','ff122efc-a254-5638-83e4-017123c5a859','Boring',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f130e24c-5655-5351-b30e-f18ff20bcde3','ff122efc-a254-5638-83e4-017123c5a859','Kind',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('aa4efb81-f15f-560b-9f2b-6673f4ecebaf','d2c9217b-d3a7-5a4a-9815-c33704a25aff','9d7380b8-75fd-5049-92b0-3c4314429881','Choose the word closest in meaning to “innovative”.','easy',15,'“Innovative” means inventive.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('04fc3faf-699e-5c4b-97e8-a61eb427a2f0','aa4efb81-f15f-560b-9f2b-6673f4ecebaf','Inventive',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9260b387-996a-53c2-8c19-50d669780e44','aa4efb81-f15f-560b-9f2b-6673f4ecebaf','Sensible',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f097a0cf-a9f9-5e7e-99e9-fc31661191f4','aa4efb81-f15f-560b-9f2b-6673f4ecebaf','Peaceful',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f1b7b507-e3ae-52be-bd06-0e07e49637e1','aa4efb81-f15f-560b-9f2b-6673f4ecebaf','Concise',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('e0cb3d01-b1b3-52cc-9fc2-9f139f11cfd3','d2c9217b-d3a7-5a4a-9815-c33704a25aff','15ce5c00-e6c7-57c7-90b8-666779e61e99','Choose the word closest in meaning to “lucid”.','medium',15,'“Lucid” means clear.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8279ebc8-d8e7-5374-9681-0c5ec51a51a3','e0cb3d01-b1b3-52cc-9fc2-9f139f11cfd3','Clear',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2fa8b18b-ebd8-5b69-96bd-b6f99c89b1b7','e0cb3d01-b1b3-52cc-9fc2-9f139f11cfd3','Unwilling',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('18c39538-4028-53c8-b61c-a4d4743451cf','e0cb3d01-b1b3-52cc-9fc2-9f139f11cfd3','Unclear',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('83041097-d660-5630-9d5a-606757014dcb','e0cb3d01-b1b3-52cc-9fc2-9f139f11cfd3','Frank',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('5051d4ee-f3a8-5a49-ba42-024a94476984','d2c9217b-d3a7-5a4a-9815-c33704a25aff','acf1d39a-0793-5fc6-b20e-ababc6f69306','Choose the word closest in meaning to “meticulous”.','hard',15,'“Meticulous” means thorough.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('714a86ef-fe00-50b5-a943-ca1a8eeace5d','5051d4ee-f3a8-5a49-ba42-024a94476984','Thorough',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('17e26e2d-be02-570f-92f5-ac05364e03a4','5051d4ee-f3a8-5a49-ba42-024a94476984','Rare',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6184279d-8da1-5563-8fa2-89ab28786286','5051d4ee-f3a8-5a49-ba42-024a94476984','Adaptable',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('47c4bfd7-da73-5487-83ce-1e6e9f7fb2fe','5051d4ee-f3a8-5a49-ba42-024a94476984','Careful',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('03b489dd-48a7-56d1-a1da-1f1ff8e7e476','d2c9217b-d3a7-5a4a-9815-c33704a25aff','9d7380b8-75fd-5049-92b0-3c4314429881','Choose the word closest in meaning to “novice”.','easy',15,'“Novice” means beginner.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('439a1a32-caea-5d09-9421-31f65e88f4e2','03b489dd-48a7-56d1-a1da-1f1ff8e7e476','Beginner',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('12fcbc4f-6cea-5616-8f72-911f5e5b6287','03b489dd-48a7-56d1-a1da-1f1ff8e7e476','Calm',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('baf10de7-3674-5986-a198-368a85f1a033','03b489dd-48a7-56d1-a1da-1f1ff8e7e476','Essential',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8bfa35e5-3b79-533b-91cf-4182ff297445','03b489dd-48a7-56d1-a1da-1f1ff8e7e476','Logical',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('922425d3-c363-50d2-9930-241ef9480eb9','d2c9217b-d3a7-5a4a-9815-c33704a25aff','15ce5c00-e6c7-57c7-90b8-666779e61e99','Choose the word closest in meaning to “obsolete”.','medium',15,'“Obsolete” means outdated.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f39fd0d4-d62d-5aca-9aad-ec0f36291cfd','922425d3-c363-50d2-9930-241ef9480eb9','Outdated',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('83cc5bd9-0de6-5b37-b387-6c75d315e05f','922425d3-c363-50d2-9930-241ef9480eb9','Honest',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f6d63ecc-23d8-55c7-972c-6033f373452e','922425d3-c363-50d2-9930-241ef9480eb9','Tired',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('afbfb741-2ab4-57b7-8ec1-91bfc70dd887','922425d3-c363-50d2-9930-241ef9480eb9','Capable',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('c534a63a-ef22-5d88-9433-84f4941f7212','d2c9217b-d3a7-5a4a-9815-c33704a25aff','acf1d39a-0793-5fc6-b20e-ababc6f69306','Choose the word closest in meaning to “optimistic”.','easy',15,'“Optimistic” means hopeful.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4c2e2b44-79e5-5d6b-a0c4-016ff2cebc52','c534a63a-ef22-5d88-9433-84f4941f7212','Hopeful',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a3c8cdaf-7430-598f-adbe-3eafcc42e66b','c534a63a-ef22-5d88-9433-84f4941f7212','Doubtful',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('be640d29-a973-5c3a-8f9b-45b0d5284448','c534a63a-ef22-5d88-9433-84f4941f7212','Plentiful',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c359f45b-d068-5f97-ba45-2816c1b65663','c534a63a-ef22-5d88-9433-84f4941f7212','Hardworking',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('6f1b4bbd-83db-5efb-b662-1a179ba588c2','d2c9217b-d3a7-5a4a-9815-c33704a25aff','9d7380b8-75fd-5049-92b0-3c4314429881','Choose the word closest in meaning to “persistent”.','medium',15,'“Persistent” means determined.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c487866b-32a2-5153-91ca-e587be047e08','6f1b4bbd-83db-5efb-b662-1a179ba588c2','Determined',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('dee68692-4967-559f-a253-25c962e8f437','6f1b4bbd-83db-5efb-b662-1a179ba588c2','Quick',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9dc53d24-2fe8-57f3-a3a6-83a095a0a291','6f1b4bbd-83db-5efb-b662-1a179ba588c2','Precise',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3d4c6dac-975a-514f-9bf1-54fc2d01e6ca','6f1b4bbd-83db-5efb-b662-1a179ba588c2','Varied',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('40b4805e-49d5-57c8-8029-10b49c74d8a5','d2c9217b-d3a7-5a4a-9815-c33704a25aff','15ce5c00-e6c7-57c7-90b8-666779e61e99','Choose the word closest in meaning to “prudent”.','hard',15,'“Prudent” means sensible.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8fe712ed-a8d3-5f32-bbe9-992b87224620','40b4805e-49d5-57c8-8029-10b49c74d8a5','Sensible',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('686e55e3-085d-5c5b-b91c-0d11eda66229','40b4805e-49d5-57c8-8029-10b49c74d8a5','Boring',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6c7ead7c-ac04-5372-b6df-c0841b5cc324','40b4805e-49d5-57c8-8029-10b49c74d8a5','Kind',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('474796b9-35c6-5c49-a272-80a961d1a6f1','40b4805e-49d5-57c8-8029-10b49c74d8a5','Keen',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('a7183bec-bc2a-5be4-bd7e-deda9ff80a94','d2c9217b-d3a7-5a4a-9815-c33704a25aff','acf1d39a-0793-5fc6-b20e-ababc6f69306','Choose the word closest in meaning to “reluctant”.','easy',15,'“Reluctant” means unwilling.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7f901482-14ce-5ce4-ad71-bf6474c14619','a7183bec-bc2a-5be4-bd7e-deda9ff80a94','Unwilling',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('96853bc2-b3e0-5a05-89de-4f7029772a74','a7183bec-bc2a-5be4-bd7e-deda9ff80a94','Peaceful',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('dd03f57a-79a4-5f52-a7fc-47378344d66f','a7183bec-bc2a-5be4-bd7e-deda9ff80a94','Concise',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c6387a4e-bb0b-596e-90a9-db07ea41081f','a7183bec-bc2a-5be4-bd7e-deda9ff80a94','Obvious',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('56efc4ee-72e1-5d40-a927-663b6bb5902e','d2c9217b-d3a7-5a4a-9815-c33704a25aff','9d7380b8-75fd-5049-92b0-3c4314429881','Choose the word closest in meaning to “scarce”.','medium',15,'“Scarce” means rare.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e76d4721-d9ba-5120-aff8-13f84256f50b','56efc4ee-72e1-5d40-a927-663b6bb5902e','Rare',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e13c32c6-32da-5bcc-bbae-5eda3b3061d8','56efc4ee-72e1-5d40-a927-663b6bb5902e','Unclear',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ea3c2387-09be-5ce0-a9a1-f01a716ef482','56efc4ee-72e1-5d40-a927-663b6bb5902e','Frank',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('515d0953-16e5-5ec9-80bb-5051667e4b8e','56efc4ee-72e1-5d40-a927-663b6bb5902e','Practical',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('d78c3c10-fa5c-5289-98f8-f9d40097b6b3','d2c9217b-d3a7-5a4a-9815-c33704a25aff','15ce5c00-e6c7-57c7-90b8-666779e61e99','Choose the word closest in meaning to “serene”.','easy',15,'“Serene” means calm.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2d5f5aae-fc2c-5025-a647-8721b54a3df6','d78c3c10-fa5c-5289-98f8-f9d40097b6b3','Calm',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4fd2b301-5c64-542b-b884-ad2d89c14193','d78c3c10-fa5c-5289-98f8-f9d40097b6b3','Adaptable',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0458df0f-d14e-561b-a4ea-ec7f8c545404','d78c3c10-fa5c-5289-98f8-f9d40097b6b3','Careful',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3abf6719-6349-5fba-bc6d-c37a97fed04c','d78c3c10-fa5c-5289-98f8-f9d40097b6b3','Delicate',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('077a616e-b0b1-5b00-8c23-b93442301f1e','d2c9217b-d3a7-5a4a-9815-c33704a25aff','acf1d39a-0793-5fc6-b20e-ababc6f69306','Choose the word closest in meaning to “sincere”.','medium',15,'“Sincere” means honest.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('81123c19-6d74-5768-a3e5-2a89b6ed3a33','077a616e-b0b1-5b00-8c23-b93442301f1e','Honest',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('93af7580-62c6-554d-9344-3d06d7cd9f1e','077a616e-b0b1-5b00-8c23-b93442301f1e','Essential',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9c30d397-d187-5031-8abe-e170c6d0de50','077a616e-b0b1-5b00-8c23-b93442301f1e','Logical',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0eeae0ac-c120-5b5e-a49e-2f5509ce08a7','077a616e-b0b1-5b00-8c23-b93442301f1e','Thrifty',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('3af87bcf-ab8e-509c-a2c2-a217fce6487a','d2c9217b-d3a7-5a4a-9815-c33704a25aff','9d7380b8-75fd-5049-92b0-3c4314429881','Choose the word closest in meaning to “skeptical”.','hard',15,'“Skeptical” means doubtful.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('91089037-d112-5074-93d2-a156c9ea7c2a','3af87bcf-ab8e-509c-a2c2-a217fce6487a','Doubtful',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e32678e3-2869-5a98-a530-56db5dc92213','3af87bcf-ab8e-509c-a2c2-a217fce6487a','Tired',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7db3ddd9-caa5-5178-9708-9693f4630f5b','3af87bcf-ab8e-509c-a2c2-a217fce6487a','Capable',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d1d2fecf-ca5b-5f95-b867-c654dc853d5b','3af87bcf-ab8e-509c-a2c2-a217fce6487a','Unfriendly',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('a3088b82-7feb-53c1-8ac9-6f98af973681','d2c9217b-d3a7-5a4a-9815-c33704a25aff','15ce5c00-e6c7-57c7-90b8-666779e61e99','Choose the word closest in meaning to “swift”.','easy',15,'“Swift” means quick.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c7882e41-4053-5739-9c9d-fe4b36997e8d','a3088b82-7feb-53c1-8ac9-6f98af973681','Quick',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('bcf02b09-35f0-5cb8-b718-8065778b458f','a3088b82-7feb-53c1-8ac9-6f98af973681','Plentiful',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1d7b1bdf-3bf8-528b-b714-02272b5dd92b','a3088b82-7feb-53c1-8ac9-6f98af973681','Hardworking',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c270a74a-0996-586d-a2bc-3675deaebcfa','a3088b82-7feb-53c1-8ac9-6f98af973681','Modest',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('32847e18-dbff-5ced-b234-e23f3fda915b','d2c9217b-d3a7-5a4a-9815-c33704a25aff','acf1d39a-0793-5fc6-b20e-ababc6f69306','Choose the word closest in meaning to “tedious”.','medium',15,'“Tedious” means boring.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8949a2a5-e200-5534-8248-34c2c3a539db','32847e18-dbff-5ced-b234-e23f3fda915b','Boring',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d99a7e64-b276-5a92-ab92-ca52229cfa6b','32847e18-dbff-5ced-b234-e23f3fda915b','Precise',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6b90667b-7976-56be-ac5c-54b3f65cd1a6','32847e18-dbff-5ced-b234-e23f3fda915b','Varied',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6e972b1f-e77d-5ee0-8db0-fe9cb3dd1e11','32847e18-dbff-5ced-b234-e23f3fda915b','Enormous',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('3c0a42ca-e15d-5fcf-a6e6-ac63d7dd8169','d2c9217b-d3a7-5a4a-9815-c33704a25aff','9d7380b8-75fd-5049-92b0-3c4314429881','Choose the word closest in meaning to “tranquil”.','easy',15,'“Tranquil” means peaceful.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9cb22e77-6f11-583d-bcb1-be54fe074ce3','3c0a42ca-e15d-5fcf-a6e6-ac63d7dd8169','Peaceful',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e7362718-ce0a-5fb4-9f14-7bfe90b75932','3c0a42ca-e15d-5fcf-a6e6-ac63d7dd8169','Kind',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c583369b-1d5c-5635-a143-eea96534fb7f','3c0a42ca-e15d-5fcf-a6e6-ac63d7dd8169','Keen',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('14cda22e-08c8-5d0c-a4ca-bfe1522ac307','3c0a42ca-e15d-5fcf-a6e6-ac63d7dd8169','Unbiased',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('8e884e12-ed0e-5fca-9c42-40dcd8c9dffb','d2c9217b-d3a7-5a4a-9815-c33704a25aff','15ce5c00-e6c7-57c7-90b8-666779e61e99','Choose the word closest in meaning to “vague”.','medium',15,'“Vague” means unclear.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e7e57ee3-d012-558b-9a8a-ed477a878ec1','8e884e12-ed0e-5fca-9c42-40dcd8c9dffb','Unclear',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('489e9e28-1969-59ec-833d-47d7cdfeb7ab','8e884e12-ed0e-5fca-9c42-40dcd8c9dffb','Concise',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('85eca3bb-2282-581e-8690-aa6de526f534','8e884e12-ed0e-5fca-9c42-40dcd8c9dffb','Obvious',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9508cd30-f787-5125-894a-a4a68e29334f','8e884e12-ed0e-5fca-9c42-40dcd8c9dffb','Unavoidable',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('b4d2378e-103a-579a-8560-3f68aaa43e1f','d2c9217b-d3a7-5a4a-9815-c33704a25aff','acf1d39a-0793-5fc6-b20e-ababc6f69306','Choose the word closest in meaning to “versatile”.','hard',15,'“Versatile” means adaptable.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4e1de5e3-1610-50ed-96dd-e7f2713e1805','b4d2378e-103a-579a-8560-3f68aaa43e1f','Adaptable',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7b7ab5ee-3ae1-55f4-859f-0b1dac251c2c','b4d2378e-103a-579a-8560-3f68aaa43e1f','Frank',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e65d9fb1-cbd7-556d-be72-96d9f2f4361f','b4d2378e-103a-579a-8560-3f68aaa43e1f','Practical',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('65f36a63-e477-53a5-81ea-86d6c33bf1c9','b4d2378e-103a-579a-8560-3f68aaa43e1f','Inventive',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('66cef766-bcf8-56aa-85cf-b1b320229b31','d2c9217b-d3a7-5a4a-9815-c33704a25aff','9d7380b8-75fd-5049-92b0-3c4314429881','Choose the word closest in meaning to “vital”.','easy',15,'“Vital” means essential.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d4efc82c-be41-51f4-b3dd-e4bbe9c04451','66cef766-bcf8-56aa-85cf-b1b320229b31','Essential',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e5b604d8-594b-5eec-af0a-2fc7fde1823c','66cef766-bcf8-56aa-85cf-b1b320229b31','Careful',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c951f7ba-0ce8-5f1e-bb1f-c9b685143724','66cef766-bcf8-56aa-85cf-b1b320229b31','Delicate',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7db72d27-5b84-5a03-b24b-846be7f02e26','66cef766-bcf8-56aa-85cf-b1b320229b31','Clear',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('8d5c94c1-c557-5239-8753-b97ee23e2c29','d2c9217b-d3a7-5a4a-9815-c33704a25aff','15ce5c00-e6c7-57c7-90b8-666779e61e99','Choose the word closest in meaning to “weary”.','medium',15,'“Weary” means tired.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('bff515ca-315f-5b67-91f0-240c5f64ad59','8d5c94c1-c557-5239-8753-b97ee23e2c29','Tired',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('435202f6-d2ef-5e68-90dd-9af12b9bb600','8d5c94c1-c557-5239-8753-b97ee23e2c29','Logical',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e9576223-22a6-528f-84e9-3b5a9666bb10','8d5c94c1-c557-5239-8753-b97ee23e2c29','Thrifty',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('dc1a6a57-d4f3-5018-b1e4-6bd31ba1dfc1','8d5c94c1-c557-5239-8753-b97ee23e2c29','Thorough',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('1aaa53fd-4221-5d67-9d98-1c7b98ba3d6d','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','Which part of the Indian Constitution contains Fundamental Rights?','easy',15,'The correct answer is Part III.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('80d5347c-9bf9-563c-abbb-a670da325ac6','1aaa53fd-4221-5d67-9d98-1c7b98ba3d6d','Part III',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('64efc310-9074-50c3-9f76-703fb84276b7','1aaa53fd-4221-5d67-9d98-1c7b98ba3d6d','Part I',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b25dabbe-deea-5119-aca9-5682acaeda97','1aaa53fd-4221-5d67-9d98-1c7b98ba3d6d','Part II',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('22c8b650-23de-5ed5-9649-ecd0aebec745','1aaa53fd-4221-5d67-9d98-1c7b98ba3d6d','Part IV',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('88a3bef8-6d51-5298-9a72-54613c6f73f9','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','c48ff9f3-c397-56fe-8ffd-e8af52ca6db0','Which article abolishes untouchability?','medium',15,'The correct answer is Article 17.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('701d66fe-43eb-5f84-bf5d-d0ed75bc0025','88a3bef8-6d51-5298-9a72-54613c6f73f9','Article 17',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e2269f49-011d-55ba-b9e4-cc47b30117f6','88a3bef8-6d51-5298-9a72-54613c6f73f9','Article 14',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f5827948-2338-552c-a0a2-5f01154a6c83','88a3bef8-6d51-5298-9a72-54613c6f73f9','Article 19',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('40aac614-2e0b-58d3-895e-628785672802','88a3bef8-6d51-5298-9a72-54613c6f73f9','Article 21',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('28cb1fc8-0b56-5a65-b183-41b274a86157','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','1898f5a5-af8f-5e22-b21f-bb51f1e6fb2c','What is the minimum age to become a member of the Lok Sabha?','hard',15,'The correct answer is 25 years.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b12cd802-b43e-5a93-991b-eb2dd4f15689','28cb1fc8-0b56-5a65-b183-41b274a86157','25 years',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('709dce8d-5cf4-578a-85be-5135b1bd683a','28cb1fc8-0b56-5a65-b183-41b274a86157','21 years',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4639be96-1808-5934-9774-1cccd595c7c9','28cb1fc8-0b56-5a65-b183-41b274a86157','30 years',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('819fca13-6be4-592b-8858-85fb8bfe3c7f','28cb1fc8-0b56-5a65-b183-41b274a86157','35 years',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('21277680-771f-5157-869f-2642e86eb521','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','The Directive Principles are contained in which part?','easy',15,'The correct answer is Part IV.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('63edca97-2b3c-5451-a489-e49be476acc1','21277680-771f-5157-869f-2642e86eb521','Part IV',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4796f537-804e-58ce-b39d-63fb578acc93','21277680-771f-5157-869f-2642e86eb521','Part II',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('bb2207f9-42c6-57a3-8f33-62b38b38ffb4','21277680-771f-5157-869f-2642e86eb521','Part III',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('38d58ac4-87a9-525b-b7bb-438521867c52','21277680-771f-5157-869f-2642e86eb521','Part V',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('4122a7a3-d64f-565b-a517-e8640dd3a256','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','c48ff9f3-c397-56fe-8ffd-e8af52ca6db0','How many Fundamental Duties are listed in the Constitution?','medium',15,'The correct answer is 11.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('94e77615-58b9-5923-b3fa-6803b8c3cf92','4122a7a3-d64f-565b-a517-e8640dd3a256','11',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('24954dc8-9991-5b80-8e63-9e695a5dc878','4122a7a3-d64f-565b-a517-e8640dd3a256','10',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ff82af49-94eb-53ba-a0ec-be414bbe3749','4122a7a3-d64f-565b-a517-e8640dd3a256','12',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e7e54fdc-34a3-5283-83fb-79b51729d967','4122a7a3-d64f-565b-a517-e8640dd3a256','9',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('4359b42f-5f74-5321-8aa8-1556cafb0a46','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','1898f5a5-af8f-5e22-b21f-bb51f1e6fb2c','Who chairs the Rajya Sabha?','easy',15,'The correct answer is Vice President.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3d46330e-5bee-5e75-8052-fdb70276ae19','4359b42f-5f74-5321-8aa8-1556cafb0a46','Vice President',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7d2eaa0b-c2a8-5c33-858f-46955a92385b','4359b42f-5f74-5321-8aa8-1556cafb0a46','President',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0eb23d05-62e0-5974-8214-e22628f69095','4359b42f-5f74-5321-8aa8-1556cafb0a46','Prime Minister',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9821ee53-a663-5fa1-831d-c628653c1e71','4359b42f-5f74-5321-8aa8-1556cafb0a46','Lok Sabha Speaker',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('15b0f1fa-06d3-59c0-be43-16fbb109001a','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','Which amendment lowered the voting age to 18?','medium',15,'The correct answer is 61st.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6d3f0bfb-c885-52c9-936d-8d0318485fa4','15b0f1fa-06d3-59c0-be43-16fbb109001a','61st',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b2ce2619-8af3-5174-8558-a0713981532e','15b0f1fa-06d3-59c0-be43-16fbb109001a','42nd',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a22b0f49-0bfd-5bd7-add0-31091caa8a86','15b0f1fa-06d3-59c0-be43-16fbb109001a','44th',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('05abd8c8-deef-584b-a112-d45e1bade154','15b0f1fa-06d3-59c0-be43-16fbb109001a','73rd',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('fe27d3fd-a8a5-5d4c-b05e-d3d605d8699a','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','c48ff9f3-c397-56fe-8ffd-e8af52ca6db0','Which schedule lists the recognised languages?','hard',15,'The correct answer is Eighth.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b0d0a6f0-d58f-558f-981b-f6d2b57b7708','fe27d3fd-a8a5-5d4c-b05e-d3d605d8699a','Eighth',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2362174e-203d-5f6b-8c00-4aa3ad6f6d20','fe27d3fd-a8a5-5d4c-b05e-d3d605d8699a','Fifth',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('48bda702-e925-5c3e-89e4-a22eb3112597','fe27d3fd-a8a5-5d4c-b05e-d3d605d8699a','Seventh',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e14a2035-1832-5725-8d02-bfbd042cc0db','fe27d3fd-a8a5-5d4c-b05e-d3d605d8699a','Tenth',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('d4de2ca4-43d3-5f30-8d96-e87d537f3656','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','1898f5a5-af8f-5e22-b21f-bb51f1e6fb2c','Panchayati Raj received constitutional status through which amendment?','easy',15,'The correct answer is 73rd.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4683d166-2f6f-55fc-86b6-9662f76e9f2b','d4de2ca4-43d3-5f30-8d96-e87d537f3656','73rd',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3d9481ee-1b13-5f72-9878-a727d75db429','d4de2ca4-43d3-5f30-8d96-e87d537f3656','42nd',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e6b99cbe-a400-565b-93d2-4aed066a3925','d4de2ca4-43d3-5f30-8d96-e87d537f3656','61st',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('12a452c5-52a7-58a9-8c96-5b901609c6e2','d4de2ca4-43d3-5f30-8d96-e87d537f3656','86th',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('ba2b5b76-039e-5c05-9c1d-5183959bfda9','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','What is the minimum age to become President of India?','medium',15,'The correct answer is 35 years.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('eb47f570-65f3-5e82-89cd-2e57e5723ed4','ba2b5b76-039e-5c05-9c1d-5183959bfda9','35 years',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2b9b6a37-8083-5262-bf13-08ff911a0382','ba2b5b76-039e-5c05-9c1d-5183959bfda9','25 years',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7ca162c0-f2ee-5996-95e1-2105c7e4d763','ba2b5b76-039e-5c05-9c1d-5183959bfda9','30 years',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9a608b60-9b58-5aba-ae58-5da05fe32daa','ba2b5b76-039e-5c05-9c1d-5183959bfda9','40 years',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('039e9f77-ad80-5b9c-9d6b-7cf3918a268e','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','c48ff9f3-c397-56fe-8ffd-e8af52ca6db0','On which date did the Constitution of India come into effect?','easy',15,'The correct answer is 26 January 1950.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('54713fd0-0770-59c6-968f-95076ef0d33b','039e9f77-ad80-5b9c-9d6b-7cf3918a268e','26 January 1950',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c3fa55e6-f2e1-5bbf-8258-c510d6160143','039e9f77-ad80-5b9c-9d6b-7cf3918a268e','15 August 1947',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ce17f4b2-d5b4-5573-9b64-98df275f57d1','039e9f77-ad80-5b9c-9d6b-7cf3918a268e','26 November 1949',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f9f0f86f-6bc5-5081-9849-78b79e5d9827','039e9f77-ad80-5b9c-9d6b-7cf3918a268e','2 October 1950',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('5e10c041-2701-54f4-baaf-458ca49d3791','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','1898f5a5-af8f-5e22-b21f-bb51f1e6fb2c','Who chaired the Constitution Drafting Committee?','medium',15,'The correct answer is B. R. Ambedkar.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('220bded0-f990-51d0-b301-f5cd6de6541b','5e10c041-2701-54f4-baaf-458ca49d3791','B. R. Ambedkar',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('cc144ac9-ee83-5408-8ff6-c437bbfe9a4f','5e10c041-2701-54f4-baaf-458ca49d3791','Jawaharlal Nehru',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3dc5a5ca-de95-54a6-bcbf-fff7f6ae3904','5e10c041-2701-54f4-baaf-458ca49d3791','Rajendra Prasad',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1432c563-7c13-5e27-b243-04c7535c0223','5e10c041-2701-54f4-baaf-458ca49d3791','Sardar Patel',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('688e9c20-6fdd-59ce-9033-ee6dc31a6425','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','Which ocean lies south of India?','hard',15,'The correct answer is Indian Ocean.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9cd26579-2998-5492-9bda-eefdef8b0b9a','688e9c20-6fdd-59ce-9033-ee6dc31a6425','Indian Ocean',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1a88a024-6716-55a9-9c58-6ffeec9824b7','688e9c20-6fdd-59ce-9033-ee6dc31a6425','Pacific Ocean',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3e18b056-3ada-51d9-ae8c-7362aa759188','688e9c20-6fdd-59ce-9033-ee6dc31a6425','Atlantic Ocean',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('dc4f6514-6708-52a7-ba6b-37474b827ccd','688e9c20-6fdd-59ce-9033-ee6dc31a6425','Arctic Ocean',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('e9c897e6-8670-540e-9ea0-34016aba59ea','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','c48ff9f3-c397-56fe-8ffd-e8af52ca6db0','Which is the largest Indian state by area?','easy',15,'The correct answer is Rajasthan.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9bac93a4-d759-5ee8-9139-44a5f82d4c3c','e9c897e6-8670-540e-9ea0-34016aba59ea','Rajasthan',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b418cc28-a4f8-5730-99f4-344ba71251fd','e9c897e6-8670-540e-9ea0-34016aba59ea','Maharashtra',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1afc8dd2-0511-561b-b663-fc1916988d0d','e9c897e6-8670-540e-9ea0-34016aba59ea','Madhya Pradesh',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0dcaf8b4-cca7-565e-8974-20d9afd93f43','e9c897e6-8670-540e-9ea0-34016aba59ea','Uttar Pradesh',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('98d1f2a4-fe58-5e0b-8e8e-b884051d4e3f','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','1898f5a5-af8f-5e22-b21f-bb51f1e6fb2c','Which is the smallest Indian state by area?','medium',15,'The correct answer is Goa.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d9492c38-86e6-578c-9512-de0f2c6d56e0','98d1f2a4-fe58-5e0b-8e8e-b884051d4e3f','Goa',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('89e12210-f622-5312-97e0-9285c9f00e85','98d1f2a4-fe58-5e0b-8e8e-b884051d4e3f','Sikkim',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('86ccee80-a144-54e9-acf8-69c295536cae','98d1f2a4-fe58-5e0b-8e8e-b884051d4e3f','Tripura',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4e26a307-ec13-560b-9ca5-2a228877e0bb','98d1f2a4-fe58-5e0b-8e8e-b884051d4e3f','Mizoram',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('165cd268-c9e1-5d8f-8e1d-3519e3da00b7','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','Which river flows through Delhi?','easy',15,'The correct answer is Yamuna.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7ebb8baf-d218-5bad-a3a6-2b728ce47498','165cd268-c9e1-5d8f-8e1d-3519e3da00b7','Yamuna',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('cd81ed06-5302-5cc1-a4f7-6650b12caa69','165cd268-c9e1-5d8f-8e1d-3519e3da00b7','Ganga',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ba76bd09-bcb1-5e3b-b212-e31af33fe5fc','165cd268-c9e1-5d8f-8e1d-3519e3da00b7','Godavari',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e7be6598-9cb1-51e1-a946-3b6be8c1a155','165cd268-c9e1-5d8f-8e1d-3519e3da00b7','Narmada',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('82f77b90-98f5-584f-9861-576152c338d2','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','c48ff9f3-c397-56fe-8ffd-e8af52ca6db0','Which imaginary line passes through central India?','medium',15,'The correct answer is Tropic of Cancer.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e31ad169-cd52-5901-9204-3bdacddedb6b','82f77b90-98f5-584f-9861-576152c338d2','Tropic of Cancer',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9d0ea58f-f69c-56bf-a5e1-14d4883f2a50','82f77b90-98f5-584f-9861-576152c338d2','Equator',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('82db12a0-0a6c-5b4c-97f5-ed2de6b9702a','82f77b90-98f5-584f-9861-576152c338d2','Tropic of Capricorn',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ead04df5-b1d9-5588-a8d3-51a55a60afd6','82f77b90-98f5-584f-9861-576152c338d2','Arctic Circle',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('01e8081f-3716-54e7-ba24-57af20e1a98c','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','1898f5a5-af8f-5e22-b21f-bb51f1e6fb2c','Which range separates the Indian subcontinent from the Tibetan Plateau?','hard',15,'The correct answer is Himalayas.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('86a6874c-66d5-5bae-b4fd-0d61a84eb619','01e8081f-3716-54e7-ba24-57af20e1a98c','Himalayas',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c4f98311-c813-5cea-b182-c37c3f2126d8','01e8081f-3716-54e7-ba24-57af20e1a98c','Aravalli',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1b4a1ef5-a063-5f84-b0bb-804d5f58b6e3','01e8081f-3716-54e7-ba24-57af20e1a98c','Western Ghats',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('fb14a11c-d519-52ae-8bfb-3c2c5a6d20c7','01e8081f-3716-54e7-ba24-57af20e1a98c','Satpura',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('65661d7d-bd21-5b06-8f73-5cf0226a101d','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','What is the capital of Kerala?','easy',15,'The correct answer is Thiruvananthapuram.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('83d9fa0d-eee4-5ecf-a7df-a984e02b3c54','65661d7d-bd21-5b06-8f73-5cf0226a101d','Thiruvananthapuram',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('04337472-588a-5fcf-8a4e-5842259961b5','65661d7d-bd21-5b06-8f73-5cf0226a101d','Kochi',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('263d3cd3-3e19-5a7f-b5ff-a2efe7d7b17a','65661d7d-bd21-5b06-8f73-5cf0226a101d','Kozhikode',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e2a34095-290d-55a3-879a-05f621b81f88','65661d7d-bd21-5b06-8f73-5cf0226a101d','Thrissur',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('88737177-72af-57c7-88d4-23075cf5851f','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','c48ff9f3-c397-56fe-8ffd-e8af52ca6db0','Which plateau covers much of peninsular India?','medium',15,'The correct answer is Deccan Plateau.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a602f712-9d4f-5bb5-9a4f-e415445f1216','88737177-72af-57c7-88d4-23075cf5851f','Deccan Plateau',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('853091ba-49c0-5785-9595-da4a0010d53c','88737177-72af-57c7-88d4-23075cf5851f','Tibetan Plateau',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('fc3367cd-bb55-5598-a735-e6f0122c3c8e','88737177-72af-57c7-88d4-23075cf5851f','Chota Nagpur Plateau',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1cfe6949-ec4a-5b8a-8ccd-16f5263f358c','88737177-72af-57c7-88d4-23075cf5851f','Malwa Plateau',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('878739b8-1291-509f-b001-c784af251848','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','1898f5a5-af8f-5e22-b21f-bb51f1e6fb2c','Which sea lies west of India?','easy',15,'The correct answer is Arabian Sea.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('82af1a9e-1774-5d4c-850b-39226c6223ba','878739b8-1291-509f-b001-c784af251848','Arabian Sea',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('648edbcc-7abf-5fff-af78-e51f1662dbbc','878739b8-1291-509f-b001-c784af251848','Red Sea',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2c088476-902d-5191-a118-5f14d7647635','878739b8-1291-509f-b001-c784af251848','Caspian Sea',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ca2c902a-3b00-5902-93d1-18cd7efb5888','878739b8-1291-509f-b001-c784af251848','South China Sea',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('eec1f4f6-a44d-51fd-8a44-33215615c5c2','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','Which is the largest continent by area?','medium',15,'The correct answer is Asia.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2a178b3e-cbc4-5e61-951f-6db1b406b8f9','eec1f4f6-a44d-51fd-8a44-33215615c5c2','Asia',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a81d4348-9b8e-5148-a43b-6453d484548f','eec1f4f6-a44d-51fd-8a44-33215615c5c2','Africa',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('661860f2-e221-5636-9f17-ca2514943efa','eec1f4f6-a44d-51fd-8a44-33215615c5c2','Europe',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ae184a21-ecfe-51df-9cd8-c5bdfe037370','eec1f4f6-a44d-51fd-8a44-33215615c5c2','Antarctica',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('f09f80cb-7d32-5fe6-89bc-97b0264d0c31','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','c48ff9f3-c397-56fe-8ffd-e8af52ca6db0','Which is the smallest continent by area?','hard',15,'The correct answer is Australia.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a77153c4-c8e8-5d5f-a5f7-feb30c630692','f09f80cb-7d32-5fe6-89bc-97b0264d0c31','Australia',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4fcf8f95-8f5c-5bf8-9413-2dfb73163395','f09f80cb-7d32-5fe6-89bc-97b0264d0c31','Europe',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('0316f03a-1c06-55c4-9da0-520fc31ddf6c','f09f80cb-7d32-5fe6-89bc-97b0264d0c31','Antarctica',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c9055a95-4311-50ce-b327-03f62846fabb','f09f80cb-7d32-5fe6-89bc-97b0264d0c31','South America',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('c65fa38c-40bc-5d8b-a3b2-5344de7f28b2','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','1898f5a5-af8f-5e22-b21f-bb51f1e6fb2c','Which is the longest river in peninsular India?','easy',15,'The correct answer is Godavari.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('a67e5783-f689-5d92-8e15-403e6ba90116','c65fa38c-40bc-5d8b-a3b2-5344de7f28b2','Godavari',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8d22d209-21c1-575d-9c13-a822dba8728e','c65fa38c-40bc-5d8b-a3b2-5344de7f28b2','Krishna',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('43c5225d-11b0-55c2-a473-9e32cf875f0d','c65fa38c-40bc-5d8b-a3b2-5344de7f28b2','Kaveri',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3db0dac0-16f2-5056-ae38-8449972092ca','c65fa38c-40bc-5d8b-a3b2-5344de7f28b2','Narmada',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('6efd8f01-0384-55cf-8450-e5ba234351c2','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','What is the SI unit of force?','medium',15,'The correct answer is Newton.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('22062fb9-6f95-506b-a6a8-5bc5b93b444b','6efd8f01-0384-55cf-8450-e5ba234351c2','Newton',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('20a4fd44-8357-507b-80fd-9e953fdc87b8','6efd8f01-0384-55cf-8450-e5ba234351c2','Joule',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8272bfc6-1737-56c1-af18-426dd9fdd004','6efd8f01-0384-55cf-8450-e5ba234351c2','Watt',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e3ddcfbe-cfb2-5ad1-a5f1-cf41015a293c','6efd8f01-0384-55cf-8450-e5ba234351c2','Pascal',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('cafefe94-9809-525e-b510-10f0938cbb98','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','c48ff9f3-c397-56fe-8ffd-e8af52ca6db0','What is the chemical symbol for gold?','easy',15,'The correct answer is Au.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ca612d7a-c06c-563a-9ba2-c71f7776c563','cafefe94-9809-525e-b510-10f0938cbb98','Au',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('e5059535-849a-5597-8a6c-2f73ac04a722','cafefe94-9809-525e-b510-10f0938cbb98','Ag',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7a3710d0-c859-5009-baf3-31919b2673fb','cafefe94-9809-525e-b510-10f0938cbb98','Fe',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7f42835e-4111-5520-b8f8-f9e4966c563c','cafefe94-9809-525e-b510-10f0938cbb98','Cu',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('5b7988ec-1c7d-5220-a5e4-f8aa444dc294','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','1898f5a5-af8f-5e22-b21f-bb51f1e6fb2c','Which gas do plants absorb during photosynthesis?','medium',15,'The correct answer is Carbon dioxide.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('ed42ebb5-815c-53e7-8489-6f11a054f7da','5b7988ec-1c7d-5220-a5e4-f8aa444dc294','Carbon dioxide',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('976d70a9-0a12-5162-bfdc-8ae2d1ed2470','5b7988ec-1c7d-5220-a5e4-f8aa444dc294','Oxygen',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1ac18170-c8cd-52a8-af60-c9454ad657c5','5b7988ec-1c7d-5220-a5e4-f8aa444dc294','Nitrogen',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8b2e717d-38a9-5bb2-b384-50b442183e8f','5b7988ec-1c7d-5220-a5e4-f8aa444dc294','Hydrogen',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('b35827dd-4408-5b1a-b864-274a682f6dd0','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','Which organ pumps blood through the human body?','hard',15,'The correct answer is Heart.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('df8292c7-4c66-5923-ae22-883f69a61c68','b35827dd-4408-5b1a-b864-274a682f6dd0','Heart',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('5ff7432f-2198-5da9-99ac-9240ffb67fad','b35827dd-4408-5b1a-b864-274a682f6dd0','Liver',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('2c39f627-8552-5878-b7d2-16adaa7c5057','b35827dd-4408-5b1a-b864-274a682f6dd0','Lungs',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d3b6b34c-bf7f-5581-bed8-fb708c5c027f','b35827dd-4408-5b1a-b864-274a682f6dd0','Kidneys',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('d87b660b-4cc7-5707-85e9-45d885c4d065','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','c48ff9f3-c397-56fe-8ffd-e8af52ca6db0','What is the SI unit of electric current?','easy',15,'The correct answer is Ampere.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d0388e98-4a15-55e5-a8df-4c53b3dcb667','d87b660b-4cc7-5707-85e9-45d885c4d065','Ampere',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f38d1fc8-2011-5577-96e7-7ff73aa1ce0b','d87b660b-4cc7-5707-85e9-45d885c4d065','Volt',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b8ecbce0-6a88-5a67-8482-86bc8118720b','d87b660b-4cc7-5707-85e9-45d885c4d065','Ohm',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('3bf2078e-c514-526e-b5ac-15b091b28930','d87b660b-4cc7-5707-85e9-45d885c4d065','Watt',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('f6ed569f-cf5f-57b3-8d09-86a49824f1ea','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','1898f5a5-af8f-5e22-b21f-bb51f1e6fb2c','Which vitamin is produced by skin exposed to sunlight?','medium',15,'The correct answer is Vitamin D.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b5666185-93a4-5e69-adcd-28e3318e9e0a','f6ed569f-cf5f-57b3-8d09-86a49824f1ea','Vitamin D',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('9e9ef4ab-60a7-5b99-a17d-5573f550c91e','f6ed569f-cf5f-57b3-8d09-86a49824f1ea','Vitamin A',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b878993c-9812-5615-af99-5a3d418ddcac','f6ed569f-cf5f-57b3-8d09-86a49824f1ea','Vitamin B12',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('51eae27e-d0c7-539e-b2c9-5c84387d5bc3','f6ed569f-cf5f-57b3-8d09-86a49824f1ea','Vitamin C',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('be1a0194-cfbc-57b6-93ff-9635e902a089','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','What is the chemical formula of water?','easy',15,'The correct answer is H₂O.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('29d1b55c-2942-5d11-88dc-bef5c1abe3c5','be1a0194-cfbc-57b6-93ff-9635e902a089','H₂O',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f0c384b8-1405-5087-97be-d62a54deaece','be1a0194-cfbc-57b6-93ff-9635e902a089','CO₂',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('27a05141-a74d-598a-a212-8bfc75720023','be1a0194-cfbc-57b6-93ff-9635e902a089','NaCl',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6be91556-0513-5829-978b-ad88253305ce','be1a0194-cfbc-57b6-93ff-9635e902a089','O₂',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('d0726fb3-c0ce-58ac-a458-222ee487234b','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','c48ff9f3-c397-56fe-8ffd-e8af52ca6db0','Which planet is known as the Red Planet?','medium',15,'The correct answer is Mars.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('98af20d6-b168-50c0-a194-8e55f53bf37a','d0726fb3-c0ce-58ac-a458-222ee487234b','Mars',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('42588a46-29d7-5460-bbd5-bf9058ecdfec','d0726fb3-c0ce-58ac-a458-222ee487234b','Venus',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7ba0b69f-dad6-5168-a25b-cbab53bb3e43','d0726fb3-c0ce-58ac-a458-222ee487234b','Jupiter',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('5fcda1a6-5072-5041-8916-7f0d2697e4c4','d0726fb3-c0ce-58ac-a458-222ee487234b','Mercury',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('efe1a110-0b5a-50cb-9355-72a0823fe2c8','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','1898f5a5-af8f-5e22-b21f-bb51f1e6fb2c','What is the closest star to Earth?','hard',15,'The correct answer is The Sun.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('c3bdd81b-d876-5851-b29f-8c931f410ead','efe1a110-0b5a-50cb-9355-72a0823fe2c8','The Sun',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('53b20dc3-b51e-55a9-9665-b2226e118ac8','efe1a110-0b5a-50cb-9355-72a0823fe2c8','Sirius',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('f136de6d-bd94-58d1-9932-9acf448b9de0','efe1a110-0b5a-50cb-9355-72a0823fe2c8','Polaris',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('dddc2e26-0eb9-57b2-8956-f6df754c712c','efe1a110-0b5a-50cb-9355-72a0823fe2c8','Proxima Centauri',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('3c7d0e6f-e6fc-5a8c-8598-25f8897f2a89','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','Which blood cells primarily carry oxygen?','easy',15,'The correct answer is Red blood cells.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('bad828b6-a786-59fa-b6f6-a8df9f8d5f59','3c7d0e6f-e6fc-5a8c-8598-25f8897f2a89','Red blood cells',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('dadd485e-fe36-5342-872c-b2ce1d03d0a8','3c7d0e6f-e6fc-5a8c-8598-25f8897f2a89','White blood cells',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('63c08920-364a-52de-a734-5acbbbaf8bc5','3c7d0e6f-e6fc-5a8c-8598-25f8897f2a89','Platelets',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('1ba0c787-d789-55f0-8e13-c221196dd09b','3c7d0e6f-e6fc-5a8c-8598-25f8897f2a89','Stem cells',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('fa141fda-1060-5167-81e9-4832104ead47','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','c48ff9f3-c397-56fe-8ffd-e8af52ca6db0','Which part of the cell contains most genetic material?','medium',15,'The correct answer is Nucleus.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b0d6ecd5-2f54-5f11-8e5b-b5a5a56d51c7','fa141fda-1060-5167-81e9-4832104ead47','Nucleus',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('dcffcd77-ba16-5884-b306-a5d16a682540','fa141fda-1060-5167-81e9-4832104ead47','Ribosome',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('8674d582-86a5-5f19-8933-62b49255bf29','fa141fda-1060-5167-81e9-4832104ead47','Cell membrane',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b7b74354-6c03-58b9-887e-582a25b1d250','fa141fda-1060-5167-81e9-4832104ead47','Cytoplasm',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('1fed6ba3-ce8d-503f-9071-77a59a4c1e1e','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','1898f5a5-af8f-5e22-b21f-bb51f1e6fb2c','What is the SI unit of power?','easy',15,'The correct answer is Watt.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('264c1d83-fd92-5b8b-ba25-febbb97e913f','1fed6ba3-ce8d-503f-9071-77a59a4c1e1e','Watt',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('5ef5ff3e-b701-57c9-8294-0b974e287026','1fed6ba3-ce8d-503f-9071-77a59a4c1e1e','Newton',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7954cdff-c600-5ad0-b7c2-ad6c114ee7e7','1fed6ba3-ce8d-503f-9071-77a59a4c1e1e','Joule',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('413692ee-c011-5468-8836-5b79cb0cd156','1fed6ba3-ce8d-503f-9071-77a59a4c1e1e','Volt',false,2) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('b8ea0d4e-041e-545e-9fcf-fe92d4bc3c39','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','What is the normal boiling point of water at sea level?','medium',15,'The correct answer is 100°C.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('cbf776b5-45f0-5ea2-857d-fb82fa119160','b8ea0d4e-041e-545e-9fcf-fe92d4bc3c39','100°C',true,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b4ed082e-2294-5cd3-9309-a6277a9cee06','b8ea0d4e-041e-545e-9fcf-fe92d4bc3c39','90°C',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('d6229b53-a36f-5665-acee-852aa35ae547','b8ea0d4e-041e-545e-9fcf-fe92d4bc3c39','110°C',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('95491442-df97-5826-b344-892015f0947d','b8ea0d4e-041e-545e-9fcf-fe92d4bc3c39','120°C',false,3) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('6d030dbe-91a1-564f-9995-71ea734e3eee','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','c48ff9f3-c397-56fe-8ffd-e8af52ca6db0','Which gas makes up the largest share of Earth’s atmosphere?','hard',15,'The correct answer is Nitrogen.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('defc53a2-79ec-5262-9d99-7b738c68c6fb','6d030dbe-91a1-564f-9995-71ea734e3eee','Nitrogen',true,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('5fa92b9c-6056-5d63-8101-7ebc7b029ce0','6d030dbe-91a1-564f-9995-71ea734e3eee','Oxygen',false,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('6dacd802-3dbe-5d5e-87eb-0df4bcab4c6c','6d030dbe-91a1-564f-9995-71ea734e3eee','Carbon dioxide',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('10630138-920a-58d8-8e1e-90e6d3b9df36','6d030dbe-91a1-564f-9995-71ea734e3eee','Argon',false,0) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('305c8ef1-2aea-5f4a-bcfc-26ed84a0af5a','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','1898f5a5-af8f-5e22-b21f-bb51f1e6fb2c','Which acid is found in the human stomach?','easy',15,'The correct answer is Hydrochloric acid.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('7984a203-556b-5071-b2f4-ff699471d2b4','305c8ef1-2aea-5f4a-bcfc-26ed84a0af5a','Hydrochloric acid',true,2) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('b70f1de7-9342-5b49-acf3-a59a310e6d35','305c8ef1-2aea-5f4a-bcfc-26ed84a0af5a','Sulfuric acid',false,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('4b449197-cc91-5881-bd44-57e9e02c49b6','305c8ef1-2aea-5f4a-bcfc-26ed84a0af5a','Nitric acid',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('043809ff-b5ba-58cd-9f6b-1a86ba016507','305c8ef1-2aea-5f4a-bcfc-26ed84a0af5a','Acetic acid',false,1) on conflict(id) do nothing;
insert into public.questions(id,category_id,subtopic_id,question_text,difficulty,time_limit_seconds,explanation,status) values ('7edb0c2b-7c36-53f6-a970-b37e96973b44','b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','cc5778cf-3f8a-5a08-a217-1dbbb9473d1b','What is the approximate speed of light in a vacuum?','medium',15,'The correct answer is 300,000 km/s.','published') on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('46636374-ff12-55c9-b12d-a5a355f8de99','7edb0c2b-7c36-53f6-a970-b37e96973b44','300,000 km/s',true,3) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('12413d85-c84f-5af8-a1b5-924f2e014ca0','7edb0c2b-7c36-53f6-a970-b37e96973b44','30,000 km/s',false,0) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('5c9b8130-a818-5ce9-b2f9-212aadaaa41c','7edb0c2b-7c36-53f6-a970-b37e96973b44','3,000 km/s',false,1) on conflict(id) do nothing;
insert into public.question_options(id,question_id,option_text,is_correct,sort_order) values ('5f01dd45-9bd4-57a1-9e54-b5696083b7d9','7edb0c2b-7c36-53f6-a970-b37e96973b44','300 km/s',false,2) on conflict(id) do nothing;
insert into public.admin_users(email,role) values ('badushamc312@gmail.com','super_admin') on conflict(email) do nothing;
insert into public.app_settings(key,value) values ('search_timeout_seconds','20'::jsonb) on conflict(key) do nothing;
insert into public.app_settings(key,value) values ('questions_per_match','10'::jsonb) on conflict(key) do nothing;
insert into public.app_settings(key,value) values ('label_bots','true'::jsonb) on conflict(key) do nothing;
insert into public.app_settings(key,value) values ('maintenance_mode','false'::jsonb) on conflict(key) do nothing;
insert into public.app_settings(key,value) values ('min_app_version','"0.1.0"'::jsonb) on conflict(key) do nothing;
insert into public.badges(slug,name,milestone) values ('streak-3','3-day streak',3) on conflict(slug) do nothing;
insert into public.badges(slug,name,milestone) values ('streak-7','7-day streak',7) on conflict(slug) do nothing;
insert into public.badges(slug,name,milestone) values ('streak-30','30-day streak',30) on conflict(slug) do nothing;
insert into public.badges(slug,name,milestone) values ('streak-100','100-day streak',100) on conflict(slug) do nothing;
commit;


commit;
