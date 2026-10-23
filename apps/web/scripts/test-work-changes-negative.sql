-- Additional negative checks, always rolled back.
begin;
update public.academy_profiles set role='employee',status='active',restaurant_id='minsk',department='Бар',position='Бармен' where id='4233956d-46bb-44c6-a266-759203b6648a';
update public.academy_profiles set role='manager',status='active',restaurant_id='pushkino',department='Бар',position='Бармен' where id='68a8567e-625e-41bc-bb37-6744d729c3d4';
set local role authenticated;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
select public.academy_request_work_change('khimki','Зал','Хостес');
reset role;
select set_config('test.work_request_id',(select id::text from public.academy_work_changes where status='pending' and user_id='4233956d-46bb-44c6-a266-759203b6648a'),true);
select set_config('request.jwt.claim.sub','68a8567e-625e-41bc-bb37-6744d729c3d4',true);
set local role authenticated;
do $$ declare denied boolean;begin
 if jsonb_array_length(public.academy_work_change_list())<>0 then raise exception 'Wrong team sees request';end if;
 denied:=false;begin perform public.academy_review_work_change(current_setting('test.work_request_id')::uuid,true);exception when others then denied:=true;end;if not denied then raise exception 'Wrong team approved request';end if;
 denied:=false;begin perform public.academy_assign_work('4233956d-46bb-44c6-a266-759203b6648a','pushkino','Бар','Бармен');exception when others then denied:=true;end;if not denied then raise exception 'Wrong team directly assigned employee';end if;
end $$;
reset role;
update public.academy_profiles set restaurant_id='khimki',department='Зал',position='Администратор' where id='68a8567e-625e-41bc-bb37-6744d729c3d4';
set local role authenticated;
select public.academy_review_work_change(current_setting('test.work_request_id')::uuid,false);
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
do $$ declare r uuid;begin
 if (select restaurant_id from public.academy_profiles where id=auth.uid())<>'minsk' then raise exception 'Rejection changed work';end if;
 r:=public.academy_request_work_change('khimki','Зал','Хостес');
 perform public.academy_cancel_work_change(r);
 if exists(select 1 from jsonb_array_elements(public.academy_work_change_list()) x where x->>'status'='pending') then raise exception 'Cancellation failed';end if;
end $$;
reset role;
do $$ begin
 if has_table_privilege('authenticated','public.academy_work_changes','INSERT') or has_table_privilege('authenticated','public.academy_work_changes','UPDATE') or has_function_privilege('anon','public.academy_assign_work(uuid,text,text,text)','EXECUTE') then raise exception 'Unexpected direct/anonymous access';end if;
end $$;
rollback;
select 'PASS: wrong-team isolation, rejection, cancellation, direct writes and anonymous calls denied; fixtures rolled back' as test_result;
