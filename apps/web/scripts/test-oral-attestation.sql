begin;
update public.academy_profiles set role='employee',status='active',restaurant_id='minsk',department='Зал',position='Официант' where id='68a8567e-625e-41bc-bb37-6744d729c3d4';
update public.academy_profiles set role='manager',status='active',restaurant_id='minsk',department='Кухня',position='Шеф-повар' where id='4233956d-46bb-44c6-a266-759203b6648a';
set local role authenticated;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
do $$ declare id uuid; data jsonb; denied boolean; begin
 data:=public.academy_oral_data(true);
 if not exists(select 1 from jsonb_array_elements(data->'members') m where m->>'id'='68a8567e-625e-41bc-bb37-6744d729c3d4' and (m->>'can_grade_kitchen')::boolean) then raise exception 'Chef cannot see/grade hall employee';end if;
 id:=public.academy_save_kitchen_oral('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','{"hot":7,"cold":8,"allergens":8,"sauces":8,"pizza":8,"general":8}','47 points');
 select public.academy_oral_data(true) into data;
 if exists(select 1 from jsonb_array_elements(data->'assessments') a where a->>'id'=id::text and (a->>'passed')::boolean) then raise exception '47/60 wrongly passed';end if;
 id:=public.academy_save_kitchen_oral('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','{"hot":8,"cold":8,"allergens":8,"sauces":8,"pizza":8,"general":8}','48 points');
 select public.academy_oral_data(true) into data;
 if not exists(select 1 from jsonb_array_elements(data->'assessments') a where a->>'id'=id::text and (a->>'passed')::boolean and (a->>'average')::numeric=8) then raise exception '48/60 did not pass';end if;
 if exists(select 1 from jsonb_array_elements(data->'members') m where m->>'id'='68a8567e-625e-41bc-bb37-6744d729c3d4' and m->>'training_level'='certified') then raise exception 'Kitchen alone certified waiter';end if;
 denied:=false;begin perform public.academy_save_kitchen_oral('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','{"hot":10,"cold":10,"allergens":10,"sauces":10,"pizza":10}');exception when others then denied:=true;end;if not denied then raise exception 'Incomplete score accepted';end if;
 denied:=false;begin perform public.academy_save_kitchen_oral('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','{"hot":0,"cold":10,"allergens":10,"sauces":10,"pizza":10,"general":10}');exception when others then denied:=true;end;if not denied then raise exception 'Out of range score accepted';end if;
 denied:=false;begin perform public.academy_save_kitchen_oral(auth.uid(),'minsk','{"hot":8,"cold":8,"allergens":8,"sauces":8,"pizza":8,"general":8}');exception when others then denied:=true;end;if not denied then raise exception 'Self examination accepted';end if;
end $$;
reset role;
insert into public.academy_oral_assessments(employee_id,employee_name,employee_position,restaurant_id,division,scores,category_count,score_total,examiner_id,examiner_name,comment)
values('68a8567e-625e-41bc-bb37-6744d729c3d4','QA waiter','Официант','minsk','bar','{"fixture":8}',1,8,'4233956d-46bb-44c6-a266-759203b6648a','QA bar examiner','Future bar PASS fixture, rolled back');
update public.academy_profiles set training_level=training_level where id='68a8567e-625e-41bc-bb37-6744d729c3d4';
do $$ begin if not exists(select 1 from public.academy_profiles where id='68a8567e-625e-41bc-bb37-6744d729c3d4' and training_level='certified') then raise exception 'Kitchen and bar did not certify waiter';end if;end $$;
set local role authenticated;
select public.academy_save_kitchen_oral('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','{"hot":7,"cold":8,"allergens":8,"sauces":8,"pizza":8,"general":8}','Retake fail');
reset role;
do $$ begin if exists(select 1 from public.academy_profiles where id='68a8567e-625e-41bc-bb37-6744d729c3d4' and training_level='certified') then raise exception 'Latest failed kitchen did not reset stage';end if;end $$;
update public.academy_profiles set department='Бар',position='Бар-менеджер' where id='4233956d-46bb-44c6-a266-759203b6648a';
set local role authenticated;
do $$ declare denied boolean;data jsonb;begin
 data:=public.academy_oral_data(true);
 if not exists(select 1 from jsonb_array_elements(data->'members') m where m->>'id'='68a8567e-625e-41bc-bb37-6744d729c3d4' and (m->>'can_grade_bar')::boolean and not (m->>'can_grade_kitchen')::boolean) then raise exception 'Bar manager boundaries wrong';end if;
 denied:=false;begin perform public.academy_save_kitchen_oral('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','{"hot":8,"cold":8,"allergens":8,"sauces":8,"pizza":8,"general":8}');exception when others then denied:=true;end;if not denied then raise exception 'Bar manager graded kitchen';end if;
