-- Read-only role checks; the one guard probe is rolled back inside its exception block.
do $safety$ begin
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('academy_content_catalog','academy_lesson_content') and p.prosecdef) then raise exception 'Catalog must use invoker RLS';end if;
 if has_function_privilege('anon','public.academy_content_catalog(text,text)','EXECUTE') or has_function_privilege('anon','public.academy_lesson_content(text,text)','EXECUTE') then raise exception 'Anonymous execute must be denied';end if;
 begin insert into public.academy_content(id,kind,title,payload,published) values('qa-lazy-catalog-save-guard','material','QA summary guard','{"_catalogOnly":true}'::jsonb,false);raise exception 'Summary save guard failed';exception when others then if position('Сначала загрузите' in sqlerrm)=0 then raise;end if;end;
end $safety$;

begin;
select set_config('request.jwt.claim.sub',coalesce((select id::text from public.academy_profiles where status='active' and role in ('admin','manager') order by (role='admin') desc,created_at limit 1),''),true);
select set_config('qa.denied_course_id',coalesce((select c.id from public.academy_content c where c.kind='course' and jsonb_array_length(coalesce(c.payload->'lessons','[]'::jsonb))>0 and not academy_private.can_read_content(c.id) limit 1),'qa-nonexistent-course'),true);
select set_config('qa.denied_lesson_id',coalesce((select c.payload->'lessons'->0->>'id' from public.academy_content c where c.id=current_setting('qa.denied_course_id')),'0'),true);
set local role authenticated;
do $qa$ declare catalog_row public.academy_content;original public.academy_content;first_lesson jsonb;expected_id text;actual_lesson jsonb;begin
 if (select count(*) from public.academy_content_catalog())<>(select count(*) from public.academy_content visible_c where visible_c.published or exists(select 1 from public.academy_profiles p where p.id=auth.uid() and p.role<>'employee')) then raise exception 'Catalog changed visibility';end if;
 for catalog_row in select * from public.academy_content_catalog() loop
  select * into original from public.academy_content where id=catalog_row.id;
  if (to_jsonb(catalog_row)-'payload') is distinct from (to_jsonb(original)-'payload') then raise exception 'Catalog metadata mismatch';end if;
  if catalog_row.kind='menu' and catalog_row.payload is distinct from original.payload then raise exception 'Menu changed';end if;
  if catalog_row.kind<>'menu' and (catalog_row.payload->>'_catalogOnly' is distinct from 'true' or catalog_row.payload ?| array['body','html','content','text','questions','guide','categories','files','attachments','blocks']) then raise exception 'Heavy body in catalog';end if;
  if catalog_row.kind='course' then
   if jsonb_array_length(catalog_row.payload->'lessons')<>coalesce(jsonb_array_length(original.payload->'lessons'),0) then raise exception 'Lesson count mismatch';end if;
   if exists(select 1 from jsonb_array_elements(catalog_row.payload->'lessons') l where l ?| array['html','body','content','text','blocks','video','links']) then raise exception 'Heavy lesson in catalog';end if;
   first_lesson:=original.payload->'lessons'->0;if first_lesson is not null then expected_id:=coalesce(first_lesson->>'id','0');actual_lesson:=public.academy_lesson_content(catalog_row.id,expected_id);if actual_lesson is distinct from first_lesson||jsonb_build_object('id',expected_id) then raise exception 'Lesson content mismatch';end if;end if;
  elsif catalog_row.kind='test' then if (catalog_row.payload->>'questionCount')::integer<>coalesce(jsonb_array_length(original.payload->'questions'),0) then raise exception 'Question count mismatch';end if;end if;
 end loop;
 if public.academy_lesson_content(current_setting('qa.denied_course_id'),current_setting('qa.denied_lesson_id')) is not null then raise exception 'Unavailable lesson must be null';end if;
end $qa$;
select 'manager' as audience,(select count(*) from public.academy_content_catalog()) as catalog_records,(select sum(octet_length(to_jsonb(c)::text)) from public.academy_content c where c.published or exists(select 1 from public.academy_profiles p where p.id=auth.uid() and p.role<>'employee')) as full_bytes,(select sum(octet_length(to_jsonb(c)::text)) from public.academy_content_catalog() c) as catalog_bytes;
rollback;

