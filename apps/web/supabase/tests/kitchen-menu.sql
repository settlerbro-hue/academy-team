-- Run in SQL Editor as postgres. All edits and simulated role assignments roll back.
begin;
select 1/(case when count(*)=92 and count(distinct payload->>'image')=83 then 1 else 0 end) as kitchen_count_assertion
from public.academy_content where id like 'rvb-kitchen-p%';
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
select set_config('request.jwt.claims','{"sub":"4233956d-46bb-44c6-a266-759203b6648a","role":"authenticated"}',true);
select set_config('academy.qa_document',(select to_jsonb(c)::text from public.academy_content c where id='rvb-kitchen-p03-1'),true);
set local role authenticated;
-- Existing bar manager can study the kitchen, but cannot edit that other department.
select 1/(case when count(*)=92 then 1 else 0 end) as staff_read_assertion from public.academy_content where id like 'rvb-kitchen-p%';
do $$ begin
 begin
  perform public.academy_save_menu(current_setting('academy.qa_document')::jsonb);
  raise exception 'Unexpected kitchen edit permission';
 exception when raise_exception then if SQLERRM='Unexpected kitchen edit permission' then raise; end if; end;
end $$;
reset role;
update public.academy_profiles set department='Кухня' where id=auth.uid();
set local role authenticated;
select public.academy_save_menu(jsonb_set(current_setting('academy.qa_document')::jsonb,'{payload,description}','"QA kitchen description"'::jsonb));
select 1/(case when payload->>'description'='QA kitchen description' and department is null then 1 else 0 end) as manager_save_assertion from public.academy_content where id='rvb-kitchen-p03-1';
do $$ begin
 begin
  perform public.academy_save_menu(jsonb_set(current_setting('academy.qa_document')::jsonb,'{restaurant_id}','"pushkino"'::jsonb));
  raise exception 'Unexpected foreign restaurant edit';
 exception when raise_exception then if SQLERRM='Unexpected foreign restaurant edit' then raise; end if; end;
end $$;
reset role;
update public.academy_profiles set role='employee' where id=auth.uid();
set local role authenticated;
do $$ begin
 begin
  perform public.academy_save_menu(current_setting('academy.qa_document')::jsonb);
  raise exception 'Unexpected employee edit';
 exception when raise_exception then if SQLERRM='Unexpected employee edit' then raise; end if; end;
end $$;
reset role;
rollback;
select 'PASS: 92 cards / 83 images, staff read, kitchen manager saves, other department / restaurant and employee edits denied; all changes rolled back' as result;
