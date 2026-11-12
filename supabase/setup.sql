-- SJ E-Learning: first installation only. Do not rerun over an existing project.
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


-- 202611110022_shared_player_portraits.sql

-- Google may provide its picture under either metadata key. Keep existing
-- learner-selected pictures when filling gaps on older profiles.
create or replace function sj_private.new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,auth_user_id,full_name,email,avatar_url)
 values(new.id,new.id,left(coalesce(new.raw_user_meta_data->>'full_name',''),50),lower(new.email),
   coalesce(nullif(new.raw_user_meta_data->>'avatar_url',''),nullif(new.raw_user_meta_data->>'picture','')));
 return new;
end $$;

update public.profiles p
set avatar_url=coalesce(nullif(u.raw_user_meta_data->>'avatar_url',''),nullif(u.raw_user_meta_data->>'picture',''))
from auth.users u
where p.auth_user_id=u.id and p.avatar_url is null
  and coalesce(nullif(u.raw_user_meta_data->>'avatar_url',''),nullif(u.raw_user_meta_data->>'picture',''))
    like 'https://%.googleusercontent.com/%';

-- Gallery thumbnails remain private table data, but any signed-in learner can
-- fetch the current picture of another player. Old match_id callers still work.
create or replace function public.get_player_photo(photo_id uuid, match_id uuid default null)
returns text language sql stable security definer set search_path='' as $$
 select replace(encode(f.thumbnail,'base64'),chr(10),'')
 from sj_private.player_photos f
 join public.profiles p on p.id=f.owner_id
 where f.photo_id=get_player_photo.photo_id
   and p.avatar_url='photo:'||f.photo_id::text
   and p.deleted_at is null
   and auth.uid() is not null
$$;

-- A match participant receives the same picture reference for Google,
-- gallery, preset and bot avatars. Answer visibility rules stay unchanged.
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
 'players',(select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'level',p.level,'avatar_url',p.avatar_url,'rating',mp.rating_before,'score',coalesce((select sum(points) from public.match_answers a join public.match_questions q on q.match_id=a.match_id and q.question_index=a.question_index where a.match_id=m.id and a.user_id=p.id and q.revealed_at is not null),0),
 'rating_after',mp.rating_after,'xp_gained',mp.xp_gained,'result',mp.result,'connected',p.is_bot or mp.heartbeat_at>now()-interval '5 seconds')) from public.match_players mp join public.profiles p on p.id=mp.user_id where mp.match_id=m.id),
 'question',case when mq.started_at is null then null else sj_private.safe_question(mq.snapshot)||jsonb_build_object('started_at',mq.started_at,'deadline_at',mq.deadline_at) end,
 'answered',(select coalesce(jsonb_agg(a.user_id),'[]') from public.match_answers a where a.match_id=m.id and a.question_index=m.current_question_index),
 'result',case when mq.revealed_at is not null then jsonb_build_object('correct_option_id',mq.snapshot->>'correct_option_id','explanation',mq.snapshot->>'explanation',
 'answers',(select coalesce(jsonb_agg(jsonb_build_object('user_id',a.user_id,'option_id',a.option_id,'points',a.points)),'[]') from public.match_answers a where a.match_id=m.id and a.question_index=m.current_question_index)) else null end);
end $$;

