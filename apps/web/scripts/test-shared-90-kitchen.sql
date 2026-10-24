begin;
do $$ declare a public.academy_profiles;c public.academy_content;rid text;begin
 select * into c from public.academy_content where id like '90-kitchen-%' limit 1;
 if c.id is null then raise exception 'Kitchen not imported';end if;
 a.status:='active';a.role:='manager';a.department:='Кухня';c.published:=false;
 foreach rid in array array['pushkino','khimki','mytishchi'] loop
  a.restaurant_id:=rid;if not academy_private.can_edit_menu_for(a,c) then raise exception 'Own kitchen denied';end if;
 end loop;
 a.department:='Бар';if academy_private.can_edit_menu_for(a,c) then raise exception 'Bar allowed to edit kitchen';end if;
 a.department:='Кухня';a.restaurant_id:='minsk';if academy_private.can_edit_menu_for(a,c) then raise exception 'RVB manager allowed';end if;
 a.restaurant_id:='pushkino';a.role:='employee';if academy_private.can_edit_menu_for(a,c) then raise exception 'Employee edit allowed';end if;
 a.role:='manager';a.status:='pending';if academy_private.can_edit_menu_for(a,c) then raise exception 'Pending edit allowed';end if;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from public.academy_profiles where role='admin' and status='active' limit 1),true);
select set_config('academy.qa_kitchen',(select to_jsonb(c)::text from public.academy_content c where id like '90-kitchen-%' limit 1),true);
set local role authenticated;
select public.academy_save_menu_with_notice(jsonb_set(current_setting('academy.qa_kitchen')::jsonb,'{payload,description}','"Проверка кухни"'),false,'');
select 1/(case when payload->>'description'='Проверка кухни' then 1 else 0 end) as save_pass from public.academy_content where id=current_setting('academy.qa_kitchen')::jsonb->>'id';
select public.academy_save_menu_with_notice(jsonb_set(current_setting('academy.qa_kitchen')::jsonb,'{published}','false'),false,'');
select 1/(case when academy_private.can_read_content(current_setting('academy.qa_kitchen')::jsonb->>'id') then 1 else 0 end) as draft_read_pass;
reset role;
rollback;
select 'PASS: three kitchens allowed; bar / RVB / employee / pending denied; authenticated save and draft read; all rolled back' as result;
