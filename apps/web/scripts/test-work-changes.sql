-- All fixture changes are rolled back, including assignments and audit rows.
begin;
update public.academy_profiles set role='employee',status='active',restaurant_id='minsk',department='Бар',position='Бармен' where id='4233956d-46bb-44c6-a266-759203b6648a';
update public.academy_profiles set role='manager',status='active',restaurant_id='khimki',department='Зал',position='Администратор' where id='68a8567e-625e-41bc-bb37-6744d729c3d4';
set local role authenticated;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
do $$ declare r uuid; failed boolean; begin
 r:=public.academy_request_work_change('khimki','Зал','Хостес');
 if (select restaurant_id from public.academy_profiles where id=auth.uid())<>'minsk' then raise exception 'Request changed access before approval'; end if;
 failed:=false;begin perform public.academy_request_work_change('khimki','Зал','Хостес');exception when others then failed:=true;end;if not failed then raise exception 'Duplicate pending accepted';end if;
 failed:=false;begin perform public.academy_assign_work(auth.uid(),'minsk','Бар','Старший бармен');exception when others then failed:=true;end;if not failed then raise exception 'Employee assigned own work';end if;
 failed:=false;begin perform public.academy_review_work_change(r,true);exception when others then failed:=true;end;if not failed then raise exception 'Self approval accepted';end if;
 failed:=false;begin perform public.academy_request_work_change('minsk','Бар','Владелец');exception when others then failed:=true;end;if not failed then raise exception 'Invalid position accepted';end if;
 if jsonb_array_length(public.academy_work_change_list())<>1 then raise exception 'Own request not listed';end if;
end $$;
select set_config('request.jwt.claim.sub','68a8567e-625e-41bc-bb37-6744d729c3d4',true);
do $$ declare r uuid; begin
 r:=(public.academy_work_change_list()->0->>'id')::uuid;
 if r is null or not (public.academy_work_change_list()->0->>'can_review')::boolean then raise exception 'Receiving admin cannot review';end if;
 perform public.academy_review_work_change(r,true);
 if not exists(select 1 from public.academy_profiles where id='4233956d-46bb-44c6-a266-759203b6648a' and restaurant_id='khimki' and department='Зал' and position='Хостес' and role='employee') then raise exception 'Approval did not apply';end if;
 perform public.academy_assign_work('4233956d-46bb-44c6-a266-759203b6648a','pushkino','Бар','Барбэк');
 if exists(select 1 from public.academy_profiles where id='4233956d-46bb-44c6-a266-759203b6648a') then raise exception 'Old team still sees transferred employee';end if;
end $$;
reset role;
update public.academy_profiles set role='manager',restaurant_id='minsk',department='Бар',position='Бармен' where id='4233956d-46bb-44c6-a266-759203b6648a';
set local role authenticated;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
select public.academy_request_work_change('khimki','Зал','Администратор');
select set_config('request.jwt.claim.sub','68a8567e-625e-41bc-bb37-6744d729c3d4',true);
do $$ begin if exists(select 1 from jsonb_array_elements(public.academy_work_change_list()) r where r->>'status'='pending') then raise exception 'Manager request visible to another manager';end if;end $$;
reset role;
update public.academy_profiles set role='admin' where id='68a8567e-625e-41bc-bb37-6744d729c3d4';
set local role authenticated;
do $$ declare r uuid; begin
 select (j->>'id')::uuid into r from jsonb_array_elements(public.academy_work_change_list()) j where j->>'status'='pending';
 perform public.academy_review_work_change(r,true);
 if not exists(select 1 from public.academy_profiles where id='4233956d-46bb-44c6-a266-759203b6648a' and role='manager' and restaurant_id='khimki') then raise exception 'Owner approval changed role or failed';end if;
end $$;
reset role;
rollback;
select 'PASS: employee requests, duplicate protection, no self approval, scoped admin review, direct transfer, role preservation; fixtures rolled back' as test_result;
