-- All fixtures, account changes and notices roll back. No email or external delivery.
begin;
delete from academy_private.notifications;
delete from academy_private.notification_checks;
update public.academy_content set published=false where kind in ('course','test');
update public.academy_profiles set role='employee',status='active',restaurant_id='minsk',department='Бар',position='Бармен' where id='68a8567e-625e-41bc-bb37-6744d729c3d4';
update public.academy_profiles set role='manager',status='active',restaurant_id='minsk',department='Бар',position='Бар-менеджер' where id='4233956d-46bb-44c6-a266-759203b6648a';
insert into auth.users(id,email) values('00000000-0000-4000-8000-000000000015','notifications-qa@example.invalid');
insert into public.academy_profiles(id,full_name,role,status,restaurant_id,department,position) values('00000000-0000-4000-8000-000000000015','QA новая заявка','employee','pending','minsk','Бар','Бармен');
do $$ begin
 if not exists(select 1 from academy_private.notifications where user_id='4233956d-46bb-44c6-a266-759203b6648a' and event_key='enrollment:00000000-0000-4000-8000-000000000015') then raise exception 'Administrator missed registration';end if;
 if not exists(select 1 from academy_private.notifications where user_id='00000000-0000-4000-8000-000000000015' and category='account') then raise exception 'Registration receipt missing';end if;
end $$;
update public.academy_profiles set status='active',restaurant_id='mytishchi' where id='00000000-0000-4000-8000-000000000015';
set local role authenticated;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
select public.academy_save_content_with_notice('{"id":"qa-notice-course","kind":"course","title":"QA курс бара","published":true,"restaurant_id":"minsk","department":"Бар","payload":{"priority":"additional","audiencePositions":["Бармен"],"audiencePriorities":{"Бармен":"start"},"lessons":[{"id":"one","title":"QA lesson"}],"dueAt":"2020-01-01"}}',null,true,'Прочитать перед сменой');
select public.academy_save_content_with_notice('{"id":"qa-notice-draft","kind":"course","title":"QA черновик","published":false,"restaurant_id":"minsk","department":"Бар","payload":{"lessons":[]}}',null,true,'Не рассылать');
select public.academy_save_content_with_notice('{"id":"qa-notice-other-position","kind":"course","title":"QA только старшим барменам","published":true,"restaurant_id":"minsk","department":"Бар","payload":{"audiencePositions":["Старший бармен"],"lessons":[]}}',null,true,'');
select public.academy_save_content_with_notice('{"id":"qa-notice-material","kind":"material","title":"QA файл библиотеки","published":true,"restaurant_id":"minsk","department":"Бар","payload":{"brand":"rvb"}}',null,false,'');
select public.academy_save_menu_with_notice('{"id":"qa-notice-menu-1","kind":"menu","title":"QA напиток 1","published":true,"restaurant_id":"minsk","payload":{"brand":"rvb","menuSection":"bar","name":"QA напиток 1"}}',false,'');
select public.academy_save_menu_with_notice('{"id":"qa-notice-menu-2","kind":"menu","title":"QA напиток 2","published":true,"restaurant_id":"minsk","payload":{"brand":"rvb","menuSection":"bar","name":"QA напиток 2"}}',false,'');
select public.academy_announce_content(array['qa-notice-menu-1','qa-notice-menu-2'],'Изменились составы');
select public.academy_announce_content(array['qa-notice-course'],'Повтор не должен дублироваться');
reset role;
insert into public.academy_material_files(material_id,storage_path,filename,mime_type,byte_size,status,uploaded_by) values('qa-notice-material','qa-notice-file.pdf','QA файл.pdf','application/pdf',1,'ready','4233956d-46bb-44c6-a266-759203b6648a');
set local role authenticated;
select public.academy_announce_content(array['qa-notice-material'],'Новый PDF');
select set_config('request.jwt.claim.sub','68a8567e-625e-41bc-bb37-6744d729c3d4',true);
do $$ declare r jsonb;denied boolean;id uuid;begin
 r:=public.academy_notifications(200,false);
 if (select count(*) from jsonb_array_elements(r->'items') where value->>'category'='publication')<>3 then raise exception 'Expected course, grouped menu, file exactly once: %',r;end if;
 if not exists(select 1 from jsonb_array_elements(r->'items') n where n->>'title'='Курс опубликован: QA курс бара' and n->>'body' like 'Важно для начала работы%') then raise exception 'Position priority missing';end if;
 if not exists(select 1 from jsonb_array_elements(r->'items') n where jsonb_array_length(n->'targets')=2) then raise exception 'Menu changes not grouped';end if;
 if exists(select 1 from jsonb_array_elements(r->'items') n where n->>'body' like '%Не рассылать%') then raise exception 'Draft leaked';end if;
 denied:=false;begin perform public.academy_announce_content(array['qa-notice-course'],'');exception when others then denied:=true;end;if not denied then raise exception 'Employee published notice';end if;
 denied:=false;begin perform count(*) from academy_private.notifications;exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Private table exposed';end if;
 id:=(r->'items'->0->>'id')::uuid;perform public.academy_read_notifications(id,null);
 if exists(select 1 from jsonb_array_elements(public.academy_notifications(200,true)->'items') n where n->>'id'=id::text) then raise exception 'Read filter wrong';end if;
 perform public.academy_read_notifications(null,(r->>'as_of')::timestamptz);
 if (public.academy_notifications(200,true)->>'unread')::integer<>0 then raise exception 'Read all failed';end if;
