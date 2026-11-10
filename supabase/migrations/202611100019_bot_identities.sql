begin;

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
commit;
