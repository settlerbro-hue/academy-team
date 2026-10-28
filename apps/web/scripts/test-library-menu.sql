-- Run within one transaction after migration 034; never commit fixtures.
do $$
declare owner_id uuid; ids uuid[]:=array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()]; uid uuid; allowed boolean; p public.academy_profiles; c public.academy_content; doc jsonb; bad jsonb; denied boolean; old record;
begin
 for old in select * from qa_library_before loop
  perform set_config('request.jwt.claim.sub',old.uid::text,true);
  if academy_private.can_read_content(old.cid) is distinct from old.allowed then raise exception 'Existing library access changed: % %',old.uid,old.cid;end if;
 end loop;
 select id into owner_id from public.academy_profiles where role='admin' and status='active' limit 1;
 for i in 1..6 loop
  uid:=ids[i];insert into auth.users(id,aud,role,email) values(uid,'authenticated','authenticated','qa-library-'||uid||'@example.invalid');
  insert into public.academy_profiles(id,full_name,status,role,restaurant_id,department,position) values(uid,'QA library','active',case when i=6 then 'manager' else 'employee' end,case when i=5 then 'khimki' else 'minsk' end,case when i=3 then 'Кухня' when i=4 then 'Зал' else 'Бар' end,case when i=3 then 'Повар' when i=4 then 'Официант' when i=2 then 'Бармен' when i=6 then 'Старший бармен' else 'Барбэк' end)
  on conflict(id) do update set status=excluded.status,role=excluded.role,restaurant_id=excluded.restaurant_id,department=excluded.department,position=excluded.position;
 end loop;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 doc:='{"id":"qa-library-multi","kind":"material","title":"QA library","restaurant_id":"minsk","published":true,"payload":{"brand":"rvb","body":"QA","libraryAccess":{"enabled":true,"departments":["Бар","Кухня"],"positions":["Барбэк","Повар"]}}}';
 execute 'set local role authenticated';perform public.academy_save_content(doc,null);execute 'reset role';
 insert into public.academy_material_files(material_id,storage_path,filename,mime_type,byte_size,status,uploaded_by) values('qa-library-multi','qa-library/file.pdf','qa.pdf','application/pdf',100,'ready',owner_id);
 insert into storage.objects(bucket_id,name) values('academy-materials','qa-library/file.pdf');
 for i in 1..6 loop
  uid:=ids[i];allowed:=i in (1,3);perform set_config('request.jwt.claim.sub',uid::text,true);
  select * into p from public.academy_profiles where id=uid;select * into c from public.academy_content where id='qa-library-multi';
  if academy_private.notice_content_for(p,c) is distinct from allowed then raise exception 'Notice audience mismatch %',i;end if;
  execute 'set local role authenticated';
  if exists(select 1 from public.academy_content where id='qa-library-multi') is distinct from allowed then raise exception 'Material RLS mismatch %',i;end if;
  if exists(select 1 from public.academy_material_files where material_id='qa-library-multi') is distinct from allowed then raise exception 'File RLS mismatch %',i;end if;
  if exists(select 1 from storage.objects where bucket_id='academy-materials' and name='qa-library/file.pdf') is distinct from allowed then raise exception 'Storage RLS mismatch %',i;end if;
  denied:=false;begin perform public.academy_save_content(doc,null);exception when others then denied:=true;end;if not denied then raise exception 'Unauthorised ACL write %',i;end if;
  execute 'reset role';
 end loop;
 -- An administrator retains editing and preview in their existing department.
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 doc:=jsonb_set(jsonb_set(jsonb_set(doc,'{id}','"qa-library-local"'),'{department}','"Бар"'),'{payload,libraryAccess}','{"enabled":true,"departments":["Бар"],"positions":["Барбэк"]}');perform public.academy_save_content(doc,null);
 perform set_config('request.jwt.claim.sub',ids[6]::text,true);execute 'set local role authenticated';
 if not exists(select 1 from public.academy_content where id='qa-library-local') then raise exception 'Admin preview denied';end if;
 perform public.academy_save_content(doc,null);execute 'reset role';
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 for bad in select value from jsonb_array_elements('[{"enabled":true,"departments":[],"positions":[]},{"enabled":true,"departments":["Бар"],"positions":["Повар"]},{"enabled":"true"},{"enabled":true,"departments":["Бар"],"positions":["Операционный директор"]}]') loop
  denied:=false;begin perform public.academy_save_content(jsonb_set(doc,'{payload,libraryAccess}',bad),null);exception when others then denied:=true;end;if not denied then raise exception 'Invalid library audience accepted';end if;
 end loop;
 foreach allowed in array array[true,false] loop
  doc:=jsonb_build_object('id',case when allowed then 'qa-new-rvb' else 'qa-new-90' end,'kind','menu','title','QA menu','published',true,'restaurant_id',case when allowed then 'minsk' else 'khimki' end,'payload',jsonb_build_object('brand',case when allowed then 'rvb' else '90' end,'menuSection','bar','isNewItem',true,'newBadgeUntil',now()+interval '14 days'));
  execute 'set local role authenticated';perform public.academy_save_menu(doc);execute 'reset role';
  for bad in select value from jsonb_array_elements('[{"isNewItem":true,"newBadgeUntil":"bad"},{"isNewItem":true,"newBadgeUntil":"2000-01-01"},{"isNewItem":true},{"isNewItem":"true"}]') loop
   denied:=false;begin perform public.academy_save_menu(jsonb_set(doc,'{payload}',((doc->'payload')-'isNewItem'-'newBadgeUntil')||bad));exception when others then denied:=true;end;if not denied then raise exception 'Invalid new badge accepted';end if;
  end loop;
  perform public.academy_save_menu(jsonb_set(doc,'{payload}',(doc->'payload')-'isNewItem'-'newBadgeUntil'));
 end loop;
 raise notice 'PASS: legacy visibility unchanged; department/job, venue, notification, material/file/storage boundaries; administrator preview; invalid audiences and badges rejected; both brands.';
end $$;
rollback;
