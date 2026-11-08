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
