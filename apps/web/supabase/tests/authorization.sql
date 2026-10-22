-- Run as database owner after migrations. Entire fixture is rolled back.
begin;
insert into auth.users(id,email) values
('00000000-0000-4000-8000-000000000011','academy-rls-a@example.invalid'),
('00000000-0000-4000-8000-000000000012','academy-rls-b@example.invalid'),
('00000000-0000-4000-8000-000000000013','academy-rls-manager@example.invalid'),
('00000000-0000-4000-8000-000000000014','academy-rls-pending@example.invalid');
insert into public.academy_profiles(id,full_name,restaurant_id,department,role,status) values
('00000000-0000-4000-8000-000000000011','A','minsk','Зал','employee','active'),
('00000000-0000-4000-8000-000000000012','B','khimki','Бар','employee','active'),
('00000000-0000-4000-8000-000000000013','M','minsk','Зал','manager','active'),
('00000000-0000-4000-8000-000000000014','P','minsk','Зал','employee','pending');
insert into public.academy_content(id,kind,title,payload) values
('security-test','test','Test','{"passCount":1,"timeLimitSeconds":300,"questions":[{"id":"q1","type":"single","options":["yes","no"]}]}'),
('security-menu','menu','Menu','{}');
insert into public.academy_content(id,kind,title,payload) values('security-course','course','Course','{"lessons":[{"id":"real-lesson","title":"Real"}]}');
insert into academy_private.test_keys values('security-test','{"q1":[0]}');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000014',true);
do $$ begin
 if exists(select 1 from public.academy_content) then raise exception 'FAIL pending can read content'; end if;
 begin perform public.academy_start_test('security-test'); raise exception 'FAIL pending can start test';
 exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000011',true);
do $$ declare a jsonb; result jsonb; begin
 if exists(select 1 from public.academy_profiles where id='00000000-0000-4000-8000-000000000012') then raise exception 'FAIL employee sees another user'; end if;
 begin update public.academy_profiles set role='admin' where id=auth.uid(); raise exception 'FAIL direct role escalation';
 exception when insufficient_privilege then null; end;
 begin perform public.academy_manage_member(auth.uid(),'active','admin'); raise exception 'FAIL RPC escalation';
 exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
 begin perform keys from academy_private.test_keys; raise exception 'FAIL key disclosure';
 exception when insufficient_privilege then null; end;
 begin insert into public.academy_progress(user_id,course_id,lesson_id) values(auth.uid(),'security-course','fake'); raise exception 'FAIL direct progress forgery';
 exception when insufficient_privilege then null; end;
 begin perform public.academy_complete_lesson('security-course','fake'); raise exception 'FAIL fabricated lesson completion';
 exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
 perform public.academy_complete_lesson('security-course','real-lesson');
 perform public.academy_complete_lesson('security-course','real-lesson');
 if (select count(*) from public.academy_progress where user_id=auth.uid())<>1 then raise exception 'FAIL duplicate completion'; end if;
 a:=public.academy_start_test('security-test');
 if a::text like '%correct%' or a::text like '%keys%' then raise exception 'FAIL answer disclosure'; end if;
 result:=public.academy_submit_test((a->>'attempt_id')::uuid,'{"q1":[1]}');
 if (result->>'score')::int<>0 or (result->>'passed')::bool then raise exception 'FAIL client controls grading'; end if;
 result:=public.academy_submit_test((a->>'attempt_id')::uuid,'{"q1":[0]}');
 if (result->>'score')::int<>0 then raise exception 'FAIL submitted result can change'; end if;
 a:=public.academy_start_test('security-test'); result:=public.academy_submit_test((a->>'attempt_id')::uuid,'{"q1":[0]}');
 if (result->>'score')::int<>1 or not (result->>'passed')::bool then raise exception 'FAIL correct grading'; end if;
 perform public.academy_set_mark('security-menu','learned');
 begin perform public.academy_set_mark('security-menu','learned','00000000-0000-4000-8000-000000000012'); raise exception 'FAIL foreign mark edit';
 exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000013',true);
do $$ begin
 if not exists(select 1 from public.academy_profiles where id='00000000-0000-4000-8000-000000000011') then raise exception 'FAIL manager cannot see team'; end if;
 if exists(select 1 from public.academy_profiles where id='00000000-0000-4000-8000-000000000012') then raise exception 'FAIL manager sees other branch'; end if;
 perform public.academy_set_mark('security-menu','repeat','00000000-0000-4000-8000-000000000011');
 begin perform public.academy_manage_member('00000000-0000-4000-8000-000000000011','active','admin'); raise exception 'FAIL manager grants admin';
 exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
 begin perform public.academy_manage_member('00000000-0000-4000-8000-000000000012','active','employee'); raise exception 'FAIL manager changes other branch';
 exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
 begin perform public.academy_save_content('{"id":"security-menu","kind":"menu","title":"hijack","payload":{}}'); raise exception 'FAIL manager changes shared content';
 exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
end $$;
reset role;
select 'PASS: pending denial, own data isolation, role escalation denial, private keys, server grading, immutable attempts, scoped manager edits' as security_result;
rollback;
