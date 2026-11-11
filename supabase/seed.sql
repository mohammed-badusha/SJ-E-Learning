-- Development seed: accounts, settings and badges only. Question catalog comes from migrations; questions are added by staff.
begin;
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
