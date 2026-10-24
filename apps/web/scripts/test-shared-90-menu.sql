-- Isolated composite actors test scope; no accounts are created or assigned roles.
begin;
do $$
declare a public.academy_profiles;c public.academy_content;rid text;
begin
 select * into c from public.academy_content where id='90-bar-r119-1';
 if c.id is null then raise exception 'Menu not imported';end if;
 c.published:=false; -- Administrators retain their narrow scope for unpublished cards.
 a.status:='active';a.role:='manager';a.department:='Бар';
 foreach rid in array array['pushkino','khimki','mytishchi'] loop
  a.restaurant_id:=rid;if not academy_private.can_edit_menu_for(a,c) then raise exception 'Own brand denied';end if;
 end loop;
 a.restaurant_id:='minsk';if academy_private.can_edit_menu_for(a,c) then raise exception 'RVB manager allowed';end if;
 a.restaurant_id:='pushkino';a.department:='Кухня';if academy_private.can_edit_menu_for(a,c) then raise exception 'Kitchen manager allowed';end if;
 a.department:='Бар';a.role:='employee';if academy_private.can_edit_menu_for(a,c) then raise exception 'Employee allowed';end if;
 a.role:='manager';a.status:='pending';if academy_private.can_edit_menu_for(a,c) then raise exception 'Pending allowed';end if;
 a.status:='active';a.restaurant_id:='khimki';c.restaurant_id:='pushkino';if academy_private.can_edit_menu_for(a,c) then raise exception 'Other restaurant-specific card allowed';end if;
end $$;
-- Exercise actual authenticated save RPC as existing owner, with automatic rollback.
select set_config('request.jwt.claim.sub',(select id::text from public.academy_profiles where role='admin' and status='active' limit 1),true);
select set_config('academy.qa_90_card',(select to_jsonb(c)::text from public.academy_content c where id='90-bar-r119-1'),true);
set local role authenticated;
select public.academy_save_menu_with_notice(jsonb_set(current_setting('academy.qa_90_card')::jsonb,'{payload,description}','"Проверка сохранения карточки"'),false,'');
select 1/(case when payload->>'description'='Проверка сохранения карточки' then 1 else 0 end) as save_pass from public.academy_content where id='90-bar-r119-1';
select public.academy_save_menu_with_notice(jsonb_set(current_setting('academy.qa_90_card')::jsonb,'{published}','false'),false,'');
select 1/(case when academy_private.can_read_content('90-bar-r119-1') then 1 else 0 end) as draft_read_pass;
reset role;
rollback;
select 'PASS: all three 90-е bar scopes; RVB, kitchen, employee, pending and other restaurant denied; authenticated save works; rolled back' as result;
