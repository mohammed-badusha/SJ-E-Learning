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
const args = ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-p', port, '-U', user, '-d', 'postgres'];
const sql = async (query) => (await exec(psql, [...args, '-c', query], {maxBuffer: 8_000_000})).stdout.trim();
const file = async (path) => exec(psql, [...args, '-f', path], {maxBuffer: 8_000_000});
const temporary = await mkdtemp(join(tmpdir(), 'sj-load-'));

let setup = `create role anon; create role authenticated; create role service_role bypassrls;
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
  for idx in 1..40 loop
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
from generate_series(1,30) i;
update public.profiles p set full_name='Load player '||split_part(split_part(u.email,'@',1),'-',2),
 phone='+9190000'||lpad(split_part(split_part(u.email,'@',1),'-',2),5,'0'),
 profile_completed=true
from auth.users u where p.id=u.id and u.email like 'load-%@example.com';
`);
await file(fixturePath);

const ids = (await sql("select id from auth.users where email like 'load-%@example.com' order by email")).split(/\s+/);
assert.equal(ids.length, 30);
const userSql = (id, expression) => `set role authenticated; set request.jwt.claim.sub='${id}'; select ${expression};`;
const matchFor = new Map();
let joinErrors = [];
const joinStarted = performance.now();
for (let attempt = 0; attempt < 6 && matchFor.size < 30; attempt++) {
 const pending = ids.filter(id => !matchFor.has(id));
 await Promise.all(pending.map(async id => {
  try {
   const result = JSON.parse(await sql(userSql(id, 'public.join_matchmaking(null,null)::text')));
   if (result.match_id) matchFor.set(id, result.match_id);
  } catch (error) { joinErrors.push(error.message); }
 }));
}
assert.deepEqual(joinErrors, [], `matchmaking errors: ${joinErrors.join('; ')}`);
assert.equal(matchFor.size, 30, 'all 30 players must find a human match');
const matchIds = [...new Set(matchFor.values())];
assert.equal(matchIds.length, 15, '30 players must form 15 distinct matches');
const joinMs = Math.round(performance.now() - joinStarted);

await sql("update public.matches set next_tick_at=now()-interval '1 second' where status='pending'");
const tickStarted = performance.now();
await sql('select sj_private.tick_all()');
const tickMs = Math.round(performance.now() - tickStarted);
assert.equal(Number(await sql("select count(*) from public.matches where phase='question'")),15);
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
assert.equal(Number(await sql('select count(*) from public.match_answers')),30);
assert.equal(Number(await sql("select count(*) from public.matches where phase='result'")),15);
const answerMs = Math.round(performance.now() - answerStarted);
console.log(JSON.stringify({players:30,human_matches:15,accepted_answers:30,
 join_ms:joinMs,first_question_tick_ms:tickMs,concurrent_answers_ms:answerMs,
 deadlocks:0,duplicate_answers:0}));