end $$;
select set_config('request.jwt.claim.sub','68a8567e-625e-41bc-bb37-6744d729c3d4',true);
do $$ declare data jsonb;begin
 data:=public.academy_oral_data(true);
 if (data->>'viewer')::boolean or jsonb_array_length(data->'members')<>1 or exists(select 1 from jsonb_array_elements(data->'assessments') a where a->>'employee_id'<>auth.uid()::text) then raise exception 'Employee sees other results';end if;
end $$;
reset role;
update public.academy_profiles set restaurant_id='khimki',department='Кухня',position='Шеф-повар' where id='4233956d-46bb-44c6-a266-759203b6648a';
set local role authenticated;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
do $$ declare data jsonb;denied boolean;begin
 data:=public.academy_oral_data(true);
 if exists(select 1 from jsonb_array_elements(data->'members') m where m->>'id'='68a8567e-625e-41bc-bb37-6744d729c3d4') then raise exception 'Foreign restaurant results visible';end if;
 denied:=false;begin perform public.academy_save_kitchen_oral('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','{"hot":8,"cold":8,"allergens":8,"sauces":8,"pizza":8,"general":8}');exception when others then denied:=true;end;if not denied then raise exception 'Foreign restaurant chef graded';end if;
end $$;
reset role;
do $$ begin if has_table_privilege('authenticated','public.academy_oral_assessments','INSERT') or has_function_privilege('anon','public.academy_save_kitchen_oral(uuid,text,jsonb,text)','EXECUTE') then raise exception 'Unexpected direct/anonymous access';end if;end $$;
update public.academy_profiles set role='admin' where id='4233956d-46bb-44c6-a266-759203b6648a';
set local role authenticated;
do $$ declare denied boolean;begin
 denied:=false;begin perform public.academy_set_training_level('68a8567e-625e-41bc-bb37-6744d729c3d4','certified');exception when others then denied:=true;end;if not denied then raise exception 'Owner manually certified waiter';end if;
 perform public.academy_save_kitchen_oral('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','{"hot":8,"cold":8,"allergens":8,"sauces":8,"pizza":8,"general":8}','Owner retake');
end $$;
reset role;
do $$ begin if not exists(select 1 from public.academy_profiles where id='68a8567e-625e-41bc-bb37-6744d729c3d4' and training_level='certified') then raise exception 'Both latest passes not certified';end if;end $$;
update public.academy_profiles set restaurant_id='khimki' where id='68a8567e-625e-41bc-bb37-6744d729c3d4';
do $$ begin if exists(select 1 from public.academy_profiles where id='68a8567e-625e-41bc-bb37-6744d729c3d4' and training_level='certified') then raise exception 'Old restaurant certification counted after transfer';end if;end $$;
update public.academy_profiles set restaurant_id='minsk' where id='68a8567e-625e-41bc-bb37-6744d729c3d4';
update public.academy_profiles set role='employee',restaurant_id='minsk',department='Руководитель',position='Управляющий' where id='4233956d-46bb-44c6-a266-759203b6648a';
set local role authenticated;
do $$ declare data jsonb;denied boolean;begin
 data:=public.academy_oral_data(true);
 if not(data->>'viewer')::boolean or not exists(select 1 from jsonb_array_elements(data->'members') m where m->>'id'='68a8567e-625e-41bc-bb37-6744d729c3d4' and not(m->>'can_grade_kitchen')::boolean) then raise exception 'Leader view-only boundary failed';end if;
 denied:=false;begin perform public.academy_save_kitchen_oral('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','{"hot":8,"cold":8,"allergens":8,"sauces":8,"pizza":8,"general":8}');exception when others then denied:=true;end;if not denied then raise exception 'View-only leader graded';end if;
end $$;
reset role;
rollback;
select 'PASS: 47 fails, 48 passes, all six scores required, kitchen alone insufficient, both divisions certify, latest failure resets, chef/bar/employee/restaurant boundaries, history and fixtures rolled back' as test_result;

