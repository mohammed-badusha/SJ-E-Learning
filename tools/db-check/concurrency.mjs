// Disposable local PostgreSQL load check. Never points at a hosted project.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, readdir, writeFile, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const exec = promisify(execFile);
const root = fileURLToPath(new URL('../../', import.meta.url));
const psql = process.env.PSQL_PATH ?? 'C:/Program Files/PostgreSQL/18/bin/psql.exe';
const port = process.env.PGPORT ?? '55432';
const user = process.env.PGUSER ?? process.env.USERNAME ?? 'USER';
const database = process.env.PGDATABASE ?? 'postgres';
const players = Number(process.env.LOAD_PLAYERS ?? 30);
const questionsPerSubject = Number(process.env.LOAD_QUESTIONS_PER_SUBJECT ?? 40);
const prequeue = process.env.LOAD_PREQUEUE === '1';
assert.ok(Number.isInteger(players) && players > 0 && players % 2 === 0);
assert.ok(Number.isInteger(questionsPerSubject) && questionsPerSubject >= 4);
const args = ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-p', port, '-U', user, '-d', database];
const sql = async (query) => (await exec(psql, [...args, '-c', query], {maxBuffer: 8_000_000})).stdout.trim();
const file = async (path) => exec(psql, [...args, '-f', path], {maxBuffer: 8_000_000});
const temporary = await mkdtemp(join(tmpdir(), 'sj-load-'));

let setup = `do $$ begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role bypassrls; end if;
end $$;
create schema auth; create schema realtime;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth,realtime to authenticated;
grant execute on function auth.uid() to authenticated;
create table realtime.messages(id int,topic text);
alter table realtime.messages enable row level security;
create function realtime.topic() returns text language sql stable as $$ select current_setting('realtime.topic',true) $$;
create table realtime.sent(topic text,event text,payload jsonb);
create function realtime.send(payload jsonb,event text,topic text,private boolean) returns void language sql as $$ insert into realtime.sent values(topic,event,payload) $$;
`;
for (const name of (await readdir(join(root, 'supabase/migrations'))).sort()) {
  if (name.includes('scheduler')) continue;
  setup += `\n${await readFile(join(root, 'supabase/migrations', name), 'utf8')}\n`;
}
setup += `\n${await readFile(join(root, 'supabase/seed.sql'), 'utf8')}\n`;
const setupPath = join(temporary, 'setup.sql');
await writeFile(setupPath, setup);
await file(setupPath);

const fixturePath = join(temporary, 'fixtures.sql');
await writeFile(fixturePath, `
do $$ declare subject record; idx int; qid uuid; begin
 for subject in select c.id category_id,s.id subtopic_id
   from public.categories c join lateral
   (select id from public.subtopics where category_id=c.id order by sort_order limit 1) s on true
   where c.slug in ('quant','reasoning','general-awareness','english') loop
  for idx in 1..${questionsPerSubject} loop
   insert into public.questions(category_id,subtopic_id,question_text,difficulty,
      time_limit_seconds,explanation,status)
   values(subject.category_id,subject.subtopic_id,'Load question '||subject.category_id||' '||idx,
      'medium',15,'Load explanation','published') returning id into qid;
   insert into public.question_options(question_id,option_text,is_correct,sort_order)
   values(qid,'A',true,0),(qid,'B',false,1),(qid,'C',false,2),(qid,'D',false,3);
  end loop;
 end loop;
end $$;
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data)
select gen_random_uuid(),'load-'||i||'@example.com',now(),'{"provider":"google"}'
from generate_series(1,${players}) i;
update public.profiles p set full_name='Load player '||split_part(split_part(u.email,'@',1),'-',2),
 phone='+9190000'||lpad(split_part(split_part(u.email,'@',1),'-',2),5,'0'),
 profile_completed=true
from auth.users u where p.id=u.id and u.email like 'load-%@example.com';
`);
await file(fixturePath);