begin;
select set_config('request.jwt.claim.sub',coalesce((select id::text from public.academy_profiles where status='active' and role='employee' and department='Бар' order by created_at limit 1),''),true);
select set_config('qa.denied_course_id',coalesce((select c.id from public.academy_content c where c.kind='course' and jsonb_array_length(coalesce(c.payload->'lessons','[]'::jsonb))>0 and not academy_private.can_read_content(c.id) limit 1),'qa-nonexistent-course'),true);
select set_config('qa.denied_lesson_id',coalesce((select c.payload->'lessons'->0->>'id' from public.academy_content c where c.id=current_setting('qa.denied_course_id')),'0'),true);
set local role authenticated;
do $qa$ declare catalog_row public.academy_content;original public.academy_content;first_lesson jsonb;expected_id text;actual_lesson jsonb;begin
 if (select count(*) from public.academy_content_catalog())<>(select count(*) from public.academy_content visible_c where visible_c.published or exists(select 1 from public.academy_profiles p where p.id=auth.uid() and p.role<>'employee')) then raise exception 'Catalog changed visibility';end if;
 for catalog_row in select * from public.academy_content_catalog() loop
  select * into original from public.academy_content where id=catalog_row.id;
  if (to_jsonb(catalog_row)-'payload') is distinct from (to_jsonb(original)-'payload') then raise exception 'Catalog metadata mismatch';end if;
  if catalog_row.kind='menu' and catalog_row.payload is distinct from original.payload then raise exception 'Menu changed';end if;
  if catalog_row.kind<>'menu' and (catalog_row.payload->>'_catalogOnly' is distinct from 'true' or catalog_row.payload ?| array['body','html','content','text','questions','guide','categories','files','attachments','blocks']) then raise exception 'Heavy body in catalog';end if;
  if catalog_row.kind='course' then
   if jsonb_array_length(catalog_row.payload->'lessons')<>coalesce(jsonb_array_length(original.payload->'lessons'),0) then raise exception 'Lesson count mismatch';end if;
   if exists(select 1 from jsonb_array_elements(catalog_row.payload->'lessons') l where l ?| array['html','body','content','text','blocks','video','links']) then raise exception 'Heavy lesson in catalog';end if;
   first_lesson:=original.payload->'lessons'->0;if first_lesson is not null then expected_id:=coalesce(first_lesson->>'id','0');actual_lesson:=public.academy_lesson_content(catalog_row.id,expected_id);if actual_lesson is distinct from first_lesson||jsonb_build_object('id',expected_id) then raise exception 'Lesson content mismatch';end if;end if;
  elsif catalog_row.kind='test' then if (catalog_row.payload->>'questionCount')::integer<>coalesce(jsonb_array_length(original.payload->'questions'),0) then raise exception 'Question count mismatch';end if;end if;
 end loop;
 if public.academy_lesson_content(current_setting('qa.denied_course_id'),current_setting('qa.denied_lesson_id')) is not null then raise exception 'Unavailable lesson must be null';end if;
end $qa$;
select 'bar' as audience,(select count(*) from public.academy_content_catalog()) as catalog_records,(select sum(octet_length(to_jsonb(c)::text)) from public.academy_content c where c.published or exists(select 1 from public.academy_profiles p where p.id=auth.uid() and p.role<>'employee')) as full_bytes,(select sum(octet_length(to_jsonb(c)::text)) from public.academy_content_catalog() c) as catalog_bytes;
rollback;

begin;
select set_config('request.jwt.claim.sub',coalesce((select id::text from public.academy_profiles where status='active' and role='employee' and department='Зал' order by created_at limit 1),''),true);
select set_config('qa.denied_course_id',coalesce((select c.id from public.academy_content c where c.kind='course' and jsonb_array_length(coalesce(c.payload->'lessons','[]'::jsonb))>0 and not academy_private.can_read_content(c.id) limit 1),'qa-nonexistent-course'),true);
select set_config('qa.denied_lesson_id',coalesce((select c.payload->'lessons'->0->>'id' from public.academy_content c where c.id=current_setting('qa.denied_course_id')),'0'),true);
set local role authenticated;
do $qa$ declare catalog_row public.academy_content;original public.academy_content;first_lesson jsonb;expected_id text;actual_lesson jsonb;begin
 if (select count(*) from public.academy_content_catalog())<>(select count(*) from public.academy_content visible_c where visible_c.published or exists(select 1 from public.academy_profiles p where p.id=auth.uid() and p.role<>'employee')) then raise exception 'Catalog changed visibility';end if;
 for catalog_row in select * from public.academy_content_catalog() loop
  select * into original from public.academy_content where id=catalog_row.id;
  if (to_jsonb(catalog_row)-'payload') is distinct from (to_jsonb(original)-'payload') then raise exception 'Catalog metadata mismatch';end if;
  if catalog_row.kind='menu' and catalog_row.payload is distinct from original.payload then raise exception 'Menu changed';end if;
  if catalog_row.kind<>'menu' and (catalog_row.payload->>'_catalogOnly' is distinct from 'true' or catalog_row.payload ?| array['body','html','content','text','questions','guide','categories','files','attachments','blocks']) then raise exception 'Heavy body in catalog';end if;
  if catalog_row.kind='course' then
   if jsonb_array_length(catalog_row.payload->'lessons')<>coalesce(jsonb_array_length(original.payload->'lessons'),0) then raise exception 'Lesson count mismatch';end if;
   if exists(select 1 from jsonb_array_elements(catalog_row.payload->'lessons') l where l ?| array['html','body','content','text','blocks','video','links']) then raise exception 'Heavy lesson in catalog';end if;
   first_lesson:=original.payload->'lessons'->0;if first_lesson is not null then expected_id:=coalesce(first_lesson->>'id','0');actual_lesson:=public.academy_lesson_content(catalog_row.id,expected_id);if actual_lesson is distinct from first_lesson||jsonb_build_object('id',expected_id) then raise exception 'Lesson content mismatch';end if;end if;
  elsif catalog_row.kind='test' then if (catalog_row.payload->>'questionCount')::integer<>coalesce(jsonb_array_length(original.payload->'questions'),0) then raise exception 'Question count mismatch';end if;end if;
 end loop;
 if public.academy_lesson_content(current_setting('qa.denied_course_id'),current_setting('qa.denied_lesson_id')) is not null then raise exception 'Unavailable lesson must be null';end if;
end $qa$;
select 'hall' as audience,(select count(*) from public.academy_content_catalog()) as catalog_records,(select sum(octet_length(to_jsonb(c)::text)) from public.academy_content c where c.published or exists(select 1 from public.academy_profiles p where p.id=auth.uid() and p.role<>'employee')) as full_bytes,(select sum(octet_length(to_jsonb(c)::text)) from public.academy_content_catalog() c) as catalog_bytes;
rollback;
