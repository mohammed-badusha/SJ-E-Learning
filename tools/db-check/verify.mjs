import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const root=fileURLToPath(new URL('../../',import.meta.url));
const db=new PGlite();
await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
create schema auth; create schema realtime;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth,realtime to authenticated; grant execute on function auth.uid() to authenticated;
create table realtime.messages(id int,topic text); alter table realtime.messages enable row level security;
create function realtime.topic() returns text language sql stable as $$ select current_setting('realtime.topic',true) $$;
create table realtime.sent(topic text,event text,payload jsonb);
create function realtime.send(payload jsonb,event text,topic text,private boolean) returns void language sql as $$ insert into realtime.sent values(topic,event,payload) $$;`);
for(const f of (await readdir(root+'supabase/migrations')).sort()) {
 if(f.includes('scheduler')) continue; // pg_cron needs the actual Supabase server; never mock its execution.
 try { await db.exec(await readFile(root+'supabase/migrations/'+f,'utf8')); console.log('Migration OK:',f); }
 catch(e) {console.error('MIGRATION FAILED:',f,e.message); process.exit(1);}
}
try { await db.exec(await readFile(root+'supabase/seed.sql','utf8')); } catch(e) {console.error('SEED FAILED:',e.message);process.exit(1);}
console.log('Seed OK');
const ids=['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333','44444444-4444-4444-8444-444444444444'];
for(let i=0;i<ids.length;i++) await db.query(`insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data) values($1,$2,now(),'{"provider":"google"}')`,[ids[i],i===2?'badushamc312@gmail.com':`student${i}@example.com`]);
let tests=0;
async function test(name,fn) { try {await fn(); console.log('PASS',name);tests++;} catch(e) {console.error('FAIL',name,e.message, e.where ?? '');process.exit(1);} }
async function asUser(i,fn) {
 await db.exec(`set role authenticated; set request.jwt.claim.sub='${ids[i]}';`);
 try {return await fn();} finally {await db.exec('reset role;');}
}
async function q(sql,params=[]) {return (await db.query(sql,params)).rows;}
async function rejects(fn,pattern) {await assert.rejects(fn,pattern);}
await test('Unfinished profiles cannot start a game',()=>asUser(0,()=>rejects(()=>q('select public.start_practice()'),/PROFILE_REQUIRED/)));
for(let i=0;i<3;i++) await asUser(i,()=>q('select public.complete_profile($1,$2)',[`Student ${i}`,`+91987654321${i}`]));
await test('New players start at zero trophies and cannot edit them',async()=>{
 assert.deepEqual((await q('select trophies from public.profiles where id=$1',[ids[0]]))[0],{trophies:0});
 await asUser(0,()=>rejects(()=>q('update public.profiles set trophies=100'),/can only be updated to DEFAULT|permission denied/i));
 assert.equal(Number((await asUser(0,()=>q("select metric from jsonb_to_recordset(public.get_leaderboard('all_time')->'rows') as x(id uuid,metric numeric) where id=$1",[ids[0]])))[0].metric),0);
});
await test('Duplicate phone numbers rejected',()=>asUser(3,()=>rejects(()=>q("select public.complete_profile('Duplicate Student','+919876543210')"),/PHONE_IN_USE/)));
await test('Invalid phone and short names rejected',()=>asUser(3,async()=>{
 await rejects(()=>q("select public.complete_profile('A','+919876543219')"),/INVALID_NAME/);
 await rejects(()=>q("select public.complete_profile('Student','+911234567890')"),/INVALID_PHONE/);
}));
await test('Students cannot read correct answers or question snapshots',()=>asUser(0,async()=>{
 await rejects(()=>q('select is_correct from public.question_options'),/permission denied/);
 await rejects(()=>q('select snapshot from public.match_questions'),/permission denied/);
 await rejects(()=>q('select * from public.bot_plans'),/permission denied/);
}));
await test('Students cannot modify rating or read another phone',()=>asUser(0,async()=>{
 await rejects(()=>q('update public.profiles set rating=9999'),/permission denied/);
 assert.equal((await q('select id,phone from public.profiles where id=$1',[ids[1]])).length,0);
}));
await test('Seeded admin recognized; normal account rejected',async()=>{
 assert.equal((await asUser(2,()=>q('select public.get_my_role() role')))[0].role,'super_admin');
 assert.equal((await asUser(0,()=>q('select public.get_my_role() role')))[0].role,'student');
 await asUser(0,()=>rejects(()=>q('select public.admin_dashboard()'),/ADMIN_REQUIRED/));
});
await test('Role revocation immediately denies privileged RPC',async()=>{
 await q("update public.admin_users set is_active=false where email='badushamc312@gmail.com'");
 await asUser(2,()=>rejects(()=>q('select public.admin_dashboard()'),/ADMIN_REQUIRED/));
 await q("update public.admin_users set is_active=true where email='badushamc312@gmail.com'");
});
let practice;
await test('Practice start strips answer key and explanation',async()=>{
 practice=(await asUser(0,()=>q('select public.start_practice() data')))[0].data;
 assert.equal(practice.question.correct_option_id,undefined);assert.equal(practice.question.explanation,undefined);
});
await test('First practice answer wins, retries idempotent; future question denied',async()=>{
 const params=[practice.attempt_id,0,practice.question.options[0].id];
 const first=(await asUser(0,()=>q('select public.submit_practice_answer($1,$2,$3) data',params)))[0].data;
 const second=(await asUser(0,()=>q('select public.submit_practice_answer($1,$2,$3) data',[...params.slice(0,2),practice.question.options[1].id])))[0].data;
 assert.deepEqual(first,second);
 await asUser(0,()=>rejects(()=>q('select public.get_practice_question($1,3)',[practice.attempt_id]),/QUESTION_NOT_ACTIVE/));
 await asUser(1,()=>rejects(()=>q('select public.get_practice_question($1,1)',[practice.attempt_id]),/ATTEMPT_NOT_FOUND/));
 await asUser(0,()=>q('select public.get_practice_question($1,1)',[practice.attempt_id]));
});
await test('Score caps, grace period floor and final double',async()=>{
 assert.equal((await q('select sj_private.score(true,0,15) s'))[0].s,20);
 assert.equal((await q('select sj_private.score(true,15500,15) s'))[0].s,10);
 assert.equal((await q('select sj_private.score(false,0,15,true) s'))[0].s,0);
 assert.equal((await q('select sj_private.score(true,0,15,true) s'))[0].s,40);
});
let mid;
await test('Two humans match exactly once and answer keys stay hidden',async()=>{
 const first=(await asUser(0,()=>q('select public.join_matchmaking() data')))[0].data;
 assert.equal(first.match_id,null);
 const second=(await asUser(1,()=>q('select public.join_matchmaking() data')))[0].data;
 mid=second.match_id;assert.ok(mid);
 const again=(await asUser(0,()=>q('select public.join_matchmaking() data')))[0].data;
 assert.equal(again.match_id,mid);
 assert.equal((await q('select count(*)::int c from public.matchmaking_queue'))[0].c,0);
 await asUser(2,()=>rejects(()=>q('select public.get_match_state($1)',[mid]),/MATCH_NOT_FOUND/));
 await q("update public.matches set next_tick_at=now()-interval '1 second' where id=$1",[mid]);
 await q('select sj_private.tick_match($1)',[mid]);
 const state=(await asUser(0,()=>q('select public.get_match_state($1) data',[mid])))[0].data;
 assert.equal(state.question.correct_option_id,undefined);assert.equal(state.result,null);
});
const photoFixture='iVBORw0KGgoAAAANSUhEUgAAAMAAAADACAAAAAB3tzPbAAAAO0lEQVR4nO3BMQEAAADCoPVPbQ0PoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgHcDkMAAAZ1kLtkAAAAASUVORK5CYII=';
const savePortrait=(i,portrait,data=null)=>asUser(i,()=>q('select public.save_profile_portrait($1,$2,$3,$4)',[`Student ${i}`,`+91987654321${i}`,portrait,data]));
const readPhoto=(i,photo,match=null)=>asUser(i,async()=>(await q('select public.get_player_photo($1,$2) data',[photo,match]))[0].data);
await test('Only owner or current rival can load gallery pixels; polls contain only a reference',async()=>{
 await savePortrait(0,'gallery',photoFixture);
 const state=(await asUser(1,()=>q('select public.get_match_state($1) data',[mid])))[0].data;
 const ref=state.players.find(p=>p.id===ids[0]).avatar_url;
 assert.match(ref,/^photo:/);assert.ok(!JSON.stringify(state).includes(photoFixture));
 const key=ref.slice(6);
 assert.equal(await readPhoto(0,key),photoFixture); assert.equal(await readPhoto(1,key,mid),photoFixture);
 assert.equal(await readPhoto(2,key,mid),null);assert.equal(await readPhoto(1,key),null);
 await savePortrait(0,'preset:curie');assert.equal(await readPhoto(0,key),null);
});
await test('Bad portraits roll back profile changes and originals are not retained after deletion',async()=>{
 await asUser(0,()=>rejects(()=>q("select public.save_profile_portrait('Changed Name','+919876543210','gallery','invalid!')"),/invalid|INVALID/i));
 assert.equal((await q('select full_name from public.profiles where id=$1',[ids[0]]))[0].full_name,'Student 0');
 await savePortrait(1,'gallery',photoFixture);
});
await test('Duplicate live submissions locked; result revealed only once both answer',async()=>{
 const state=(await asUser(0,()=>q('select public.get_match_state($1) data',[mid])))[0].data;
 const option=state.question.options[0].id;
 await asUser(0,()=>q('select public.submit_answer($1,0,$2)',[mid,option]));
 await asUser(0,()=>q('select public.submit_answer($1,0,$2)',[mid,state.question.options[1].id]));
 assert.equal((await q('select count(*)::int c from public.match_answers where match_id=$1',[mid]))[0].c,1);
 assert.equal((await asUser(0,()=>q('select public.get_match_state($1) data',[mid])))[0].data.result,null);
 await asUser(1,()=>q('select public.submit_answer($1,0,$2)',[mid,option]));
 assert.ok((await asUser(0,()=>q('select public.get_match_state($1) data',[mid])))[0].data.result.correct_option_id);
});
await test('Finalization idempotent and participant history protected',async()=>{
 await asUser(0,()=>q('select public.forfeit_match($1)',[mid]));
 const xp=(await q('select xp from public.profiles where id=$1',[ids[1]]))[0].xp;
 await q('select sj_private.finalize_match($1)',[mid]);
 assert.equal((await q('select xp from public.profiles where id=$1',[ids[1]]))[0].xp,xp);
 await asUser(2,()=>rejects(()=>q('select public.get_match_review($1)',[mid]),/REVIEW_UNAVAILABLE/));
});
await test('Human battle gives fifteen for a win and floors a loss at zero',async()=>{
 const players=await q('select user_id,result,rating_before,rating_after from public.match_players where match_id=$1',[mid]);
 const winner=players.find(p=>p.user_id===ids[1]);
 const loser=players.find(p=>p.user_id===ids[0]);
 assert.equal(winner.result,'win');assert.equal(winner.rating_after-winner.rating_before,15);
 assert.equal(loser.result,'loss');assert.equal(loser.rating_after,0);
 assert.equal((await q('select trophies from public.profiles where id=$1',[ids[1]]))[0].trophies,15);
 assert.equal((await q('select trophies from public.profiles where id=$1',[ids[0]]))[0].trophies,0);
});
await test('Weekly podium returns portraits for its three leaders only',async()=>{
 const rows=(await asUser(0,()=>q('select public.get_weekly_podium_portraits() data')))[0].data.rows;
 assert.equal(rows.length,3);
 assert.equal(new Set(rows.map(row=>row.id)).size,3);
 assert.ok(rows.every(row=>[ids[0],ids[1],ids[2]].includes(row.id)));
 assert.equal(rows.find(row=>row.id===ids[1]).photo_png,photoFixture);
});
await test('Bot wins award fifteen and losses demote across the Silver boundary',async()=>{
 await q('begin');
 try {
  const bot=(await q("insert into public.profiles(full_name,is_bot,rating,level,avatar_url) values('Test Bot',true,1000,8,'color:#5B4CFF') returning id"))[0].id;
  await q('update public.profiles set rating=1000 where id=$1',[ids[0]]);
  const lost=(await q("select sj_private.new_match($1,$2,null,null,'bot') id",[ids[0],bot]))[0].id;
  await q('select sj_private.finalize_match($1,$2)',[lost,bot]);
  assert.equal((await q('select trophies from public.profiles where id=$1',[ids[0]]))[0].trophies,995);
  const won=(await q("select sj_private.new_match($1,$2,null,null,'bot') id",[ids[0],bot]))[0].id;
  await q('select sj_private.finalize_match($1,$2)',[won,ids[0]]);
  assert.equal((await q('select trophies from public.profiles where id=$1',[ids[0]]))[0].trophies,1010);
 } finally { await q('rollback'); }
});
await test('Bot cannot start early and uses one queue entry',async()=>{
 await asUser(0,()=>q('select public.join_matchmaking()'));
 await asUser(0,()=>rejects(()=>q('select public.start_bot_match()'),/SEARCH_NOT_EXPIRED/));
 await q("update public.matchmaking_queue set joined_at=now()-interval '21 seconds'");
 const bot=(await asUser(0,()=>q('select public.start_bot_match() data')))[0].data;
 assert.ok(bot.match_id);
 const again=(await asUser(0,()=>q('select public.start_bot_match() data')))[0].data;
 assert.equal(bot.match_id,again.match_id);
});
await test('Daily users share identical ordered question set; second start resumes',async()=>{
 const d1=(await asUser(0,()=>q('select public.start_daily_attempt() data')))[0].data;
 const d2=(await asUser(1,()=>q('select public.start_daily_attempt() data')))[0].data;
 assert.equal(d1.question.id,d2.question.id);assert.deepEqual(d1.question.options,d2.question.options);
 const again=(await asUser(0,()=>q('select public.start_daily_attempt() data')))[0].data;
 assert.equal(d1.attempt_id,again.attempt_id);
 await asUser(0,()=>rejects(()=>q('select public.get_daily_question($1,9)',[d1.attempt_id]),/QUESTION_NOT_ACTIVE/));
 await asUser(1,()=>rejects(()=>q('select public.submit_daily_answer($1,0,null)',[d1.attempt_id]),/ATTEMPT_NOT_FOUND/));
});
await test('Admin role changes, viewer restrictions and settings validation',async()=>{
 await asUser(2,()=>q("select public.admin_set_role('student1@example.com','viewer',true)"));
 assert.equal((await asUser(1,()=>q('select public.get_my_role() role')))[0].role,'viewer');
 await asUser(1,()=>rejects(()=>q("select public.admin_save_category('{\"name\":\"Test\",\"slug\":\"test\"}')"),/ADMIN_REQUIRED/));
 await asUser(1,()=>rejects(()=>q("select public.admin_save_setting('questions_per_match','4')"),/ADMIN_REQUIRED/));
 await asUser(2,()=>q("select public.admin_save_setting('questions_per_match','4')"));
 await asUser(2,()=>rejects(()=>q("select public.admin_save_setting('questions_per_match','30')"),/INVALID_SETTING/));
 await asUser(2,()=>q("select public.admin_save_setting('questions_per_match','4')"));
 await asUser(2,()=>rejects(()=>q("select public.admin_set_role('badushamc312@gmail.com','viewer',true)"),/KEEP_ONE_SUPER_ADMIN/));
});
await test('A complete bot battle advances server-side and awards rewards once',async()=>{
 const bot=(await q("select id from public.matches where mode='bot' and status='pending'"))[0].id;
 for(let i=0;i<4;i++){
  await q("update public.matches set next_tick_at=now()-interval '1 second' where id=$1",[bot]);
  await q('select sj_private.tick_match($1)',[bot]);
  const state=(await asUser(0,()=>q('select public.get_match_state($1) data',[bot])))[0].data;
  assert.equal(state.question_index,i);
  const key=(await q('select snapshot->>\'correct_option_id\' key from public.match_questions where match_id=$1 and question_index=$2',[bot,i]))[0].key;
  await asUser(0,()=>q('select public.submit_answer($1,$2,$3)',[bot,i,key]));
  await q('update public.bot_plans set response_ms=0 where match_id=$1 and question_index=$2',[bot,i]);
  await q('select sj_private.tick_match($1)',[bot]);
  const result=(await asUser(0,()=>q('select public.get_match_state($1) data',[bot])))[0].data;
  assert.equal(result.phase,'result');assert.ok(result.result.correct_option_id);
 }
 await q("update public.matches set next_tick_at=now()-interval '1 second' where id=$1",[bot]);
 await q('select sj_private.tick_match($1)',[bot]);
 assert.equal((await q('select status from public.matches where id=$1',[bot]))[0].status,'completed');
 assert.ok((await q('select xp_gained from public.match_players where match_id=$1 and user_id=$2',[bot,ids[0]]))[0].xp_gained>=40);
 const payout=(await q('select result,rating_before,rating_after from public.match_players where match_id=$1 and user_id=$2',[bot,ids[0]]))[0];
 assert.equal(payout.rating_after,Math.max(0,payout.rating_before+(payout.result==='win'?15:payout.result==='loss'?-5:0)));
});
await test('An early answer unlocks exactly one daily question, resumes there, and retries once',async()=>{
 const attempt=(await asUser(1,()=>q('select public.start_daily_attempt() data')))[0].data;
 const args=[attempt.attempt_id,0,attempt.question.options[0].id];
 await asUser(1,()=>q('select public.submit_daily_answer($1,$2,$3)',args));
 const next=(await asUser(1,()=>q('select public.get_daily_question($1,1) data',[args[0]])))[0].data;
 assert.ok(new Date(next.started_at)<new Date(attempt.question.deadline_at));
 await asUser(1,()=>q('select public.submit_daily_answer($1,$2,$3)',args));
 const resumed=(await asUser(1,()=>q('select public.start_daily_attempt() data')))[0].data;
 assert.equal(resumed.question_index,1);assert.equal(resumed.question.deadline_at,next.deadline_at);
 await asUser(1,()=>rejects(()=>q('select public.get_daily_question($1,2)',[args[0]]),/QUESTION_NOT_ACTIVE/));
 for(let i=1;i<attempt.question_count;i++)await asUser(1,()=>q('select public.submit_daily_answer($1,$2,null)',[args[0],i]));
 const result=(await asUser(1,()=>q('select public.start_daily_attempt() data')))[0].data;
 assert.equal(result.completed,true);
});
await test('Returning after a missed question can finish immediately on the last answer',async()=>{
 const attempt=(await asUser(2,()=>q('select public.start_daily_attempt() data')))[0].data;
 await q("update public.daily_attempts set started_at=now()-make_interval(secs=>$2) where id=$1",[attempt.attempt_id,attempt.question.time_limit_seconds+1]);
 const resume=(await asUser(2,()=>q('select public.start_daily_attempt() data')))[0].data;
 assert.equal(resume.question_index,1);
 for(let i=1;i<resume.question_count;i++)await asUser(2,()=>q('select public.submit_daily_answer($1,$2,null)',[resume.attempt_id,i]));
 assert.equal((await asUser(2,()=>q('select public.finish_daily_attempt($1) data',[resume.attempt_id])))[0].data.score,0);
});
await test('Category pages, learner directory and atomic JSON imports enforce roles and preserve topics',async()=>{
 const row={question:'What is 15% of 200?',option_a:'25',option_b:'30',option_c:'35',option_d:'40',correct_answer:'B',subject:'Quantitative Aptitude',topic:'Percentage',difficulty:'Easy',explanation:'15% of 200 = 30'};
 const submit=(rows)=>asUser(2,()=>q('select public.admin_import_questions($1::jsonb) data',[JSON.stringify({questions:rows})]));
 const before=(await q('select count(*)::int n from public.questions'))[0].n;
 await rejects(()=>submit([row,{...row,correct_answer:'X'}]),/Question 2/);
 assert.equal((await q('select count(*)::int n from public.questions'))[0].n,before);
 const many=Array.from({length:55},(_,i)=>({...row,question:row.question+' #'+i}));
 assert.equal((await submit(many))[0].data.imported,55);
 assert.equal((await submit(many))[0].data.already_imported,true);
 const groups=(await asUser(2,()=>q('select public.admin_question_groups($1) data',['#'])))[0].data.categories;
 const first=(await asUser(2,()=>q('select public.admin_question_page($1,$2) data',[groups[0].id,'#'])))[0].data.rows;
 assert.equal(first.length,50);assert.equal(first[0].topic_name,'Percentage');assert.equal(first[0].options.find(o=>o.is_correct).option_text,'30');
 const more=(await asUser(2,()=>q('select public.admin_question_page($1,$2,$3) data',[groups[0].id,'#',first.at(-1).id])))[0].data.rows;
 assert.equal(new Set([...first,...more].map(o=>o.id)).size,55);
 const users=(await asUser(2,()=>q('select public.admin_user_page() data')))[0].data.rows;assert.ok(users.some(u=>u.phone));assert.ok(!('fcm_token' in users[0]));
 for (const sql of ['select public.admin_user_page()','select public.admin_question_groups()', "select public.admin_import_questions('{}')"]){
   await asUser(0,()=>rejects(()=>q(sql),/ADMIN_REQUIRED/));
 }
});
await test('Expired daily attempts auto-submit once and award a streak',async()=>{
 const aid=(await q('select id from public.daily_attempts where user_id=$1',[ids[0]]))[0].id;
 await q("update public.daily_attempts set started_at=now()-interval '1 hour' where id=$1",[aid]);
 await q('select sj_private.daily_maintenance()');
 assert.ok((await q('select completed_at from public.daily_attempts where id=$1',[aid]))[0].completed_at);
 const p=(await q('select xp,current_streak from public.profiles where id=$1',[ids[0]]))[0];assert.equal(p.current_streak,1);
 await q('select sj_private.daily_maintenance()');assert.equal((await q('select xp from public.profiles where id=$1',[ids[0]]))[0].xp,p.xp);
});
await test('Admin question save validates options and preserves used questions',async()=>{
 const category=(await q("select id from public.categories where slug='quant'"))[0].id;
 const payload={category_id:category,topic_name:'Test topic',question_text:'A new test question?',explanation:'A useful explanation.',difficulty:'easy',time_limit_seconds:15,status:'published',options:[{option_text:'First',is_correct:true},{option_text:'Second',is_correct:false},{option_text:'Third',is_correct:false},{option_text:'Fourth',is_correct:false}]};
 const saved=(await asUser(2,()=>q('select public.admin_save_question($1::jsonb) id',[JSON.stringify(payload)])))[0].id;
 assert.ok(saved);
 await asUser(2,()=>rejects(()=>q('select public.admin_save_question($1::jsonb)',[JSON.stringify({...payload,options:[{option_text:'Same',is_correct:true},{option_text:'Same',is_correct:false},{option_text:'Third',is_correct:false},{option_text:'Fourth',is_correct:false}]})]),/ONE_CORRECT_AND_UNIQUE_OPTIONS_REQUIRED/));
 const used=(await q('select question_id from public.match_questions limit 1'))[0].question_id;
 await asUser(2,()=>rejects(()=>q('select public.admin_save_question($1::jsonb)',[JSON.stringify({...payload,id:used})]),/QUESTION_ALREADY_USED/));
});
await test('Daily scheduling and analytics enforce admin permission',async()=>{
 const day=(await q("select ((now() at time zone 'Asia/Kolkata')::date+3)::text as \"day\""))[0].day;
 await asUser(2,()=>q("select public.admin_schedule_daily($1,'Scheduled test')",[day]));
 const calendar=(await asUser(2,()=>q('select public.admin_daily_calendar() data')))[0].data;
 assert.equal(calendar.days.length,30);
 assert.ok((await asUser(2,()=>q('select public.admin_analytics() data')))[0].data.questions.length>0);
 await asUser(0,()=>rejects(()=>q('select public.admin_daily_calendar()'),/ADMIN_REQUIRED/));
});
await test('Completed battle report exposes real timing and both choices only to participants',async()=>{
 const bot=(await q("select id from public.matches where mode='bot' and status='completed'"))[0].id;
 const report=(await asUser(0,()=>q('select public.get_match_review($1) data',[bot])))[0].data;
 assert.equal(report.rounds_played,4);assert.equal(report.players.length,2);
 const me=report.players.find(p=>p.id===ids[0]);
 assert.equal(me.correct,4);assert.equal(me.wrong,0);assert.equal(me.unanswered,0);assert.equal(me.accuracy,100);
 assert.equal(me.base_points+me.speed_bonus,me.score);
 assert.ok(Math.abs(report.questions.reduce((sum,q)=>sum+q.points,0)-me.score)<0.00001);
 assert.equal(report.questions.at(-1).multiplier,1);
 assert.ok(report.questions.every(q=>q.response_ms!==null&&q.opponent_response_ms!==null));
 assert.ok(report.questions.every(q=>q.opponent_option_id&&q.correct_option_id));
 await asUser(2,()=>rejects(()=>q('select public.get_match_review($1)',[bot]),/REVIEW_UNAVAILABLE/));
 const partial=(await asUser(0,()=>q('select public.get_match_review($1) data',[mid])))[0].data;
 assert.equal(partial.question_count,4);assert.equal(partial.rounds_played,1);
 assert.equal(partial.questions.length,1); // Never describe unplayed questions as incorrect.
});
await test('Report portraits are visible to the two participants after the match',async()=>{
 const report=(await asUser(0,()=>q('select public.get_match_review($1) data',[mid])))[0].data;
 assert.equal(report.players.find(p=>p.id===ids[0]).avatar_url,'preset:curie');
 const key=report.players.find(p=>p.id===ids[1]).avatar_url.slice(6);
 assert.equal(await readPhoto(0,key,mid),photoFixture);
 assert.equal(await readPhoto(2,key,mid),null);
});
const {verifyRedesign}=await import('./redesign.mjs');
await verifyRedesign({test,q,asUser,rejects,assert,ids});
await test('Account deletion is service-only and removes personal data without breaking history',async()=>{
 await asUser(0,()=>rejects(()=>q('select public.anonymize_account($1)',[ids[1]]),/permission denied/));
 await q('select public.anonymize_account($1)',[ids[1]]);
 assert.equal((await q('select count(*)::int n from sj_private.player_photos where owner_id=$1',[ids[1]]))[0].n,0);
 await q('delete from auth.users where id=$1',[ids[1]]);
 const p=(await q('select full_name,email,phone,auth_user_id,profile_completed from public.profiles where id=$1',[ids[1]]))[0];
 assert.equal(p.full_name,'Deleted learner');assert.equal(p.email,null);assert.equal(p.phone,null);assert.equal(p.auth_user_id,null);assert.equal(p.profile_completed,false);
 assert.ok((await q('select count(*)::int n from public.match_players where user_id=$1',[ids[1]]))[0].n>0);
});
await test('Every public table has RLS enabled',async()=>assert.equal((await q("select count(*)::int n from pg_tables where schemaname='public' and not rowsecurity"))[0].n,0));
console.log(`\n${tests} database checks passed. Supabase Auth/Realtime/Cron integration still requires a real Supabase deployment.`);
await db.close();
