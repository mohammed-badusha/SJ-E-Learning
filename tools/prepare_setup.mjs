import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const migrations = readdirSync(resolve(root, 'supabase/migrations'))
  .filter((name) => name.endsWith('.sql')).sort();
const parts = [
  `-- SJ E-Learning: first installation only. Do not rerun over an existing project.
begin;
do $$ begin
 if to_regclass('public.profiles') is not null or exists(select 1 from pg_namespace where nspname='sj_private') then
  raise exception 'SJ schema already exists. Apply only new migrations via CLI; do not rerun initial setup.';
 end if;
end $$;`,
];
for (const name of migrations) {
  const sql = readFileSync(resolve(root, 'supabase/migrations', name), 'utf8');
  parts.push(`-- ${name}\n${sql.replace(/^(begin|commit);\s*$/gim, '')}`);
}
const seed = readFileSync(resolve(root, 'supabase/seed.sql'), 'utf8');
parts.push(`-- Seed\n${seed.replace(/^(begin|commit);\s*$/gim, '')}`);
parts.push('commit;\n');
writeFileSync(resolve(root, 'supabase/setup.sql'), parts.join('\n'), 'utf8');
console.log(`Prepared setup.sql from ${migrations.length} migrations and seed.`);
