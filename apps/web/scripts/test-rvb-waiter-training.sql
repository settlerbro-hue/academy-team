-- All QA profile changes, progress, attempts and assessments are rolled back.
begin;
do $$
declare actor uuid; owner_id uuid; d record; l jsonb; started jsonb; result jsonb; k jsonb; general jsonb; tests_count integer:=0; level_now text;
begin
 select p.id into actor from public.academy_profiles p join auth.users u on p.id=u.id where u.email='leagueofspirits4@gmail.com' and p.status='active' and p.role='employee' and p.restaurant_id='minsk';
 select id into owner_id from public.academy_profiles where role='admin' and status='active' limit 1;
 if actor is null or owner_id is null then raise exception 'QA identities unavailable';end if;
 update public.academy_profiles set department='Зал',position='Официант' where id=actor;
 perform set_config('request.jwt.claim.sub',actor::text,true);execute 'set local role authenticated';
 if (select count(*) from public.academy_content where id in ('rvb-waiter-kitchen-menu','rvb-waiter-bar-menu'))<>2 then raise exception 'Waiter menu courses missing';end if;
 if exists(select 1 from public.academy_content where id in ('rvb-bar-foundations','rvb-bar-techcards-course')) then raise exception 'Bar-only training leaked to waiter';end if;
 if has_table_privilege('authenticated','academy_private.test_keys','select') then raise exception 'Keys exposed';end if;
 general:=public.academy_oral_data(false)->'members'->0->'general';
 if exists(select 1 from jsonb_array_elements(general->'tests') x where x->>'id' in ('104760','104939','105476','104336')) then raise exception '90-е diary checks still mandatory for RVB';end if;
 if exists(select 1 from jsonb_array_elements(general->'courses') x where x->>'id' in ('guru-50011','guru-50012')) then raise exception '90-е menu courses still mandatory for RVB';end if;
 for d in select c.id,c.payload from public.academy_content c where general->'courses' @>jsonb_build_array(jsonb_build_object('id',c.id)) loop
  for l in select value from jsonb_array_elements(coalesce(d.payload->'lessons','[]')) loop perform public.academy_complete_lesson(d.id,l->>'id');end loop;
 end loop;
 execute 'reset role';
 for d in select c.id,c.payload from public.academy_content c where general->'tests' @>jsonb_build_array(jsonb_build_object('id',c.id)) loop
  select keys into k from academy_private.test_keys where test_id=d.id;
  if k is null then raise exception 'Missing key: %',d.id;end if;
  execute 'set local role authenticated';started:=public.academy_start_test(d.id);result:=public.academy_submit_test((started->>'attempt_id')::uuid,k);
  if not (result->>'passed')::boolean or (result->>'needs_review')::boolean then raise exception 'Scoring mismatch for %: %',d.id,result;end if;
  execute 'reset role';tests_count:=tests_count+1;
 end loop;
 execute 'set local role authenticated';general:=public.academy_oral_data(false)->'members'->0->'general';
 if not (general->>'passed')::boolean then raise exception 'General attestation not passed: %',general;end if;
 execute 'reset role';select training_level into level_now from public.academy_profiles where id=actor;
 if level_now<>'trainee' then raise exception 'General alone certified a waiter';end if;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);execute 'set local role authenticated';
 perform public.academy_save_kitchen_oral(actor,'minsk','{"hot":8,"cold":8,"allergens":8,"sauces":8,"pizza":8,"general":8}'::jsonb,'QA · ROLLBACK');
 execute 'reset role';select training_level into level_now from public.academy_profiles where id=actor;if level_now<>'trainee' then raise exception 'Two attestations certified a waiter';end if;
 execute 'set local role authenticated';perform public.academy_save_bar_oral(actor,'minsk','{"wine":8,"spirits":8,"beer":8,"cocktails":8,"nonalcoholic":8,"specials":8,"alternatives":8,"pairing":8}'::jsonb,'QA · ROLLBACK');
 execute 'reset role';select training_level into level_now from public.academy_profiles where id=actor;if level_now<>'certified' then raise exception 'All three did not certify the waiter';end if;
 delete from public.academy_progress where user_id=actor and course_id='rvb-waiter-kitchen-menu';
 select training_level into level_now from public.academy_profiles where id=actor;if level_now<>'trainee' then raise exception 'Incomplete mandatory training retained certification';end if;
 update public.academy_profiles set restaurant_id='mytishchi' where id=actor;
 perform set_config('request.jwt.claim.sub',actor::text,true);execute 'set local role authenticated';
 if exists(select 1 from public.academy_content where id like 'rvb-waiter-%') then raise exception 'RVB content leaked to another venue';end if;
 general:=public.academy_oral_data(false)->'members'->0->'general';
 if not general->'tests' @>jsonb_build_array(jsonb_build_object('id','104939')) then raise exception '90-е original diary checks were lost';end if;
 execute 'reset role';
 if tests_count<40 then raise exception 'Incomplete mandatory test coverage: %',tests_count;end if;
end $$;
rollback;
select 'PASS: waiter completes all assigned courses/tests; general + kitchen + bar required for certification; missing training resets readiness; RVB isolation and 90-е diary preserved. All QA data rolled back.' result;
