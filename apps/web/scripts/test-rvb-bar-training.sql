-- QA only: all attempts and lesson completions are rolled back.
begin;
do $$
declare actor uuid; outsider uuid; d record; l jsonb; k jsonb; started jsonb; result jsonb; n integer:=0;
begin
 select p.id into actor from public.academy_profiles p join auth.users u on u.id=p.id where u.email='leagueofspirits4@gmail.com' and p.status='active' and p.role='employee' and p.restaurant_id='minsk' and p.department='Бар';
 if actor is null then raise exception 'Expected RVB test employee is unavailable';end if;
 select p.id into outsider from public.academy_profiles p where p.restaurant_id='mytishchi' and p.role='manager' and not p.operations_director and p.status='active' limit 1;
 if outsider is null then raise exception 'Expected out-of-scope administrator is unavailable';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 execute 'set local role authenticated';
 if (select count(*) from public.academy_content where id in ('rvb-bar-foundations','rvb-bar-assortment','rvb-bar-techcards-course'))<>3 then raise exception 'Missing employee courses';end if;
 if exists(select 1 from jsonb_array_elements(public.academy_oral_data(false)->'members'->0->'general'->'courses') x where x->>'id'='guru-50011') then raise exception '90-е menu exam still required for RVB';end if;
 if has_table_privilege('authenticated','academy_private.test_keys','select') then raise exception 'Answer keys exposed';end if;
 for d in select id,payload from public.academy_content where id in ('rvb-bar-foundations','rvb-bar-assortment','rvb-bar-techcards-course') loop
  for l in select value from jsonb_array_elements(d.payload->'lessons') loop
   perform public.academy_complete_lesson(d.id,l->>'id');
  end loop;
 end loop;
 execute 'reset role';
 for d in select id,payload from public.academy_content where kind='test' and (id like 'rvb-assortment-test-%' or id like 'rvb-ttk-test-%') loop
  select keys into k from academy_private.test_keys where test_id=d.id;
  if k is null then raise exception 'Missing test key';end if;
  execute 'set local role authenticated';
  started:=public.academy_start_test(d.id);
  if started ? 'keys' or started ? 'correct' then raise exception 'Key returned to employee';end if;
  result:=public.academy_submit_test((started->>'attempt_id')::uuid,k);
  if not (result->>'passed')::boolean or (result->>'score')::integer<>jsonb_array_length(d.payload->'questions') then raise exception 'Scoring mismatch for %: %',d.id,result;end if;
  execute 'reset role';n:=n+1;
 end loop;
 if n<>12 then raise exception 'Expected 12 tests, got %',n;end if;
 execute 'set local role authenticated';
 started:=public.academy_start_test('rvb-ttk-test-1');
 result:=public.academy_submit_test((started->>'attempt_id')::uuid,'{}'::jsonb);
 if (result->>'passed')::boolean then raise exception 'Empty answers passed';end if;
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',outsider::text,true);
 execute 'set local role authenticated';
 if exists(select 1 from public.academy_content where id in ('rvb-bar-foundations','rvb-bar-assortment','rvb-bar-techcards-course')) then raise exception 'RVB training leaked to another venue';end if;
 if academy_private.can_read_content('rvb-ttk-test-1') then raise exception 'RVB test leaked';end if;
 execute 'reset role';
end $$;
rollback;
select 'PASS: RVB employee sees three courses, all lessons save, 12 tests score correctly, empty answers fail, keys stay private, another venue is denied. All QA results rolled back.' result;