create or replace function sj_private.match_player_report(mid uuid, participant uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',p.id,'full_name',p.full_name,'is_bot',p.is_bot,
 'avatar_url',p.avatar_url,
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

create or replace function public.get_leaderboard(type text default 'all_time', category_id uuid default null, result_limit int default 100) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); rows jsonb;
begin
 if type not in ('all_time','weekly','daily') then raise exception 'INVALID_LEADERBOARD'; end if;
 with ranked as (
 select p.id,p.full_name,p.level,p.rating,p.trophies,p.avatar_url,
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

create or replace function public.get_history_page(before_at timestamptz default null, before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid=sj_private.require_player();
begin
 if (before_at is null)<>(before_id is null) then raise exception 'INVALID_CURSOR'; end if;
 return jsonb_build_object('rows',(select coalesce(jsonb_agg(r order by r.played_at desc,r.id desc),'[]') from (
 select * from (
  select m.id,'battle'::text mode,m.created_at played_at,mp.score,mp.result,
   opponent.full_name title,opponent.avatar_url
  from public.match_players mp join public.matches m on m.id=mp.match_id
  join public.profiles opponent on opponent.id=case when m.player1_id=uid then m.player2_id else m.player1_id end
  where mp.user_id=uid and m.status='completed'
  union all
  select p.id,'practice',p.started_at,p.score,null,'Practice',null::text from public.practice_attempts p where p.user_id=uid and p.completed_at is not null
  union all
  select a.id,'daily',a.started_at,a.score,null,c.title,null::text from public.daily_attempts a join public.daily_challenges c on c.id=a.challenge_id
  where a.user_id=uid and a.completed_at is not null
 ) history where before_at is null or (played_at,id)<(before_at,before_id)
 order by played_at desc,id desc limit 30) r));
end $$;

create or replace function public.admin_user_page(search text default '', after_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('rows',(select coalesce(jsonb_agg(u order by u.id),'[]') from (
   select p.id,p.full_name,p.avatar_url,p.username,p.email,p.phone,p.target_exam,p.rating,p.xp,p.level,p.current_streak,p.best_streak,
     p.last_daily_date,p.profile_completed,p.is_banned,p.created_at,p.updated_at,
     coalesce((select a.role from public.admin_users a where a.is_active and a.email=p.email),'student') role
   from public.profiles p where not p.is_bot and p.deleted_at is null and (after_id is null or p.id>after_id)
     and (search='' or concat_ws(' ',p.full_name,p.email,p.phone) ilike '%'||search||'%')
   order by p.id limit 100
 ) u));
end $$;


-- 202611110023_question_catalog_reset.sql
-- Replace the question bank and topic catalog. Historical attempts retain snapshots.

-- Reports refer to removed questions; retain their original text for staff review.
alter table public.question_reports add column if not exists question_snapshot text;
update public.question_reports r set question_snapshot=q.question_text
from public.questions q where q.id=r.question_id and r.question_snapshot is null;
alter table public.question_reports alter column question_id drop not null;
alter table public.question_reports drop constraint if exists question_reports_question_id_fkey;
alter table public.question_reports add constraint question_reports_question_id_fkey
  foreign key (question_id) references public.questions(id) on delete set null;

update public.match_questions set question_id=null where question_id is not null;
update public.daily_challenge_questions set question_id=null where question_id is not null;
update public.matchmaking_queue set subtopic_id=null where subtopic_id is not null;
-- Keep historical challenges and attempts but never offer retired snapshots anew.
update public.daily_challenges set status='draft' where exists
  (select 1 from public.daily_challenge_questions q where q.challenge_id=daily_challenges.id);
delete from public.questions;
delete from public.subtopics;

-- Remove unplayed scheduled challenges built from the retired question bank.
delete from public.daily_challenges d where not exists
  (select 1 from public.daily_attempts a where a.challenge_id=d.id);

insert into public.categories(id,name,slug,icon,color_hex,sort_order) values
 ('668395b5-5411-5b0b-99a5-5efa80c18faf','Quantitative Aptitude','quant','calculate','#376BD6',0),
 ('09f88e78-88be-547c-9eb8-ef644b66db02','Reasoning','reasoning','psychology','#8051C5',1),
 ('b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','General Awareness','general-awareness','public','#B66A13',2),
 ('d2c9217b-d3a7-5a4a-9815-c33704a25aff','English','english','translate','#087E83',3)
on conflict(slug) do nothing;

insert into public.subtopics(category_id,name,sort_order)
select c.id,t.name,t.position-1 from public.categories c
join (values
 ('quant',array['Number System','Percentage','Ratio & Proportion','Profit & Loss','Average','Time & Work','Time, Speed & Distance','Simple & Compound Interest','Algebra','Geometry','Trigonometry','Mensuration','Data Interpretation','Simplification','Surds & Indices']),
 ('reasoning',array['Analogy','Classification','Series','Coding-Decoding','Blood Relations','Direction Sense','Syllogism','Venn Diagrams','Seating Arrangement','Puzzles','Mirror & Water Image','Paper Folding & Cutting','Statement & Conclusion','Missing Number','Mathematical Operations']),
 ('general-awareness',array['Indian History','Indian Polity','Geography','Economics','Physics','Chemistry','Biology','Computer Awareness','Current Affairs','Static GK','Awards & Honours','Books & Authors','Important Days','Sports']),
 ('english',array['Vocabulary','Grammar','Comprehension','Synonyms & Antonyms','Idioms & Phrases','One Word Substitution','Sentence Correction','Fill in the Blanks','Cloze Test','Spelling Errors','Active & Passive Voice','Direct & Indirect Speech'])
) as catalog(slug,names) on c.slug=catalog.slug
cross join lateral unnest(catalog.names) with ordinality as t(name,position);

create or replace function sj_private.normalize_import_name(raw text) returns text
language sql immutable set search_path='' as $$
  select regexp_replace(lower(coalesce(raw,'')),'[^a-z0-9]','','g')
$$;

create or replace function sj_private.name_distance(a text,b text) returns int
language plpgsql immutable set search_path='' as $$
declare i int; j int; previous int[]; current_row int[]; cost int;
begin
 if a=b then return 0; end if;
 previous=array(select generate_series(0,length(b)));
 for i in 1..length(a) loop
   current_row=array[i];
   for j in 1..length(b) loop
     cost=case when substr(a,i,1)=substr(b,j,1) then 0 else 1 end;
     current_row=array_append(current_row,least(current_row[j]+1,previous[j+1]+1,previous[j]+cost));
   end loop;
   previous=current_row;
 end loop;
 return previous[length(b)+1];
end $$;

create or replace function sj_private.resolve_import_name(raw text, parent uuid default null) returns uuid
language plpgsql stable security definer set search_path='' as $$
declare key text=sj_private.normalize_import_name(raw); resolved uuid; best int; runner_up int; allowance int;
begin
 if key='' then return null; end if;
 -- Explicit common names are safer than guessing across similarly named topics.
 key=case
   when parent is null and key in ('math','maths','mathematics','quant','quantitative','quantitativeaptitude') then 'quantitativeaptitude'
   when parent is null and key in ('gk','generalknowledge','generalscience','ga') then 'generalawareness'
   when parent is null and key in ('reason','logicalreasoning') then 'reasoning'
   when parent is not null and key='percentages' then 'percentage'
   when parent is not null and key='numbersystems' then 'numbersystem'
   when parent is not null and key='averages' then 'average'
   when parent is not null and key='ratio' then 'ratioproportion'
   when parent is not null and key in ('sici','simpleinterest','compoundinterest') then 'simplecompoundinterest'
   when parent is not null and key='speedanddistance' then 'timespeeddistance'
   when parent is not null and key='history' then 'indianhistory'
   when parent is not null and key='polity' then 'indianpolity'
   when parent is not null and key='analogies' then 'analogy'
   when parent is not null and key='syllogisms' then 'syllogism'
   when parent is not null and key='seatingarrangements' then 'seatingarrangement'
   when parent is not null and key='readingcomprehension' then 'comprehension'
   when parent is not null and key='grammarrules' then 'grammar'
   else key end;
 if parent is null then
   select id into resolved from public.categories c where c.is_active and
     (sj_private.normalize_import_name(c.name)=key or sj_private.normalize_import_name(c.slug)=key) limit 1;
 else
   select id into resolved from public.subtopics s where s.category_id=parent and s.is_active
     and sj_private.normalize_import_name(s.name)=key limit 1;
 end if;
 if resolved is not null then return resolved; end if;
 allowance=case when length(key)<6 then 1 when length(key)<12 then 2 else 3 end;
 if parent is null then
   select id,distance into resolved,best from
     (select c.id,sj_private.name_distance(key,sj_private.normalize_import_name(c.name)) distance
      from public.categories c where c.is_active order by distance,c.id limit 1) ranked;
   select min(sj_private.name_distance(key,sj_private.normalize_import_name(c.name))) into runner_up
     from public.categories c where c.is_active and c.id<>resolved;
 else
   select id,distance into resolved,best from
     (select s.id,sj_private.name_distance(key,sj_private.normalize_import_name(s.name)) distance
      from public.subtopics s where s.is_active and s.category_id=parent order by distance,s.id limit 1) ranked;
   select min(sj_private.name_distance(key,sj_private.normalize_import_name(s.name))) into runner_up
     from public.subtopics s where s.is_active and s.category_id=parent and s.id<>resolved;
 end if;
 if best<=allowance and (runner_up is null or best<runner_up) then return resolved; end if;
 return null;
end $$;

create or replace function public.admin_save_question(payload jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare qid uuid=coalesce((payload->>'id')::uuid,gen_random_uuid()); before_data jsonb;
  opt jsonb; idx int; distinct_options int; category uuid=(payload->>'category_id')::uuid;
  topic uuid=(payload->>'subtopic_id')::uuid; difficulty text=lower(trim(payload->>'difficulty'));
begin
 perform sj_private.require_admin('editor');
 if category is null or topic is null or not exists
   (select 1 from public.subtopics s join public.categories c on c.id=s.category_id
    where s.id=topic and s.category_id=category and s.is_active and c.is_active)
 then raise exception 'VALID_SUBJECT_AND_TOPIC_REQUIRED'; end if;
 if length(trim(coalesce(payload->>'question_text','')))<4 or difficulty not in ('easy','medium','hard')
 then raise exception 'INVALID_QUESTION_OR_DIFFICULTY'; end if;
 if jsonb_typeof(payload->'options') is distinct from 'array' or jsonb_array_length(payload->'options')<>4
 then raise exception 'FOUR_OPTIONS_REQUIRED'; end if;
 select count(*) filter(where (value->>'is_correct')::boolean),
   count(distinct lower(trim(value->>'option_text'))) into idx,distinct_options
 from jsonb_array_elements(payload->'options');
 if idx<>1 or distinct_options<>4 or exists
   (select 1 from jsonb_array_elements(payload->'options') where length(trim(coalesce(value->>'option_text','')))=0)
 then raise exception 'ONE_CORRECT_AND_UNIQUE_OPTIONS_REQUIRED'; end if;
 select to_jsonb(q) into before_data from public.questions q where id=qid for update;
 if before_data is not null and (exists(select 1 from public.match_questions where question_id=qid)
   or exists(select 1 from public.daily_challenge_questions where question_id=qid))
 then raise exception 'QUESTION_ALREADY_USED_DUPLICATE_INSTEAD'; end if;
 insert into public.questions(id,category_id,subtopic_id,question_text,image_url,difficulty,
   time_limit_seconds,explanation,status,created_by,exam)
 values(qid,category,topic,trim(payload->>'question_text'),payload->>'image_url',difficulty,
   15,coalesce(trim(payload->>'explanation'),''),'published',auth.uid(),null)
 on conflict(id) do update set category_id=excluded.category_id,subtopic_id=excluded.subtopic_id,
   question_text=excluded.question_text,image_url=excluded.image_url,difficulty=excluded.difficulty,
   time_limit_seconds=15,explanation=excluded.explanation,status='published',exam=null;
 delete from public.question_options where question_id=qid;
 idx=0;
 for opt in select value from jsonb_array_elements(payload->'options') loop
   insert into public.question_options(question_id,option_text,is_correct,sort_order)
   values(qid,trim(opt->>'option_text'),(opt->>'is_correct')::boolean,idx);
   idx=idx+1;
 end loop;
 perform sj_private.audit('save','questions',qid::text,jsonb_build_object('before',before_data,'after',payload));
 return qid;
end $$;

create or replace function public.admin_import_questions(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare item jsonb; row_num int=0; category uuid; topic uuid; choice text; difficulty text;
  opts jsonb; fingerprint text=md5(payload::text); previous int; column_name text;
begin
 perform sj_private.require_admin('editor');
 if jsonb_typeof(payload->'questions') is distinct from 'array' then raise exception 'Expected a questions array'; end if;
 if jsonb_array_length(payload->'questions') not between 1 and 500 then raise exception 'Use 1–500 questions per file'; end if;
 perform pg_advisory_xact_lock(hashtext('sj_question_import'));
 select item_count into previous from sj_private.question_imports where batch_hash=fingerprint;
 if found then return jsonb_build_object('imported',previous,'already_imported',true); end if;
 for item in select value from jsonb_array_elements(payload->'questions') loop
   row_num=row_num+1;
   foreach column_name in array array['question','option_a','option_b','option_c','option_d','correct_answer','subject','topic','difficulty'] loop
     if jsonb_typeof(item->column_name) is distinct from 'string' or trim(item->>column_name)=''
     then raise exception 'Question %: supply %',row_num,column_name; end if;
   end loop;
   choice=upper(trim(item->>'correct_answer'));
   difficulty=lower(trim(item->>'difficulty'));
   if choice not in ('A','B','C','D') or difficulty not in ('easy','medium','hard') or length(trim(item->>'question'))<4
   then raise exception 'Question %: check question text, correct_answer (A–D) and difficulty',row_num; end if;
   category=sj_private.resolve_import_name(item->>'subject');
   if category is null then raise exception 'Question %: unknown subject "%"',row_num,item->>'subject'; end if;
   topic=sj_private.resolve_import_name(item->>'topic',category);
   if topic is null then raise exception 'Question %: unknown topic "%" for subject "%"',row_num,item->>'topic',item->>'subject'; end if;
   select jsonb_agg(jsonb_build_object('option_text',trim(item->>('option_'||l)),'is_correct',upper(l)=choice) order by l)
     into opts from unnest(array['a','b','c','d']) l;
   if (select count(distinct lower(o->>'option_text')) from jsonb_array_elements(opts) o)<>4
   then raise exception 'Question %: options must be different',row_num; end if;
   perform public.admin_save_question(jsonb_build_object('category_id',category,'subtopic_id',topic,
     'question_text',trim(item->>'question'),'difficulty',difficulty,
     'explanation',coalesce(trim(item->>'explanation'),''),'options',opts));
 end loop;
 insert into sj_private.question_imports values(fingerprint,row_num);
 return jsonb_build_object('imported',row_num,'already_imported',false);
end $$;

-- Existing import hashes referred to questions that have now been removed.
delete from sj_private.question_imports;
revoke all on function sj_private.normalize_import_name(text),sj_private.name_distance(text,text),
  sj_private.resolve_import_name(text,uuid) from public,anon,authenticated;
create or replace function public.admin_reports() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform sj_private.require_admin();
 return jsonb_build_object('reports',(select coalesce(jsonb_agg(row),'[]'::jsonb) from
   (select r.*,coalesce(q.question_text,r.question_snapshot) question_text
    from public.question_reports r left join public.questions q on q.id=r.question_id
    order by r.created_at desc limit 100) row));
end $$;
create or replace function public.get_today_challenge() returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=sj_private.require_player(); day date=(now() at time zone 'Asia/Kolkata')::date;
  cid uuid; available_count int;
begin
 select count(*) into available_count from public.questions where status='published';
 if available_count<10 then return jsonb_build_object('available',false,'question_count',0); end if;
 cid=sj_private.generate_daily(day);
 return coalesce((select jsonb_build_object('available',true,'id',c.id,'title',c.title,
   'challenge_date',c.challenge_date,
   'question_count',(select count(*) from public.daily_challenge_questions where challenge_id=cid),
   'completed',coalesce(a.completed_at is not null,false),'started',a.id is not null,
   'score',a.score,'resets_at',(day+1)::timestamp at time zone 'Asia/Kolkata')
   from public.daily_challenges c left join public.daily_attempts a
   on a.challenge_id=c.id and a.user_id=uid
   where c.id=cid and c.status in ('published','scheduled')),
   jsonb_build_object('available',false,'question_count',0));
end $$;

-- 202611120024_player_bot_shuffle.sql

-- Bot identities need stable profile IDs: a new profile per match cannot be
-- rotated fairly. Preserve existing profiles because match history refers to them.
insert into public.profiles(full_name,is_bot,rating,level,avatar_url)
select n.name,true,0,n.experience_level,'color:'||n.avatar_color
from sj_private.bot_names n
where not exists (select 1 from public.profiles p where p.is_bot and p.full_name=n.name);

-- New identities added to the private catalog become selectable without a
-- client release. Bots added directly to profiles are selectable as well.
create function sj_private.create_bot_profile() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if not exists (select 1 from public.profiles p where p.is_bot and p.full_name=new.name) then
  insert into public.profiles(full_name,is_bot,rating,level,avatar_url)
  values(new.name,true,0,new.experience_level,'color:'||new.avatar_color);
 end if;
 return new;
end $$;
create trigger bot_name_to_profile after insert on sj_private.bot_names
for each row execute function sj_private.create_bot_profile();

create function sj_private.disable_removed_bot_name() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 update public.profiles set is_banned=true where is_bot and full_name=old.name;
 return old;
end $$;
create trigger removed_bot_name after delete on sj_private.bot_names
for each row execute function sj_private.disable_removed_bot_name();

create index profiles_available_bots on public.profiles(id) where is_bot and not is_banned and deleted_at is null;

-- One row per real player, regardless of the number of bots or matches.
create table public.player_bot_cycles (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 bot_ids uuid[] not null default '{}'::uuid[],
 next_index integer not null default 0 check(next_index >= 0 and next_index <= cardinality(bot_ids)),
 updated_at timestamptz not null default now()
);
alter table public.player_bot_cycles enable row level security;
revoke all on public.player_bot_cycles from public,anon,authenticated;

-- Deleted accounts retain anonymized match rows, but not their private cycle.
create function sj_private.clear_deleted_player_cycle() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 delete from public.player_bot_cycles where user_id=new.id;
 return new;
end $$;
create trigger clear_deleted_player_cycle after update of deleted_at on public.profiles
for each row when (old.deleted_at is null and new.deleted_at is not null)
execute function sj_private.clear_deleted_player_cycle();

-- This helper is called only inside start_bot_match's transaction. The cycle
-- row lock makes read/reconcile/advance atomic even if callers race.
create function sj_private.next_bot_for_player(player_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare
 active_ids uuid[];
 current_ids uuid[];
 remaining_ids uuid[];
 cycle public.player_bot_cycles;
 next_id uuid;
 new_id uuid;
 slot integer;
 insert_at integer;
begin
 select coalesce(array_agg(id order by id),'{}'::uuid[]) into active_ids
 from public.profiles where is_bot and not is_banned and deleted_at is null;
 if cardinality(active_ids)=0 then raise exception 'NO_BOTS_AVAILABLE'; end if;

 insert into public.player_bot_cycles(user_id) values(player_id) on conflict do nothing;
 select * into cycle from public.player_bot_cycles where user_id=player_id for update;

 -- Keep the used prefix until the cycle ends, so a bot disabled and later
 -- re-enabled cannot be selected twice in that same cycle. Remove unavailable
 -- bots only from the unused tail.
 select coalesce(array_agg(id order by ord) filter(where ord<=cycle.next_index),'{}'::uuid[]),
        coalesce(array_agg(id order by ord) filter(where ord>cycle.next_index and id=any(active_ids)),'{}'::uuid[])
 into current_ids,remaining_ids
 from unnest(cycle.bot_ids) with ordinality as saved(id,ord);

 if cardinality(remaining_ids)=0 then
  -- The previous cycle is complete (or every remaining bot was disabled).
  select array_agg(id order by random()) into current_ids from unnest(active_ids) as available(id);
  slot=0;
 else
  slot=cardinality(current_ids);
  current_ids=current_ids||remaining_ids;
  -- Insert each newly available bot at a random position in the unused tail.
  for new_id in select id from unnest(active_ids) as available(id)
                where not id=any(current_ids) order by id loop
   insert_at=slot+floor(random()*(cardinality(current_ids)-slot+1))::int;
   current_ids=coalesce(current_ids[1:insert_at],'{}'::uuid[]) || array[new_id] ||
               coalesce(current_ids[insert_at+1:cardinality(current_ids)],'{}'::uuid[]);
  end loop;
 end if;

 next_id=current_ids[slot+1];
 update public.player_bot_cycles set bot_ids=current_ids,next_index=slot+1,updated_at=now()
 where user_id=player_id;
 return next_id;
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
 bot=sj_private.next_bot_for_player(uid);
 mid=sj_private.new_match(uid,bot,mine.category_id,case when mine.joined_at<now()-interval '8 seconds' then null else mine.subtopic_id end,'bot');
 return jsonb_build_object('match_id',mid);
end $$;

revoke all on function sj_private.create_bot_profile(),sj_private.disable_removed_bot_name(),sj_private.clear_deleted_player_cycle(),sj_private.next_bot_for_player(uuid) from public,anon,authenticated;

-- Seed
-- Development seed: accounts, settings and badges only. Question catalog comes from migrations; questions are added by staff.

insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('668395b5-5411-5b0b-99a5-5efa80c18faf','Quantitative Aptitude','quant','calculate','#376BD6',0) on conflict(id) do nothing;
insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('d2c9217b-d3a7-5a4a-9815-c33704a25aff','English','english','translate','#087E83',1) on conflict(id) do nothing;
insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('09f88e78-88be-547c-9eb8-ef644b66db02','Reasoning','reasoning','psychology','#8051C5',2) on conflict(id) do nothing;
insert into public.categories(id,name,slug,icon,color_hex,sort_order) values ('b53dbb09-44ec-5cfa-aea5-9b5d62fcaa65','General Awareness','general-awareness','public','#B66A13',3) on conflict(id) do nothing;
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
