-- Tests are rolled back; no real role, title, or access changes survive.
begin;
do $$
declare owner_id uuid; employee_id uuid; denied boolean; restaurant text; department text;
begin
 select id into owner_id from public.academy_profiles where role='admin' and status='active' limit 1;
 select id into employee_id from public.academy_profiles where role='employee' and status='active' limit 1;
 if owner_id is null or employee_id is null then raise exception 'QA identities unavailable';end if;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);execute 'set local role authenticated';
 denied:=false;begin perform public.academy_set_operations_director(employee_id,true);exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'Owner could appoint a second operations director';end if;
 execute 'reset role';
 denied:=false;begin update public.academy_profiles set role='manager',department='Руководитель',position='Операционный директор',restaurant_id=null,operations_director=true where id=employee_id;exception when check_violation then denied:=true;end;
 if not denied then raise exception 'Direct operations access bypassed constraint';end if;
 denied:=false;begin update public.academy_profiles set position='Операционный директор' where id=employee_id;exception when check_violation then denied:=true;end;
 if not denied then raise exception 'Reserved title could be assigned without access';end if;
 perform set_config('request.jwt.claim.sub','d4c13a7d-27c6-434d-812b-6bd477166573',true);execute 'set local role authenticated';
 if not academy_private.is_operations_director() then raise exception 'Kucher access lost';end if;
 foreach restaurant in array array['minsk','pushkino','khimki','mytishchi'] loop
  foreach department in array array['Бар','Кухня','Зал','Арт','Кальян','Руководитель'] loop
   if not academy_private.can_edit(restaurant,department) then raise exception 'Kucher lost venue scope';end if;
  end loop;
 end loop;
 execute 'reset role';
 if (select count(*) from public.academy_profiles where operations_director or position='Операционный директор')<>1 then raise exception 'Operations identity not unique';end if;
end $$;
rollback;
select 'PASS: second appointment denied even to owner, direct access/title writes rejected, Kucher retains all four venues and six departments. No real profiles changed.' result;