const ids = (await sql("select id from auth.users where email like 'load-%@example.com' order by email")).split(/\s+/);
assert.equal(ids.length, players);
const userSql = (id, expression) => `set role authenticated; set request.jwt.claim.sub='${id}'; select ${expression};`;
if (prequeue) {
 await sql("insert into public.matchmaking_queue(user_id,category_id,subtopic_id,rating) select id,null,null,rating from public.profiles where email like 'load-%@example.com'");
}
const matchFor = new Map();
let joinErrors = [];
const joinStarted = performance.now();
const barrier = new Date(Date.now() + 5000).toISOString();
let firstWaveMatches = 0;
for (let attempt = 0; attempt < 6 && matchFor.size < players; attempt++) {
 const pending = ids.filter(id => !matchFor.has(id));
 await Promise.all(pending.map(async id => {
  try {
   const wait = prequeue && attempt === 0
    ? `select pg_sleep(greatest(0,extract(epoch from ('${barrier}'::timestamptz-clock_timestamp())))); `
    : '';
   const result = JSON.parse(await sql(`set role authenticated; set request.jwt.claim.sub='${id}'; ${wait}select public.join_matchmaking(null,null)::text;`));
   if (result.match_id) matchFor.set(id, result.match_id);
  } catch (error) { joinErrors.push(error.message); }
 }));
 if (attempt === 0) firstWaveMatches = matchFor.size;
}
assert.deepEqual(joinErrors, [], `matchmaking errors: ${joinErrors.join('; ')}`);
assert.equal(matchFor.size, players, 'all players must find a human match');
const matchIds = [...new Set(matchFor.values())];
assert.equal(matchIds.length, players / 2, 'players must form distinct pairs');
const joinMs = Math.round(performance.now() - joinStarted);

await sql("update public.matches set next_tick_at=now()-interval '1 second' where status='pending'");
const tickStarted = performance.now();
await sql('select sj_private.tick_all()');
const tickMs = Math.round(performance.now() - tickStarted);
assert.equal(Number(await sql("select count(*) from public.matches where phase='question'")),players / 2);
const optionRows = (await sql("select m.id::text||'|'||(q.snapshot->'options'->0->>'id') from public.matches m join public.match_questions q on q.match_id=m.id and q.question_index=0 order by m.id")).split(/\s+/);
const optionFor = new Map(optionRows.map(row => row.split('|')));

const answerStarted = performance.now();
const answerErrors = [];
await Promise.all(ids.map(async id => {
 try {
  const match = matchFor.get(id);
  const result = JSON.parse(await sql(userSql(id,
   `public.submit_answer('${match}'::uuid,0,'${optionFor.get(match)}'::uuid)::text`)));
  assert.equal(result.accepted,true);
 } catch (error) { answerErrors.push(error.message); }
}));
assert.deepEqual(answerErrors, [], `answer errors: ${answerErrors.join('; ')}`);
assert.equal(Number(await sql('select count(*) from public.match_answers')),players);
assert.equal(Number(await sql("select count(*) from public.matches where phase='result'")),players / 2);
const answerMs = Math.round(performance.now() - answerStarted);
const heartbeatStarted = performance.now();
const heartbeatPayloads = await Promise.all(ids.map(id =>
  sql(userSql(id, `public.heartbeat_match('${matchFor.get(id)}'::uuid)::text`))));
const heartbeatMs = Math.round(performance.now() - heartbeatStarted);
const fullStateStarted = performance.now();
const fullStatePayloads = await Promise.all(ids.map(id =>
  sql(userSql(id, `public.get_match_state('${matchFor.get(id)}'::uuid)::text`))));
const fullStateMs = Math.round(performance.now() - fullStateStarted);
console.log(JSON.stringify({players,questions_per_subject:questionsPerSubject,
 prequeued:prequeue,first_wave_matched_players:firstWaveMatches,
 human_matches:players / 2,accepted_answers:players,
 join_ms:joinMs,first_question_tick_ms:tickMs,concurrent_answers_ms:answerMs,
 heartbeat_poll_ms:heartbeatMs,full_state_poll_ms:fullStateMs,
 heartbeat_payload_bytes:heartbeatPayloads.reduce((n,s)=>n+s.length,0),
 full_state_payload_bytes:fullStatePayloads.reduce((n,s)=>n+s.length,0),
 deadlocks:0,duplicate_answers:0}));
