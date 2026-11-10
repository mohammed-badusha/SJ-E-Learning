// Invoked inside the same isolated Postgres database as the regression suite.
export async function verifyRedesign({test,q,asUser,rejects,assert,ids}) {
 await test('Battle v2 scoring preserves fractional marks without final-round doubling', async()=>{
  for (const [correct,elapsed,duration,expected] of [[true,0,40,2.5],[true,20000,40,2.25],[true,40000,40,2],[true,40500,40,2],[false,0,15,0]]) {
   assert.equal(Number((await q('select sj_private.battle_score($1,$2,$3) s',[correct,elapsed,duration]))[0].s),expected);
  }
 });
 await test('Every new battle has four ordered subjects and the correct server timers',async()=>{
  const match=(await q('select id from public.matches where rules_version=2 limit 1'))[0].id;
  const rounds=await q("select c.slug,(mq.snapshot->>'time_limit_seconds')::int seconds from public.match_questions mq join public.categories c on c.id=(mq.snapshot->>'category_id')::uuid where mq.match_id=$1 order by question_index",[match]);
  assert.deepEqual(rounds,[{slug:'reasoning',seconds:40},{slug:'general-awareness',seconds:15},{slug:'quant',seconds:40},{slug:'english',seconds:15}]);
  assert.equal(Number((await q("select value from public.app_settings where key='search_timeout_seconds'"))[0].value),10);
 });
 await test('Bot plans use the new private identity pool and contain 2, 3 or 4 correct rounds',async()=>{
  const identities=await q('select name,avatar_color,experience_level,play_style from sj_private.bot_names');
  assert.equal(identities.length,139);
  assert.ok(['Arjun','Athira','Joseph','Maria','Ashiq','Fathima','Roobie'].every(name=>identities.some(i=>i.name===name)));
  assert.ok(!identities.some(i=>i.name==='Aarav Sharma'));
  assert.ok(identities.every(i=>i.experience_level>=8&&i.experience_level<=35&&/^#[0-9A-Fa-f]{6}$/.test(i.avatar_color)));
  const bot=(await q("select p.id,p.full_name,p.level,p.avatar_url,m.bot_style from public.profiles p join public.matches m on m.player2_id=p.id where m.rules_version=2 and m.mode='bot' limit 1"))[0];
  const identity=identities.find(i=>i.name===bot.full_name);
  assert.ok(identity);assert.equal(bot.level,identity.experience_level);assert.equal(bot.avatar_url,`color:${identity.avatar_color}`);
  assert.equal(bot.bot_style,identity.play_style);
  const plans=await q('select count(*)::int n,count(*) filter(where will_be_correct)::int correct from public.bot_plans group by match_id');
  assert.ok(plans.every(p=>p.n===4&&p.correct>=2&&p.correct<=4));
  const slots=new Set();
  for(let i=0;i<12;i++) {
   const mid=(await q("select sj_private.new_match($1,$2,null,null,'bot') id",[ids[0],bot.id]))[0].id;
   const plan=await q('select question_index,response_ms,will_be_correct from public.bot_plans where match_id=$1 order by question_index',[mid]);
   assert.ok(plan.every(p=>p.response_ms>0&&p.response_ms<(p.question_index%2===0?40000:15000)));
   slots.add(plan.filter(p=>p.will_be_correct).map(p=>p.question_index).join(','));
  }
  assert.ok(slots.size>1,'correct rounds must not always be a fixed prefix');
 });
 await test('Preference writes are validated, merge atomically, and remain private',async()=>{
  await asUser(0,()=>q("select public.save_preferences('{\"theme\":2,\"haptics\":false}')"));
  const prefs=(await asUser(0,()=>q("select public.save_preferences('{\"music_volume\":0.4}') data")))[0].data;
  assert.deepEqual(prefs,{theme:2,haptics:false,music_volume:0.4});
  assert.equal((await asUser(1,()=>q('select * from public.user_preferences where user_id=$1',[ids[0]]))).length,0);
  await asUser(0,()=>rejects(()=>q("select public.save_preferences('{\"rating\":9999}')"),/UNKNOWN_SETTING/));
  await asUser(0,()=>rejects(()=>q("select public.save_preferences('{\"music_volume\":2}')"),/INVALID_SETTINGS/));
  await asUser(0,()=>rejects(()=>q("update public.user_preferences set settings='{}'"),/permission denied/));
 });
 await test('Filtered practice draws exactly the requested number or refuses atomically',async()=>{
  const category=(await q("select id from public.categories where slug='quant'"))[0].id;
  const practice=(await asUser(0,()=>q("select public.start_practice($1,null,true,null,null,20) data",[category])))[0].data;
  assert.equal(practice.question_count,20); assert.equal(practice.question.correct_option_id,undefined);
  const counts=(await q("select count(*)::int n,count(distinct value->>'id')::int unique_count from public.practice_attempts a,jsonb_array_elements(a.questions) where a.id=$1",[practice.attempt_id]))[0];
  assert.equal(counts.n,20);assert.equal(counts.unique_count,20);
  await asUser(0,()=>rejects(()=>q("select public.start_practice($1,null,true,'NONEXISTENT',null,25)",[category]),/NOT_ENOUGH_QUESTIONS/));
 });
 await test('Default hierarchy and ten-question daily challenge are database owned',async()=>{
  assert.ok((await q('select count(*)::int n from public.subtopics where topic_group is not null'))[0].n>=40);
  const daily=(await asUser(0,()=>q('select public.get_today_challenge() data')))[0].data;
  assert.equal(daily.question_count,10);
  await asUser(2,()=>rejects(()=>q("select public.admin_save_setting('questions_per_match','10')"),/INVALID_SETTING/));
  await asUser(2,()=>rejects(()=>q("select public.admin_save_setting('search_timeout_seconds','20')"),/INVALID_SETTING/));
 });
 await test('Cloud history uses bounded pages and protects completed daily reviews',async()=>{
  const page=(await asUser(0,()=>q('select public.get_history_page() data')))[0].data;
  assert.ok(page.rows.length<=30);
  await asUser(0,()=>rejects(()=>q('select public.get_history_page(now(),null)'),/INVALID_CURSOR/));
  const completed=(await q('select id from public.daily_attempts where user_id=$1 and completed_at is not null limit 1',[ids[0]]))[0];
  assert.ok(completed);
  const review=(await asUser(0,()=>q('select public.get_daily_review($1) data',[completed.id])))[0].data;
  assert.equal(review.questions.length,10);
  await asUser(1,()=>rejects(()=>q('select public.get_daily_review($1)',[completed.id]),/REVIEW_UNAVAILABLE/));
  const botEvents=await q("select payload from realtime.sent where event='opponent_answered' and payload->>'user_id' in (select id::text from public.profiles where is_bot)");
  assert.ok(botEvents.length>=4);
  assert.ok(botEvents.every(e=>Object.keys(e.payload).sort().join(',')==='question_index,user_id'));
 });
}
