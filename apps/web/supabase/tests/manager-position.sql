-- Exercise registration validation; changes to the existing QA profile roll back.
begin;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
select set_config('request.jwt.claims','{"sub":"4233956d-46bb-44c6-a266-759203b6648a","role":"authenticated"}',true);
update public.academy_profiles set role='employee',status='pending' where id=auth.uid();
set local role authenticated;
select public.academy_enroll('Проверка должности','minsk','Руководитель','Управляющий');
select 1/(case when position='Управляющий' and department='Руководитель' and role='employee' and status='pending' then 1 else 0 end) as title_only_assertion from public.academy_profiles where id=auth.uid();
reset role;
rollback;
select 'PASS: managing director title accepted, role remains employee / pending; all profile changes rolled back' as result;
