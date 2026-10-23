begin;
-- Hide real curriculum only inside this rolled-back fixture transaction.
update public.academy_content set published=false where kind in ('course','test');
update public.academy_profiles set role='employee',status='active',restaurant_id='minsk',department='Зал',position='Официант' where id='68a8567e-625e-41bc-bb37-6744d729c3d4';
update public.academy_profiles set role='manager',status='active',restaurant_id='minsk',department='Кухня',position='Шеф-повар' where id='4233956d-46bb-44c6-a266-759203b6648a';
insert into public.academy_content(id,kind,title,published,restaurant_id,department,course_id,payload) values
('qa-general-course','course','QA required',true,'minsk','Зал',null,'{"priority":"additional","audiencePositions":["Официант"],"audiencePriorities":{"Официант":"start"},"lessons":[{"id":"one","title":"Lesson"}]}'),
('qa-general-quiz','test','QA quiz',true,'minsk','Зал','qa-general-course','{"priority":"attestation","passCount":1,"timeLimitSeconds":0,"questions":[{"id":"q","type":"single","text":"QA","options":["yes","no"]}]}'),
('qa-general-written','test','QA written',true,'minsk','Зал','qa-general-course','{"priority":"attestation","passCount":1,"timeLimitSeconds":0,"questions":[{"id":"q","type":"text","text":"QA written"}]}'),
('qa-general-extra','course','QA extra',true,'minsk','Зал',null,'{"priority":"start","audiencePositions":["Официант"],"audiencePriorities":{"Официант":"additional"},"lessons":[{"id":"one"}]}'),
('qa-general-other','course','QA other department',true,'minsk','Кухня',null,'{"priority":"start","lessons":[{"id":"one"}]}');
insert into academy_private.test_keys(test_id,keys) values('qa-general-quiz','{"q":[0]}'),('qa-general-written','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','68a8567e-625e-41bc-bb37-6744d729c3d4',true);
do $$ declare attempt uuid;r jsonb;begin
 r:=(public.academy_oral_data(false)->'members'->0->'general');
 if (r->>'courses_total')::integer<>1 or (r->>'tests_total')::integer<>2 or (r->>'passed')::boolean then raise exception 'Wrong required plan: %',r;end if;
 perform public.academy_complete_lesson('qa-general-course','one');
 attempt:=(public.academy_start_test('qa-general-quiz')->>'attempt_id')::uuid;perform public.academy_submit_test(attempt,'{"q":[0]}');
 attempt:=(public.academy_start_test('qa-general-written')->>'attempt_id')::uuid;perform public.academy_submit_test(attempt,'{"q":"answer"}');
 perform set_config('test.written_attempt',attempt::text,true);
 r:=(public.academy_oral_data(false)->'members'->0->'general');
 if (r->>'passed')::boolean or (r->>'tests_passed')::integer<>1 then raise exception 'Pending manual review counted';end if;
end $$;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
select public.academy_save_kitchen_oral('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','{"hot":8,"cold":8,"allergens":8,"sauces":8,"pizza":8,"general":8}');
do $$ declare denied boolean;begin
 denied:=false;begin perform public.academy_save_bar_oral('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','{"wine":8,"spirits":8,"beer":8,"cocktails":8,"nonalcoholic":8,"specials":8,"alternatives":8,"pairing":8}');exception when others then denied:=true;end;if not denied then raise exception 'Chef graded bar';end if;
end $$;
reset role;
update public.academy_profiles set department='Бар',position='Бар-менеджер' where id='4233956d-46bb-44c6-a266-759203b6648a';
set local role authenticated;
select public.academy_save_bar_oral('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','{"wine":8,"spirits":8,"beer":8,"cocktails":8,"nonalcoholic":8,"specials":8,"alternatives":8,"pairing":8}');
reset role;
do $$ begin if exists(select 1 from public.academy_profiles where id='68a8567e-625e-41bc-bb37-6744d729c3d4' and training_level='certified') then raise exception 'Two oral exams certified before general';end if;end $$;
update public.academy_profiles set role='admin' where id='4233956d-46bb-44c6-a266-759203b6648a';
set local role authenticated;
select public.academy_review_attempt(current_setting('test.written_attempt')::uuid,1,'QA reviewed');
reset role;
do $$ declare g jsonb;begin
 g:=academy_private.general_training_status('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','Зал','Официант');
 if not(g->>'passed')::boolean or (g->>'courses_completed')::integer<>1 or (g->>'tests_passed')::integer<>2 then raise exception 'General status wrong after review: %',g;end if;
 if not exists(select 1 from public.academy_profiles where id='68a8567e-625e-41bc-bb37-6744d729c3d4' and training_level='certified') then raise exception 'All three did not auto certify';end if;
 if not exists(select 1 from public.academy_oral_assessments where employee_id='68a8567e-625e-41bc-bb37-6744d729c3d4' and division='bar' and category_count=8 and score_total=64 and average=8 and passed) then raise exception 'Bar denominator wrong';end if;
end $$;
insert into public.academy_content(id,kind,title,published,restaurant_id,department,payload) values('qa-general-new','course','QA new required',true,'minsk','Зал','{"priority":"attestation","audiencePositions":["Официант"],"lessons":[{"id":"one"}]}');
do $$ begin if exists(select 1 from public.academy_profiles where id='68a8567e-625e-41bc-bb37-6744d729c3d4' and training_level='certified') then raise exception 'New required content did not reset general';end if;end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','68a8567e-625e-41bc-bb37-6744d729c3d4',true);
select public.academy_complete_lesson('qa-general-new','one');
reset role;
do $$ begin if not exists(select 1 from public.academy_profiles where id='68a8567e-625e-41bc-bb37-6744d729c3d4' and training_level='certified') then raise exception 'Completion did not restore certification';end if;end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
select public.academy_save_bar_oral('68a8567e-625e-41bc-bb37-6744d729c3d4','minsk','{"wine":7,"spirits":8,"beer":8,"cocktails":8,"nonalcoholic":8,"specials":8,"alternatives":8,"pairing":8}');
reset role;
do $$ begin if exists(select 1 from public.academy_profiles where id='68a8567e-625e-41bc-bb37-6744d729c3d4' and training_level='certified') then raise exception '63/80 incorrectly passed';end if;end $$;
rollback;
select 'PASS: eight bar categories, 64 passes/63 fails, three required attestations, own-position priority, additional/other-department exclusions, pending review, automatic recalculation after tests/lessons/content; fixtures rolled back' as test_result;
