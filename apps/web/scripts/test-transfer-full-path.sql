-- Full transfer path against the real functions/RLS, without committing fixtures.
begin;
select set_config('test.old_history',jsonb_build_object(
 'progress',(select coalesce(jsonb_agg(to_jsonb(p) order by course_id,lesson_id),'[]') from public.academy_progress p where user_id='4233956d-46bb-44c6-a266-759203b6648a'),
 'attempts',(select coalesce(jsonb_agg(to_jsonb(a) order by id),'[]') from public.academy_attempts a where user_id='4233956d-46bb-44c6-a266-759203b6648a'),
 'marks',(select coalesce(jsonb_agg(to_jsonb(m) order by item_id),'[]') from public.academy_menu_marks m where user_id='4233956d-46bb-44c6-a266-759203b6648a'))::text,true);
update public.academy_profiles set role='employee',status='active',restaurant_id='minsk',department='Бар',position='Бармен' where id='4233956d-46bb-44c6-a266-759203b6648a';
update public.academy_profiles set role='manager',status='active',restaurant_id='minsk',department='Бар',position='Бармен' where id='68a8567e-625e-41bc-bb37-6744d729c3d4';
insert into public.academy_content(id,kind,title,published,restaurant_id,department,payload) values
 ('qa-transfer-old-menu','menu','QA old menu',true,'minsk','Бар','{"brand":"rvb","menuSection":"bar"}'),
 ('qa-transfer-new-menu','menu','QA new menu',true,'khimki','Зал','{"brand":"90","menuSection":"bar"}'),
 ('qa-transfer-old-course','course','QA old course',true,'minsk','Бар','{"lessons":[{"id":"one","title":"Lesson"}]}'),
 ('qa-transfer-new-course','course','QA new course',true,'khimki','Зал','{"lessons":[{"id":"one","title":"Lesson"}]}');
set local role authenticated;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
do $$ declare r uuid; before_learned integer;begin
 if not academy_private.can_read_content('qa-transfer-old-course') or academy_private.can_read_content('qa-transfer-new-course') then raise exception 'Initial course access wrong';end if;
 perform public.academy_complete_lesson('qa-transfer-old-course','one');
 perform public.academy_set_mark('qa-transfer-old-menu','learned');
 select (j->>'menu_learned')::integer into before_learned from jsonb_array_elements(public.academy_ranking()) j where j->>'user_id'=auth.uid()::text;
 if before_learned<1 then raise exception 'Old progress absent';end if;
 r:=public.academy_request_work_change('khimki','Зал','Хостес');
 perform set_config('test.request',r::text,true);
 if not exists(select 1 from public.academy_profiles where id=auth.uid() and restaurant_id='minsk' and department='Бар' and position='Бармен' and role='employee') then raise exception 'Request changed profile prematurely';end if;
 if not academy_private.can_read_content('qa-transfer-old-course') or academy_private.can_read_content('qa-transfer-new-course') then raise exception 'Request changed access prematurely';end if;
end $$;
select set_config('request.jwt.claim.sub','68a8567e-625e-41bc-bb37-6744d729c3d4',true);
do $$ begin
 if not exists(select 1 from jsonb_array_elements(public.academy_manager_dashboard()->'profiles') p where p->>'id'='4233956d-46bb-44c6-a266-759203b6648a') then raise exception 'Old admin cannot see current employee';end if;
end $$;
reset role;
update public.academy_profiles set restaurant_id='khimki',department='Зал',position='Администратор' where id='68a8567e-625e-41bc-bb37-6744d729c3d4';
set local role authenticated;
do $$ begin
 if not exists(select 1 from jsonb_array_elements(public.academy_work_change_list()) r where r->>'id'=current_setting('test.request') and (r->>'can_review')::boolean) then raise exception 'Receiving admin missing request';end if;
 perform public.academy_review_work_change(current_setting('test.request')::uuid,true);
 if not exists(select 1 from jsonb_array_elements(public.academy_manager_dashboard()->'profiles') p where p->>'id'='4233956d-46bb-44c6-a266-759203b6648a' and p->>'restaurant_id'='khimki' and p->>'position'='Хостес') then raise exception 'New admin dashboard profile stale';end if;