end $$;
reset role;
do $$ begin
 if exists(select 1 from academy_private.notifications where user_id='00000000-0000-4000-8000-000000000015' and category='publication') then raise exception 'Other restaurant received publication';end if;
 if exists(select 1 from public.academy_progress where user_id='68a8567e-625e-41bc-bb37-6744d729c3d4' and course_id='qa-notice-course') then raise exception 'Reading notice completed a lesson';end if;
 if not exists(select 1 from academy_private.notifications where user_id='68a8567e-625e-41bc-bb37-6744d729c3d4' and category='reminder') then raise exception 'Deadline reminder missing';end if;
end $$;
-- Revision changes create a new notification; the same version does not.
update public.academy_content set payload=payload||'{"price":"99"}' where id='qa-notice-menu-1';
set local role authenticated;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
select public.academy_announce_content(array['qa-notice-menu-1'],'Новая цена');
reset role;
-- Hide stale publication events when a staff member changes restaurant or position.
update public.academy_profiles set restaurant_id='mytishchi' where id='68a8567e-625e-41bc-bb37-6744d729c3d4';
set local role authenticated;
select set_config('request.jwt.claim.sub','68a8567e-625e-41bc-bb37-6744d729c3d4',true);
do $$ begin if exists(select 1 from jsonb_array_elements(public.academy_notifications(200,false)->'items') n where n->>'category'='publication') then raise exception 'Old restaurant content remains visible';end if;end $$;
select public.academy_request_work_change('minsk','Бар','Барбэк');
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
do $$ declare id uuid;r jsonb;begin
 r:=public.academy_notifications(200,false);
 if not exists(select 1 from jsonb_array_elements(r->'items') n where n->>'category'='work_review') then raise exception 'Receiving administrator missed transfer';end if;
 id:=(select (value->>'id')::uuid from jsonb_array_elements(public.academy_work_change_list()) where value->>'status'='pending' and value->>'user_id'='68a8567e-625e-41bc-bb37-6744d729c3d4');
 perform public.academy_review_work_change(id,true);
end $$;
reset role;
-- Administrator loses events after leaving the responsible team.
update public.academy_profiles set restaurant_id='pushkino' where id='4233956d-46bb-44c6-a266-759203b6648a';
set local role authenticated;
do $$ begin if exists(select 1 from jsonb_array_elements(public.academy_notifications(200,false)->'items') n where n->>'category'='work_review') then raise exception 'Old receiving-team request leaked';end if;end $$;
reset role;
update public.academy_profiles set restaurant_id='minsk' where id='4233956d-46bb-44c6-a266-759203b6648a';
insert into public.academy_content(id,kind,title,course_id,published,restaurant_id,department,payload) values('qa-notice-written','test','QA письменный тест','qa-notice-course',true,'minsk','Бар','{"passCount":1,"questions":[{"id":"q","type":"text","text":"QA"}]}');
insert into academy_private.test_keys values('qa-notice-written','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','68a8567e-625e-41bc-bb37-6744d729c3d4',true);
do $$ declare id uuid;begin id:=(public.academy_start_test('qa-notice-written')->>'attempt_id')::uuid;perform public.academy_submit_test(id,'{"q":"QA answer"}');perform set_config('test.notice_attempt',id::text,true);end $$;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
do $$ begin if not exists(select 1 from jsonb_array_elements(public.academy_notifications(200,false)->'items') n where n->>'title'='Письменный тест ждёт проверки') then raise exception 'Review event missing';end if;end $$;
select public.academy_review_attempt(current_setting('test.notice_attempt')::uuid,1,'Хороший ответ');
select public.academy_save_bar_oral('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','{"wine":8,"spirits":8,"beer":8,"cocktails":8,"nonalcoholic":8,"specials":8,"alternatives":8,"pairing":8}','QA устный результат');
select set_config('request.jwt.claim.sub','68a8567e-625e-41bc-bb37-6744d729c3d4',true);
do $$ declare r jsonb;begin r:=public.academy_notifications(200,false);
 if not exists(select 1 from jsonb_array_elements(r->'items') n where n->>'title'='Письменный ответ проверен' and n->>'body' like '%Хороший ответ%') then raise exception 'Reviewed result missing';end if;
 if not exists(select 1 from jsonb_array_elements(r->'items') n where n->>'body' like '%QA устный результат%') then raise exception 'Oral result missing';end if;
 if not exists(select 1 from jsonb_array_elements(r->'items') n where n->>'title'='Перевод подтверждён') then raise exception 'Work decision missing';end if;
end $$;
reset role;
-- Deadlines: repeated maintenance cannot flood an inbox; cron is active.
select academy_private.run_notification_digest();select academy_private.run_notification_digest();
do $$ begin
 if (select count(*) from academy_private.notifications where user_id='68a8567e-625e-41bc-bb37-6744d729c3d4' and category='reminder')<>1 then raise exception 'Duplicate reminders';end if;
 if not exists(select 1 from cron.job where jobname='academy-notifications-hourly' and active) then raise exception 'Scheduled maintenance missing';end if;
end $$;
rollback;
select 'PASS: employee/admin boundaries, course audience, menu grouping, library file, drafts silent, deduplication, read one/all, no progress side effects, transfer rights, written review, oral result, deadline cadence and active scheduler; all fixtures rolled back' as test_result;
