begin;
create extension if not exists pgtap with schema extensions;
select plan(14);
select is(sj_private.trophy_delta(1),15,'Win awards 15 trophies');
select is(sj_private.trophy_delta(0),-5,'Loss removes 5 trophies');
select is(sj_private.trophy_delta(0.5),0,'Draw leaves trophies unchanged');
select is(greatest(0,0+sj_private.trophy_delta(0)),0,'Trophies never fall below zero');
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('11111111-0000-4000-8000-000000000001','security-test-1@example.com',now(),'{"provider":"google"}','{}'),
('11111111-0000-4000-8000-000000000002','security-test-2@example.com',now(),'{"provider":"google"}','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-0000-4000-8000-000000000001',true);
select throws_ok('select public.start_practice()', '42501', 'PROFILE_REQUIRED', 'Incomplete profile cannot start a game');
select lives_ok($$select public.complete_profile('Security Test One','+919900000001')$$,'Profile completion succeeds');
select ok(jsonb_array_length(public.get_weekly_podium_portraits()->'rows')<=3,'Podium photos are limited to three players');
select is(public.get_my_role(),'student','Ordinary Google user has no admin role');
select throws_ok('select is_correct from public.question_options', '42501','permission denied for table question_options','Answer keys denied');
select throws_ok('update public.profiles set rating=9999', '42501','permission denied for table profiles','Rating writes denied');
select ok(not has_column_privilege('authenticated','public.profiles','trophies','UPDATE'),'Students cannot write trophies');
select is((select count(*)::int from public.profiles where id='11111111-0000-4000-8000-000000000002'),0,'Other profiles hidden');
select throws_ok('select public.admin_dashboard()','42501','ADMIN_REQUIRED','Student admin RPC denied');
select set_config('request.jwt.claim.sub','11111111-0000-4000-8000-000000000002',true);
select throws_ok($$select public.complete_profile('Security Test Two','+919900000001')$$,'23505','PHONE_IN_USE','Duplicate phone denied');
reset role;
select * from finish();
rollback;
