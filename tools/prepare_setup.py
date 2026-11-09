from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
files=sorted((root/'supabase/migrations').glob('*.sql'))
preflight="""-- SJ E-Learning: first installation only. Run in your NEW Supabase project's SQL Editor.
-- Includes sample educational content. No service-role key is embedded.
begin;
do $$ begin
 if to_regclass('public.profiles') is not null or exists(select 1 from pg_namespace where nspname='sj_private') then
  raise exception 'SJ schema already exists. Apply only new migrations via CLI; do not rerun initial setup.';
 end if;
end $$;
"""
parts=[preflight]
for file in files: parts.append(f'\n-- {file.name}\n'+re.sub(r'(?m)^(begin|commit);\s*$', '', file.read_text(encoding='utf-8')))
seed=(root/'supabase/seed.sql').read_text(encoding='utf-8')
parts.append('\n-- Seed\n'+seed.replace('\nbegin;\n','\n').replace('\ncommit;\n','\n'))
parts.append('\ncommit;\n')
(root/'supabase/setup.sql').write_text('\n'.join(parts),encoding='utf-8')
print('Prepared supabase/setup.sql from',len(files),'migrations + seed (one transaction).')
