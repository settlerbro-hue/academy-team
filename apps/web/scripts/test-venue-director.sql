-- This file is appended to staged migration 033 inside one rollback-only transaction.
do $$
declare fixture_id uuid; owner_id uuid; actor_id uuid; staff_ids uuid[]; home text; r text; dep text; own boolean; denied boolean; a public.academy_profiles; c public.academy_content; doc jsonb; result jsonb; f jsonb; n integer:=0;
begin
 select id into owner_id from public.academy_profiles where role='admin' and status='active' limit 1;
 actor_id:=gen_random_uuid();staff_ids:=array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
 foreach fixture_id in array array_prepend(actor_id,staff_ids) loop
  insert into auth.users(id,aud,role,email) values(fixture_id,'authenticated','authenticated','qa-venue-'||fixture_id||'@example.invalid');
  insert into public.academy_profiles(id,full_name,status,role,restaurant_id,department,position) values(fixture_id,'QA venue fixture','active','employee','minsk','Бар','Бармен') on conflict(id) do update set status='active',role='employee',restaurant_id='minsk',department='Бар',position='Бармен';
 end loop;
 if owner_id is null then raise exception 'QA owner missing';end if;
 for i in 1..4 loop update public.academy_profiles set restaurant_id=(array['minsk','pushkino','khimki','mytishchi'])[i] where id=staff_ids[i];end loop;
 foreach r in array array['minsk','pushkino','khimki','mytishchi'] loop
  foreach dep in array array['Зал','Бар','Кухня','Арт','Кальян','Руководитель'] loop
   insert into public.academy_content(id,kind,title,restaurant_id,department,published,payload) values('qa-vd-'||r||'-'||dep,'material','QA '||r||dep,r,dep,false,jsonb_build_object('brand',case when r='minsk' then 'rvb' else '90' end,'body','QA'));
  end loop;
 end loop;
 insert into public.academy_content(id,kind,title,published,payload) values
 ('qa-vd-common','material','QA common',true,'{"brand":"common","body":"QA"}'),
 ('qa-vd-shared90','material','QA 90',true,'{"brand":"90","body":"QA"}'),
 ('qa-vd-sharedrvb','material','QA RVB',true,'{"brand":"rvb","body":"QA"}');
 foreach home in array array['minsk','khimki'] loop
  update public.academy_profiles set restaurant_id=home,department='Руководитель',position='Управляющий' where id=actor_id;
  perform set_config('request.jwt.claim.sub',owner_id::text,true);execute 'set local role authenticated';perform public.academy_set_venue_director(actor_id,true);execute 'reset role';
  select * into a from public.academy_profiles where id=actor_id;
  if not a.venue_director or a.role<>'manager' then raise exception 'Grant failed';end if;
  perform set_config('request.jwt.claim.sub',actor_id::text,true);execute 'set local role authenticated';
  foreach r in array array['minsk','pushkino','khimki','mytishchi'] loop
   own:=(home='minsk' and r='minsk') or(home<>'minsk' and r<>'minsk');
   foreach dep in array array['Зал','Бар','Кухня','Арт','Кальян','Руководитель'] loop
    if exists(select 1 from public.academy_content where id='qa-vd-'||r||'-'||dep) is distinct from own then raise exception 'Content RLS boundary: % % %',home,r,dep;end if;
    if academy_private.can_edit(r,dep) is distinct from own then raise exception 'Editing boundary';end if;
    n:=n+1;
   end loop;
  end loop;
  result:=public.academy_manager_dashboard();
  if exists(select 1 from jsonb_array_elements(result->'profiles') p where p->>'id'<>actor_id::text and not academy_private.venue_scope(a,p->>'restaurant_id')) then raise exception 'Dashboard leaked another brand';end if;
  result:=public.academy_ranking();if exists(select 1 from jsonb_array_elements(result) p where not academy_private.venue_scope(a,p->>'restaurant_id')) then raise exception 'Ranking leaked another brand';end if;
  result:=public.academy_oral_data(true);if exists(select 1 from jsonb_array_elements(result->'members') p where (p->>'can_grade_kitchen')::boolean or (p->>'can_grade_bar')::boolean) then raise exception 'Examiner rights widened';end if;if exists(select 1 from jsonb_array_elements(result->'members') p where not academy_private.venue_scope(a,p->>'restaurant_id')) then raise exception 'Oral dashboard leaked another brand';end if;
  foreach r in array array['90','rvb'] loop
   own:=(home='minsk' and r='rvb')or(home<>'minsk' and r='90');
   if exists(select 1 from public.academy_content where id='qa-vd-shared'||r) is distinct from own then raise exception 'Shared library boundary';end if;
   select to_jsonb(x) into doc from public.academy_content x where id='qa-vd-shared'||r;
   if own then
    perform public.academy_save_content(doc,null);
    f:=public.academy_reserve_material_file('qa-vd-shared'||r,'qa.pdf','application/pdf',100);
    insert into storage.objects(bucket_id,name) values('academy-materials',f->>'storage_path');
   end if;
  end loop;
  select to_jsonb(x) into doc from public.academy_content x where id='qa-vd-common';
  denied:=false;begin perform public.academy_save_content(doc,null);exception when others then denied:=true;end;if not denied then raise exception 'Shared cross-brand document was editable';end if;
  doc:=jsonb_build_object('id','qa-vd-new-'||home,'kind','course','title','QA course','restaurant_id',home,'department','Кухня','published',true,'payload',jsonb_build_object('title','QA','priority','start','audiencePositions',jsonb_build_array('Повар'),'audienceLevels',jsonb_build_array('trainee','certified'),'lessons',jsonb_build_array(jsonb_build_object('id','qa-vd-lesson','title','QA lesson','blocks',jsonb_build_array(jsonb_build_object('id','qa-vd-block','type','text','html','<p>QA</p>'))))));
  perform public.academy_save_course_editor(doc,null,null,true,false,'');
  f:=public.academy_reserve_course_media(doc->>'id','qa.jpg','image/jpeg',100);insert into storage.objects(bucket_id,name) values('academy-course-media',f->>'storage_path');
  doc:=jsonb_build_object('id','qa-vd-test-'||home,'kind','test','title','QA test','course_id','qa-vd-new-'||home,'restaurant_id',home,'department','Кухня','published',true,'payload',jsonb_build_object('questions',jsonb_build_array(jsonb_build_object('id','qa-q','text','QA','type','single','options',jsonb_build_array('A','B','C'))),'passCount',1));
  perform public.academy_save_content(doc,'{"qa-q":[0]}');
  foreach r in array array['minsk','pushkino','khimki','mytishchi'] loop
   own:=(home='minsk' and r='minsk')or(home<>'minsk' and r<>'minsk');
   foreach dep in array array['bar','kitchen'] loop
    doc:=jsonb_build_object('id','qa-vd-menu-'||home||r||dep,'kind','menu','title','QA menu','restaurant_id',r,'department',null,'published',true,'payload',jsonb_build_object('name','QA','brand',case when r='minsk' then 'rvb' else '90' end,'menuSection',dep));
    if own then perform public.academy_save_menu(doc);else denied:=false;begin perform public.academy_save_menu(doc);exception when others then denied:=true;end;if not denied then raise exception 'Foreign menu edit allowed';end if;end if;
   end loop;
  end loop;
  if home<>'minsk' then
   doc:=jsonb_build_object('id','qa-vd-menu-shared90','kind','menu','title','QA shared menu','restaurant_id',null,'department',null,'published',true,'payload',jsonb_build_object('name','QA','brand','90','menuSection','bar'));perform public.academy_save_menu(doc);
  end if;
  denied:=false;begin perform public.academy_assign_work(case when home='minsk' then staff_ids[1] else staff_ids[2] end,case when home='minsk' then 'khimki' else 'minsk' end,'Бар','Бармен');exception when others then denied:=true;end;if not denied then raise exception 'Cross-brand transfer allowed';end if;
  denied:=false;begin perform public.academy_manage_member(case when home='minsk' then staff_ids[1] else staff_ids[2] end,'active','manager');exception when others then denied:=true;end;if not denied then raise exception 'Role escalation allowed';end if;
  denied:=false;begin perform public.academy_set_venue_director(staff_ids[1],true);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Managing director could delegate privilege';end if;
  execute 'reset role';perform set_config('request.jwt.claim.sub',owner_id::text,true);execute 'set local role authenticated';perform public.academy_set_venue_director(actor_id,false);execute 'reset role';
  if (select role<>'employee' or venue_director from public.academy_profiles where id=actor_id) then raise exception 'Revocation did not restore role';end if;
 end loop;
 if n<>48 then raise exception 'Incomplete scope coverage';end if;
end $$;
rollback;
select 'PASS: 48 venue/department boundaries; scoped dashboards, shared-brand library, course publication and protected uploads; cross-brand transfer and role escalation denied; oral examiner rights unchanged; revocation restores role. Everything rolled back.' result;
