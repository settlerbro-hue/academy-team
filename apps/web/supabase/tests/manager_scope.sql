-- Real manager identity, temporary fixtures, all changes rolled back.
begin;
-- Make the two QA publications visible only inside this transaction, even if archived as drafts.
update public.academy_content set published=true
where restaurant_id='minsk' and department='Бар'
and title in ('[Проверка] Чек-лист открытия бара','[Проверка] Подготовка бара к открытию');
insert into auth.users(id,email) values
('00000000-0000-4000-8000-000000000051','qa-own-bar@example.invalid'),
('00000000-0000-4000-8000-000000000052','qa-other-department@example.invalid'),
('00000000-0000-4000-8000-000000000053','qa-other-restaurant@example.invalid');
insert into public.academy_profiles(id,full_name,restaurant_id,department,status) values
('00000000-0000-4000-8000-000000000051','QA own bar','minsk','Бар','active'),
('00000000-0000-4000-8000-000000000052','QA Minsk hall','minsk','Зал','active'),
('00000000-0000-4000-8000-000000000053','QA Khimki bar','khimki','Бар','active');
insert into public.academy_content(id,kind,title,restaurant_id,department,payload) values
('qa-scope-own','course','QA own','minsk','Бар','{"lessons":[{"id":"l","title":"Lesson"}]}'),
('qa-scope-department','course','QA hall','minsk','Зал','{"lessons":[]}'),
('qa-scope-restaurant','course','QA Khimki','khimki','Бар','{"lessons":[]}');
insert into public.academy_progress(user_id,course_id,lesson_id) values
('00000000-0000-4000-8000-000000000051','qa-scope-own','l'),
('00000000-0000-4000-8000-000000000052','qa-scope-department','l'),
('00000000-0000-4000-8000-000000000053','qa-scope-restaurant','l');
set local role authenticated;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
do $$ declare doc jsonb; dashboard jsonb; begin
 if not exists(select 1 from public.academy_profiles where id=auth.uid() and status='active' and role='manager' and restaurant_id='minsk' and department='Бар') then raise exception 'FAIL actual manager scope'; end if;
 if not exists(select 1 from public.academy_profiles where id='00000000-0000-4000-8000-000000000051') then raise exception 'FAIL own employee hidden'; end if;
 if exists(select 1 from public.academy_profiles where id in ('00000000-0000-4000-8000-000000000052','00000000-0000-4000-8000-000000000053')) then raise exception 'FAIL foreign employee visible'; end if;
 if exists(select 1 from public.academy_content where id in ('qa-scope-department','qa-scope-restaurant')) then raise exception 'FAIL foreign content visible'; end if;
 if exists(select 1 from public.academy_progress where user_id in ('00000000-0000-4000-8000-000000000052','00000000-0000-4000-8000-000000000053')) then raise exception 'FAIL foreign progress visible'; end if;
 dashboard:=public.academy_manager_dashboard();
 if dashboard::text like '%QA Minsk hall%' or dashboard::text like '%QA Khimki bar%' then raise exception 'FAIL dashboard leaks team'; end if;
 doc:='{"id":"qa-manager-material","kind":"material","title":"QA material","restaurant_id":"minsk","department":"Бар","payload":{"text":"QA"},"published":false}';
 perform public.academy_save_content(doc);
 if not exists(select 1 from public.academy_content where id='qa-manager-material') then raise exception 'FAIL own draft hidden'; end if;
 begin perform public.academy_save_content(jsonb_set(doc,'{restaurant_id}','"khimki"')); raise exception 'FAIL create other restaurant'; exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
 begin perform public.academy_save_content(jsonb_set(doc,'{department}','"Зал"')); raise exception 'FAIL create other department'; exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
 begin perform public.academy_save_content('{"id":"qa-scope-restaurant","kind":"course","title":"Hijack","restaurant_id":"minsk","department":"Бар","payload":{}}'); raise exception 'FAIL hijack existing foreign content'; exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
 perform public.academy_save_content('{"id":"qa-manager-test","kind":"test","title":"QA test","course_id":"qa-scope-own","restaurant_id":"minsk","department":"Бар","payload":{"questions":[{"id":"q","type":"single","options":["A","B"]}],"passCount":1}}','{"q":[0]}');
 begin perform public.academy_manage_member('00000000-0000-4000-8000-000000000052','suspended','employee'); raise exception 'FAIL manage other department'; exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
 begin perform public.academy_manage_member('00000000-0000-4000-8000-000000000053','suspended','employee'); raise exception 'FAIL manage other restaurant'; exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
 begin perform public.academy_manage_member('00000000-0000-4000-8000-000000000051','active','manager'); raise exception 'FAIL delegate manager role'; exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
 begin perform public.academy_manage_member(auth.uid(),'active','admin'); raise exception 'FAIL self escalation'; exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
 perform public.academy_manage_member('00000000-0000-4000-8000-000000000051','suspended','employee');
 perform public.academy_manage_member('00000000-0000-4000-8000-000000000051','active','employee');
 begin perform keys from academy_private.test_keys; raise exception 'FAIL private keys read'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000051',true);
do $$ begin
 if (select count(*) from public.academy_content where title in ('[Проверка] Чек-лист открытия бара','[Проверка] Подготовка бара к открытию') and published)<>2 then raise exception 'FAIL own bar cannot read actual manager publications'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000052',true);
do $$ begin
 if exists(select 1 from public.academy_content where title in ('[Проверка] Чек-лист открытия бара','[Проверка] Подготовка бара к открытию')) then raise exception 'FAIL hall sees actual bar publications'; end if;
 if exists(select 1 from public.academy_attempts where user_id='4233956d-46bb-44c6-a266-759203b6648a') then raise exception 'FAIL hall sees manager results'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000053',true);
do $$ begin
 if exists(select 1 from public.academy_content where title in ('[Проверка] Чек-лист открытия бара','[Проверка] Подготовка бара к открытию')) then raise exception 'FAIL Khimki sees actual Minsk publications'; end if;
end $$;
reset role;
select 'PASS actual manager: own team/material/test; foreign restaurant/department denied; no escalation; private keys protected' as manager_scope_result;
rollback;
