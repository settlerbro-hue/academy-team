-- This test never persists profiles, progress, or test attempts.
begin;
do $$
declare actor uuid; d record; l jsonb; k jsonb; started jsonb; result jsonb; general jsonb; counted integer:=0; route text[]:=array['welcome-90','guru-43403','guru-42932','guru-25811','rvb-waiter-kitchen-menu','rvb-waiter-bar-menu'];
begin
 select p.id into actor from public.academy_profiles p join auth.users u on u.id=p.id where u.email='leagueofspirits4@gmail.com' and p.role='employee' and p.status='active';
 if actor is null then raise exception 'QA identity unavailable';end if;
 update public.academy_profiles set restaurant_id='minsk',department='Зал',position='Администратор',training_level='trainee' where id=actor;
 if exists(select 1 from public.academy_content where id in ('rvb-waiter-kitchen-menu','rvb-waiter-bar-menu') and not (payload->'audiencePositions' ?& array['Администратор','Официант','Хостес'])) then raise exception 'Shared audience regression';end if;
 general:=academy_private.general_training_status(actor,'minsk','Зал','Администратор');
 if not general->'courses' @>jsonb_build_array(jsonb_build_object('id','guru-25811','priority','start')) then raise exception 'Personnel not required for RVB administrator';end if;
 if exists(select 1 from jsonb_array_elements(general->'tests') x where x->>'id' in ('105287','105288','105289','105290','105291')) then raise exception '90-е internship tests leaked into RVB';end if;
 for d in select * from public.academy_content c where c.id=any(route) loop
  perform set_config('request.jwt.claim.sub',actor::text,true);execute 'set local role authenticated';
  for l in select value from jsonb_array_elements(d.payload->'lessons') loop perform public.academy_complete_lesson(d.id,l->>'id');end loop;
  execute 'reset role';
 end loop;
 for d in select * from public.academy_content c where c.kind='test' and c.course_id=any(route) and (c.restaurant_id is null or c.restaurant_id='minsk') and (not c.payload ? 'requiredRestaurantIds' or c.payload->'requiredRestaurantIds' ? 'minsk') loop
  select keys into k from academy_private.test_keys where test_id=d.id;if k is null then raise exception 'Missing key %',d.id;end if;
  execute 'set local role authenticated';started:=public.academy_start_test(d.id);result:=public.academy_submit_test((started->>'attempt_id')::uuid,k);execute 'reset role';
  if not (result->>'passed')::boolean then raise exception 'Scoring failed: %',d.id;end if;counted:=counted+1;
 end loop;
 if counted<>33 then raise exception 'Expected 33 route checks, got %',counted;end if;
 if (select role<>'employee' or training_level<>'trainee' from public.academy_profiles where id=actor) then raise exception 'Curriculum changed role or certification';end if;
 general:=academy_private.general_training_status(actor,'khimki','Зал','Администратор');
 if general->'courses' @>jsonb_build_array(jsonb_build_object('id','guru-25811')) then raise exception '90-е priorities changed';end if;
 if exists(select 1 from jsonb_array_elements(general->'tests') x where x->>'id' like 'rvb-admin-%') then raise exception 'RVB internship assigned to 90-е';end if;
 general:=academy_private.general_training_status(actor,'minsk','Зал','Хостес');if (general->>'tests_total')::integer<>28 then raise exception 'Hostess programme changed';end if;
 general:=academy_private.general_training_status(actor,'minsk','Зал','Официант');if (general->>'tests_total')::integer<>47 then raise exception 'Waiter programme changed';end if;
end $$;
rollback;
select 'PASS: all 33 admin route checks scored, scoped priorities and old tests preserved; waiter47/hostess28 unchanged; no role promotion. All QA rolled back.' as result;
