begin;

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
commit;