end $$;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
do $$ declare ranking jsonb;begin
 if not exists(select 1 from public.academy_profiles where id=auth.uid() and restaurant_id='khimki' and department='Зал' and position='Хостес' and role='employee' and status='active') then raise exception 'New profile wrong';end if;
 if academy_private.can_read_content('qa-transfer-old-course') or not academy_private.can_read_content('qa-transfer-new-course') then raise exception 'New course access wrong';end if;
 if exists(select 1 from public.academy_content where id='qa-transfer-old-course') or not exists(select 1 from public.academy_content where id='qa-transfer-new-course') then raise exception 'Content RLS wrong';end if;
 if not exists(select 1 from public.academy_menu_marks where item_id='qa-transfer-old-menu' and status='learned') then raise exception 'Old mark lost';end if;
 select j into ranking from jsonb_array_elements(public.academy_ranking()) j where j->>'user_id'=auth.uid()::text;
 if (ranking->>'menu_total')::integer<>1 or (ranking->>'menu_learned')::integer<>0 then raise exception 'Old brand progress counted: %',ranking;end if;
 perform public.academy_complete_lesson('qa-transfer-new-course','one');
 perform public.academy_set_mark('qa-transfer-new-menu','learned');
 select j into ranking from jsonb_array_elements(public.academy_ranking()) j where j->>'user_id'=auth.uid()::text;
 if (ranking->>'menu_learned')::integer<>1 then raise exception 'New learning not counted';end if;
 if not exists(select 1 from public.academy_progress where user_id=auth.uid() and course_id='qa-transfer-old-course') then raise exception 'Old course completion lost';end if;
end $$;
select set_config('request.jwt.claim.sub','68a8567e-625e-41bc-bb37-6744d729c3d4',true);
do $$ declare stat jsonb;begin
 select j into stat from jsonb_array_elements(public.academy_manager_dashboard()->'menu_stats') j where j->>'user_id'='4233956d-46bb-44c6-a266-759203b6648a';
 if (stat->>'total')::integer<>1 or (stat->>'learned')::integer<>1 then raise exception 'New admin menu stats wrong: %',stat;end if;
 if not exists(select 1 from jsonb_array_elements(public.academy_manager_dashboard()->'progress') p where p->>'user_id'='4233956d-46bb-44c6-a266-759203b6648a' and p->>'course_id'='qa-transfer-new-course') then raise exception 'New admin missing new completion';end if;
end $$;
reset role;
update public.academy_profiles set restaurant_id='minsk',department='Бар',position='Бармен' where id='68a8567e-625e-41bc-bb37-6744d729c3d4';
set local role authenticated;
do $$ begin
 if exists(select 1 from jsonb_array_elements(public.academy_manager_dashboard()->'profiles') p where p->>'id'='4233956d-46bb-44c6-a266-759203b6648a') or exists(select 1 from public.academy_progress where user_id='4233956d-46bb-44c6-a266-759203b6648a') or exists(select 1 from public.academy_menu_marks where user_id='4233956d-46bb-44c6-a266-759203b6648a') then raise exception 'Old admin retains access';end if;
end $$;
reset role;
do $$ declare history jsonb;begin
 select jsonb_build_object(
 'progress',(select coalesce(jsonb_agg(to_jsonb(p) order by course_id,lesson_id),'[]') from public.academy_progress p where user_id='4233956d-46bb-44c6-a266-759203b6648a' and course_id not like 'qa-transfer-%'),
 'attempts',(select coalesce(jsonb_agg(to_jsonb(a) order by id),'[]') from public.academy_attempts a where user_id='4233956d-46bb-44c6-a266-759203b6648a'),
 'marks',(select coalesce(jsonb_agg(to_jsonb(m) order by item_id),'[]') from public.academy_menu_marks m where user_id='4233956d-46bb-44c6-a266-759203b6648a' and item_id not like 'qa-transfer-%')) into history;
 if history<>current_setting('test.old_history')::jsonb then raise exception 'Existing history changed';end if;
end $$;
rollback;
select 'PASS: request, receiving administrator approval, updated profile, course/menu RLS, old-team access removed, new menu progress/ranking/dashboard, original history intact; all fixtures rolled back' as full_path_result;
