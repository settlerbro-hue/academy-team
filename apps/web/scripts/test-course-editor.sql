begin;
insert into public.academy_content(id,kind,title,published,restaurant_id,department,payload) values
('qa-course-editor','course','QA course editor',true,'minsk','Бар','{"priority":"additional","audiencePositions":["Бармен"],"audienceLevels":["trainee","certified"],"lessons":[{"id":"stable","title":"Stable lesson","text":"Published original"}]}'),
('qa-course-foreign','course','QA outside scope',false,'mytishchi','Бар','{"lessons":[]}');
set local role authenticated;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
do $$ declare r jsonb;doc jsonb;denied boolean;begin
 r:=public.academy_course_editor('qa-course-editor');doc:=r->'document';
 doc:=jsonb_set(doc,'{payload,lessons,0,blocks}','[{"id":"b","type":"heading","text":"Draft heading","level":2}]');
 r:=public.academy_save_course_editor(doc,(r->>'live_updated_at')::timestamptz,null,false,false,'');
 if not (r->>'has_draft')::boolean then raise exception 'Draft was not saved';end if;
 perform set_config('test.ce.doc',doc::text,true);perform set_config('test.ce.base',r->>'live_updated_at',true);perform set_config('test.ce.draft',r->>'draft_updated_at',true);
 denied:=false;begin perform public.academy_save_course_editor(doc,'2000-01-01',null,false,false,'');exception when others then denied:=true;end;if not denied then raise exception 'Stale live version accepted';end if;
 denied:=false;begin perform public.academy_save_course_editor(doc,(r->>'live_updated_at')::timestamptz,null,false,false,'');exception when others then denied:=true;end;if not denied then raise exception 'Stale draft accepted';end if;
 denied:=false;begin perform public.academy_course_editor('qa-course-foreign');exception when others then denied:=true;end;if not denied then raise exception 'Foreign manager access';end if;
 denied:=false;begin perform public.academy_save_course_editor(jsonb_set(doc,'{payload,lessons,0,id}','"replacement"'),(r->>'live_updated_at')::timestamptz,(r->>'draft_updated_at')::timestamptz,true,false,'');exception when others then denied:=true;end;if not denied then raise exception 'Historical lesson ID removed';end if;
end $$;
reset role;
do $$ begin if exists(select 1 from public.academy_content where id='qa-course-editor' and payload->'lessons'->0 ? 'blocks') then raise exception 'Draft changed live course';end if;end $$;
set local role authenticated;
select public.academy_save_course_editor(current_setting('test.ce.doc')::jsonb,current_setting('test.ce.base')::timestamptz,current_setting('test.ce.draft')::timestamptz,true,false,'');
do $$ declare m jsonb;denied boolean;begin
 m:=public.academy_reserve_course_media('qa-course-editor','test.png','image/png',10);perform set_config('test.ce.media',m->>'id',true);
 denied:=false;begin perform public.academy_finish_course_media((m->>'id')::uuid);exception when others then denied:=true;end;if not denied then raise exception 'Incomplete upload marked ready';end if;
end $$;
select set_config('request.jwt.claim.sub','48fc7ee6-32df-44a3-a3ae-0ca0f91cf89b',true);
do $$ declare denied boolean;begin
 denied:=false;begin perform public.academy_course_editor('qa-course-editor');exception when others then denied:=true;end;if not denied then raise exception 'Employee opened editor';end if;
 denied:=false;begin perform count(*) from academy_private.course_drafts;exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Draft table exposed';end if;
 if exists(select 1 from public.academy_course_media where id=current_setting('test.ce.media')::uuid) then raise exception 'Draft media exposed';end if;
end $$;
reset role;
update public.academy_course_media set status='ready' where id=current_setting('test.ce.media')::uuid;
update public.academy_content set payload=jsonb_set(payload,'{lessons,0,blocks}',jsonb_build_array(jsonb_build_object('id','image','type','image','src','course-media:'||current_setting('test.ce.media')))) where id='qa-course-editor';
set local role authenticated;
do $$ begin if not exists(select 1 from public.academy_course_media where id=current_setting('test.ce.media')::uuid) then raise exception 'Published referenced media missing';end if;end $$;
reset role;
update public.academy_content set published=false where id='qa-course-editor';
set local role authenticated;
do $$ begin if exists(select 1 from public.academy_course_media where id=current_setting('test.ce.media')::uuid) then raise exception 'Unpublished course media exposed';end if;end $$;
reset role;
rollback;
select 'PASS: scoped administrator and employee access, private drafts, live isolation, version conflicts, preserved lesson IDs, validated upload, published-reference media policy; fixtures rolled back' as test_result;
