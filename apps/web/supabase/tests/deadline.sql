begin;
insert into auth.users(id,email) values('00000000-0000-4000-8000-000000000031','academy-deadline@example.invalid');
insert into public.academy_profiles(id,full_name,restaurant_id,department,role,status)
values('00000000-0000-4000-8000-000000000031','Deadline','minsk','Зал','employee','active');
insert into public.academy_content(id,kind,title,payload) values('deadline-test','test','Deadline',
'{"passCount":1,"timeLimitSeconds":1,"questions":[{"id":"q","type":"single","options":["A","B"]}]}');
insert into academy_private.test_keys values('deadline-test','{"q":[0]}');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000031',true);
select set_config('academy.test_attempt',(public.academy_start_test('deadline-test')->>'attempt_id'),true);
reset role;
update public.academy_attempts set started_at=now()-interval '1 hour' where id=current_setting('academy.test_attempt')::uuid;
set local role authenticated;
do $$ declare r jsonb; rankings jsonb; begin
 r:=public.academy_submit_test(current_setting('academy.test_attempt')::uuid,'{"q":[0]}');
 if not (r->>'timed_out')::boolean or (r->>'passed')::boolean then raise exception 'FAIL expired attempt passes'; end if;
 r:=public.academy_submit_test(current_setting('academy.test_attempt')::uuid,'{"q":[0]}');
 if not (r->>'timed_out')::boolean then raise exception 'FAIL retry loses timeout'; end if;
 rankings:=public.academy_ranking();
 if exists(select 1 from jsonb_array_elements(rankings) ranked where ranked->>'user_id'=auth.uid()::text and (ranked->>'tests_attempted')::integer<>0) then raise exception 'FAIL expired grade affects rank'; end if;
end $$;
reset role;
select 'PASS deadline flag, immutable deadline, late score excluded from ranking' as deadline_result;
rollback;
