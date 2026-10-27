-- All changes in this test are rolled back, including profiles and reviews.
begin;
do $$
declare actor uuid; reviewer uuid; outsider uuid; d record; l jsonb; k jsonb; answers jsonb; started jsonb; result jsonb; general jsonb; dashboard jsonb; pending_ids uuid[]:='{}'; a uuid; failed_test text; denied boolean:=false; count_tests integer:=0;
begin
 select p.id into actor from public.academy_profiles p join auth.users u on u.id=p.id where u.email='leagueofspirits4@gmail.com' and p.role='employee' and p.status='active' and p.restaurant_id='minsk';
 select id into reviewer from public.academy_profiles where role='manager' and not operations_director and department='Зал' and status='active' limit 1;
 select id into outsider from public.academy_profiles where role='manager' and not operations_director and department='Бар' and restaurant_id<>'minsk' and status='active' limit 1;
 if actor is null or reviewer is null or outsider is null then raise exception 'QA identities unavailable';end if;
 update public.academy_profiles set department='Зал',position='Хостес',training_level='trainee' where id=actor;
 update public.academy_profiles set restaurant_id='minsk' where id=reviewer;
 if exists(select 1 from public.academy_content where id in ('rvb-waiter-kitchen-menu','rvb-waiter-bar-menu') and (not payload->'audiencePositions' ? 'Хостес' or not payload->'audiencePositions' ? 'Официант')) then raise exception 'Shared menu audience damaged';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);execute 'set local role authenticated';
 if not exists(select 1 from public.academy_content where id='rvb-hostess-practice') then raise exception 'Practice unavailable';end if;
 if exists(select 1 from public.academy_content where id in ('rvb-bar-foundations','rvb-bar-techcards-course')) then raise exception 'Bar-only staff content leaked';end if;
 general:=public.academy_oral_data(false)->'members'->0->'general';
 if (general->>'tests_total')::integer<>28 then raise exception 'Expected 28 checks: %',general;end if;
 for d in select id,payload from public.academy_content c where general->'courses' @>jsonb_build_array(jsonb_build_object('id',c.id)) loop
  for l in select value from jsonb_array_elements(coalesce(d.payload->'lessons','[]')) loop perform public.academy_complete_lesson(d.id,l->>'id');end loop;
 end loop;
 execute 'reset role';
 for d in select id,payload from public.academy_content c where general->'tests' @>jsonb_build_array(jsonb_build_object('id',c.id)) loop
  select keys into k from academy_private.test_keys where test_id=d.id;if k is null then raise exception 'Missing key: %',d.id;end if;
  if exists(select 1 from jsonb_array_elements(d.payload->'questions') q where q->>'type'='text') then select jsonb_object_agg(q->>'id',to_jsonb('Учебный ответ: проверю условия своего заведения, уточню пожелания, согласую решение и передам информацию администратору и команде.'::text)) into answers from jsonb_array_elements(d.payload->'questions') q;else answers:=k;end if;
  execute 'set local role authenticated';started:=public.academy_start_test(d.id);result:=public.academy_submit_test((started->>'attempt_id')::uuid,answers);
  if exists(select 1 from jsonb_array_elements(d.payload->'questions') q where q->>'type'='text') then
   if not (result->>'needs_review')::boolean or (result->>'passed')::boolean then raise exception 'Practice was auto-passed';end if;
   pending_ids:=array_append(pending_ids,(started->>'attempt_id')::uuid);
  elsif not (result->>'passed')::boolean then raise exception 'Automatic scoring failed for %',d.id;end if;
  execute 'reset role';count_tests:=count_tests+1;
 end loop;
 if cardinality(pending_ids)<>5 then raise exception 'Expected five practical works';end if;
 execute 'set local role authenticated';general:=public.academy_oral_data(false)->'members'->0->'general';if (general->>'passed')::boolean then raise exception 'Pending work completed programme';end if;execute 'reset role';
 perform set_config('request.jwt.claim.sub',outsider::text,true);execute 'set local role authenticated';
 begin perform public.academy_review_attempt(pending_ids[1],1,'QA');exception when others then denied:=true;end;
 if not denied then raise exception 'Foreign administrator reviewed hostess';end if;execute 'reset role';
 perform set_config('request.jwt.claim.sub',reviewer::text,true);execute 'set local role authenticated';dashboard:=public.academy_manager_dashboard();
 if not dashboard->'attempts' @>jsonb_build_array(jsonb_build_object('id',pending_ids[1],'needs_review',true)) then raise exception 'Administrator cannot see pending work';end if;
 perform public.academy_review_attempt(pending_ids[1],0,'QA · нужна доработка · ROLLBACK');
 foreach a in array pending_ids[2:cardinality(pending_ids)] loop perform public.academy_review_attempt(a,1,'QA · принято · ROLLBACK');end loop;
 execute 'reset role';perform set_config('request.jwt.claim.sub',actor::text,true);execute 'set local role authenticated';general:=public.academy_oral_data(false)->'members'->0->'general';if (general->>'passed')::boolean then raise exception 'Rejected work completed programme';end if;execute 'reset role';
 select test_id into failed_test from public.academy_attempts where id=pending_ids[1];execute 'set local role authenticated';started:=public.academy_start_test(failed_test);select jsonb_object_agg(q->>'id',to_jsonb('Учебный ответ после доработки: проверка схемы, пожеланий гостей, реальных условий и согласование с администратором.'::text)) into answers from jsonb_array_elements(started->'questions') q;perform public.academy_submit_test((started->>'attempt_id')::uuid,answers);execute 'reset role';
 perform set_config('request.jwt.claim.sub',reviewer::text,true);execute 'set local role authenticated';perform public.academy_review_attempt((started->>'attempt_id')::uuid,1,'QA · принято после доработки · ROLLBACK');execute 'reset role';
 perform set_config('request.jwt.claim.sub',actor::text,true);execute 'set local role authenticated';general:=public.academy_oral_data(false)->'members'->0->'general';if not (general->>'passed')::boolean then raise exception 'Approved programme not complete: %',general;end if;execute 'reset role';
 if (select training_level from public.academy_profiles where id=actor)<>'trainee' then raise exception 'Hostess certification rule unexpectedly changed';end if;
 update public.academy_profiles set position='Официант' where id=actor;execute 'set local role authenticated';general:=public.academy_oral_data(false)->'members'->0->'general';if (general->>'tests_total')::integer<>47 then raise exception 'Waiter programme changed: %',general;end if;execute 'reset role';
 update public.academy_profiles set restaurant_id='mytishchi',position='Хостес' where id=actor;execute 'set local role authenticated';if exists(select 1 from public.academy_content where id in ('rvb-hostess-practice','rvb-waiter-kitchen-menu','rvb-waiter-bar-menu')) then raise exception 'RVB programme leaked to 90-е';end if;execute 'reset role';
 if count_tests<>28 then raise exception 'Incomplete test coverage';end if;
end $$;
rollback;
select 'PASS: 28 hostess checks, five written works require own administrator review, rejection and retry work, other venue denied, waiter 47 checks and hostess training-level rules preserved. All QA rolled back.' result;
