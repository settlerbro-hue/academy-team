-- Owner-approved venue director access. No people are appointed by this migration.
begin;
-- Venue director access approved by the owner. Assigns no accounts.
alter table public.academy_profiles add column if not exists venue_director boolean not null default false;
alter table public.academy_profiles add column if not exists venue_director_base_role text check(venue_director_base_role in ('employee','manager'));
alter table public.academy_profiles add constraint academy_venue_director_identity check(not venue_director or coalesce((role='manager' and not operations_director and position='Управляющий' and department='Руководитель' and restaurant_id in ('minsk','pushkino','khimki','mytishchi')),false));
create or replace function academy_private.venue_scope(a public.academy_profiles,r text) returns boolean language sql stable set search_path='' as $$
 select coalesce(a.status='active' and a.role='manager' and a.venue_director and a.position='Управляющий' and a.department='Руководитель' and ((a.restaurant_id='minsk' and r='minsk') or (a.restaurant_id in ('pushkino','khimki','mytishchi') and r in ('pushkino','khimki','mytishchi'))),false)
$$;
create or replace function academy_private.venue_document(a public.academy_profiles,c public.academy_content,editing boolean) returns boolean language plpgsql stable security definer set search_path='' as $$
declare brand text; p public.academy_content; required text[];
begin
 if not coalesce(a.venue_director and a.status='active' and a.role='manager' and a.position='Управляющий' and a.department='Руководитель' and not a.operations_director,false) then return false;end if;
 brand:=case when a.restaurant_id='minsk' then 'rvb' else '90' end;
 if c.course_id is not null then
  select * into p from public.academy_content where id=c.course_id and kind='course' and course_id is null;
  if p.id is null or not academy_private.venue_document(a,p,false) then return false;end if;
 end if;
 if c.restaurant_id is not null then return academy_private.venue_scope(a,c.restaurant_id) and coalesce(c.payload->>'brand',brand) in (brand,'common');end if;
 if c.payload->>'brand' in ('rvb','90') then return c.payload->>'brand'=brand;end if;
 if c.course_id is not null then
  return p.id is not null and academy_private.venue_document(a,p,editing);
 end if;
 if jsonb_typeof(c.payload->'requiredRestaurantIds')='array' and jsonb_array_length(c.payload->'requiredRestaurantIds')>0 then
  select array_agg(value) into required from jsonb_array_elements_text(c.payload->'requiredRestaurantIds');
  return case when editing then not exists(select 1 from unnest(required) r where not academy_private.venue_scope(a,r)) else exists(select 1 from unnest(required) r where academy_private.venue_scope(a,r)) end;
 end if;
 return not editing and c.published;
end $$;
create or replace function academy_private.can_edit_record(c public.academy_content) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select case when a.venue_director then academy_private.venue_document(a,c,true) else academy_private.can_edit(c.restaurant_id,c.department) end from public.academy_profiles a where a.id=auth.uid()),false)
$$;
create or replace function academy_private.can_manage(p_user_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_profiles a join public.academy_profiles b on b.id=p_user_id where a.id=auth.uid() and a.status='active' and
 (a.role='admin' or a.operations_director and b.role<>'admin' and not b.operations_director and b.id<>a.id or
 a.venue_director and academy_private.venue_scope(a,b.restaurant_id) and b.role<>'admin' and not b.operations_director and not b.venue_director and b.id<>a.id or
 a.role='manager' and not a.venue_director and a.restaurant_id=b.restaurant_id and a.department=b.department and b.role='employee'))
$$;
create or replace function academy_private.can_edit(p_restaurant text,p_department text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_profiles a where a.id=auth.uid() and a.status='active' and (a.role='admin' or a.operations_director or academy_private.venue_scope(a,p_restaurant) or a.role='manager' and not a.venue_director and p_restaurant=a.restaurant_id and p_department=a.department))
$$;
create or replace function public.academy_set_venue_director(p_user_id uuid,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
declare a public.academy_profiles;b public.academy_profiles;
begin
 select * into a from public.academy_profiles where id=auth.uid() and status='active';
 if a.id is null or not(a.role='admin' or a.operations_director) then raise exception 'Допуск управляющего выдаёт владелец или операционный директор.' using errcode='42501';end if;
 select * into b from public.academy_profiles where id=p_user_id for update;
 if b.id is null or b.id=a.id or b.role='admin' or b.operations_director or b.status<>'active' or b.position is distinct from 'Управляющий' or b.department is distinct from 'Руководитель' or b.restaurant_id is null or p_enabled is null then raise exception 'Выберите активного управляющего с указанным заведением.';end if;
 update public.academy_profiles set venue_director=p_enabled,role=case when p_enabled then 'manager' when b.venue_director then coalesce(b.venue_director_base_role,'employee') else b.role end,
 venue_director_base_role=case when p_enabled then case when b.venue_director then b.venue_director_base_role else b.role end else null end,updated_at=now() where id=b.id;
 update public.academy_work_changes set status='cancelled',reviewed_at=now(),reviewed_by=a.id where user_id=b.id and status='pending';
 insert into academy_private.audit_log(actor_id,action,target,details) values(a.id,'set_venue_director',b.id::text,jsonb_build_object('enabled',p_enabled,'restaurant',b.restaurant_id,'brand',case when b.restaurant_id='minsk' then 'rvb' else '90' end));
end $$;
revoke all on function public.academy_set_venue_director(uuid,boolean) from public,anon;
grant execute on function public.academy_set_venue_director(uuid,boolean) to authenticated;
revoke all on function academy_private.venue_scope(public.academy_profiles,text),academy_private.venue_document(public.academy_profiles,public.academy_content,boolean),academy_private.can_edit_record(public.academy_content) from public,anon;
grant execute on function academy_private.venue_scope(public.academy_profiles,text),academy_private.venue_document(public.academy_profiles,public.academy_content,boolean),academy_private.can_edit_record(public.academy_content) to authenticated;

-- academy_save_content
CREATE OR REPLACE FUNCTION public.academy_save_content(p_document jsonb, p_keys jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare old public.academy_content; rid text:=p_document->>'restaurant_id'; dep text:=p_document->>'department';
begin
 if not academy_private.can_edit_record(jsonb_populate_record(null::public.academy_content,p_document)) then raise exception 'Forbidden'; end if;
 select * into old from public.academy_content where id=p_document->>'id';
 if old.id is not null and not academy_private.can_edit_record(old) then raise exception 'Forbidden'; end if;
 -- Keys must never enter the exposed payload, including nested fields.
 if jsonb_path_exists(p_document->'payload','$.**.correct') or jsonb_path_exists(p_document->'payload','$.**.key_snapshot') then raise exception 'Keep answer keys private'; end if;
 insert into public.academy_content(id,kind,title,course_id,payload,published,restaurant_id,department)
 values(p_document->>'id',p_document->>'kind',p_document->>'title',p_document->>'course_id',p_document->'payload',coalesce((p_document->>'published')::boolean,true),rid,dep)
 on conflict(id) do update set title=excluded.title,payload=excluded.payload,published=excluded.published,restaurant_id=excluded.restaurant_id,department=excluded.department,updated_at=now();
 if p_keys is not null then
 if p_document->>'kind'<>'test' or jsonb_typeof(p_keys)<>'object' then raise exception 'Invalid test keys'; end if;
 insert into academy_private.test_keys(test_id,keys) values(p_document->>'id',p_keys) on conflict(test_id) do update set keys=excluded.keys;
 end if;
 insert into academy_private.audit_log(actor_id,action,target) values(auth.uid(),'content_save',p_document->>'id');
end $function$;
-- can_read_material_file
CREATE OR REPLACE FUNCTION academy_private.can_read_material_file(p_material text, p_status text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.academy_content c where c.id=p_material and c.kind='material'
 and (academy_private.can_edit_record(c)
 or (p_status='ready' and c.published and academy_private.can_read_content(c.id))))
$function$;
-- academy_reserve_material_file
CREATE OR REPLACE FUNCTION public.academy_reserve_material_file(p_material_id text, p_filename text, p_mime_type text, p_byte_size bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.academy_content; f public.academy_material_files; ext text; file_id uuid:=gen_random_uuid();
begin
 select * into c from public.academy_content where id=p_material_id and kind='material' for update;
 if c.id is null or not academy_private.can_edit_record(c) then raise exception 'Forbidden'; end if;
 ext:=case p_mime_type when 'application/pdf' then 'pdf' when 'image/jpeg' then 'jpg' when 'image/png' then 'png'
 when 'image/webp' then 'webp' when 'image/gif' then 'gif' when 'video/mp4' then 'mp4' when 'video/webm' then 'webm' end;
 if ext is null or p_byte_size is null or p_byte_size<=0 or p_byte_size>52428800 then raise exception 'Unsupported file or size limit'; end if;
 if p_filename is null or length(trim(p_filename))=0 or length(p_filename)>240 then raise exception 'Invalid filename'; end if;
 if (select count(*) from public.academy_material_files where material_id=c.id and status<>'archived')>=10 then raise exception 'Maximum 10 files per material'; end if;
 insert into public.academy_material_files(id,material_id,storage_path,filename,mime_type,byte_size,uploaded_by)
 values(file_id,c.id,c.id||'/'||file_id::text||'.'||ext,left(regexp_replace(p_filename,'[[:cntrl:]]','','g'),200),p_mime_type,p_byte_size,auth.uid()) returning * into f;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'material_file_reserve',f.id::text,jsonb_build_object('material_id',c.id));
 return to_jsonb(f);
end $function$;
-- academy_finish_material_file
CREATE OR REPLACE FUNCTION public.academy_finish_material_file(p_file_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.academy_material_files; c public.academy_content; object_meta jsonb;
begin
 select * into f from public.academy_material_files where id=p_file_id for update;
 select * into c from public.academy_content where id=f.material_id and kind='material';
 if f.id is null or c.id is null or not academy_private.can_edit_record(c) then raise exception 'Forbidden'; end if;
 select metadata into object_meta from storage.objects where bucket_id='academy-materials' and name=f.storage_path;
 if object_meta is null or (object_meta->>'size')::bigint is distinct from f.byte_size
 or object_meta->>'mimetype' is distinct from f.mime_type then raise exception 'Upload not complete or file metadata mismatch'; end if;
 update public.academy_material_files set status='ready',updated_at=now() where id=f.id returning * into f;
 insert into academy_private.audit_log(actor_id,action,target) values(auth.uid(),'material_file_ready',f.id::text);
 return to_jsonb(f);
end $function$;
-- academy_archive_material_file
CREATE OR REPLACE FUNCTION public.academy_archive_material_file(p_file_id uuid, p_archived boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.academy_material_files; c public.academy_content;
begin
 select * into f from public.academy_material_files where id=p_file_id for update;
 select * into c from public.academy_content where id=f.material_id and kind='material';
 if f.id is null or c.id is null or not academy_private.can_edit_record(c) then raise exception 'Forbidden'; end if;
 if p_archived is distinct from true then perform public.academy_finish_material_file(f.id);
 else update public.academy_material_files set status='archived',updated_at=now() where id=f.id; end if;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'material_file_archive',f.id::text,jsonb_build_object('archived',p_archived));
end $function$;
-- academy_set_priority
CREATE OR REPLACE FUNCTION public.academy_set_priority(p_content_id text, p_priority text, p_lesson_id text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.academy_content; updated_payload jsonb;
begin
 select * into c from public.academy_content where id=p_content_id for update;
 if c.id is null or c.kind not in ('course','test') or not academy_private.can_edit_record(c) then raise exception 'Forbidden'; end if;
 if p_priority not in ('start','attestation','additional') then raise exception 'Неверный приоритет.'; end if;
 if p_lesson_id is null then updated_payload=jsonb_set(c.payload,'{priority}',to_jsonb(p_priority));
 else
 if not exists(select 1 from jsonb_array_elements(c.payload->'lessons') l where l->>'id'=p_lesson_id) then raise exception 'Урок не найден.'; end if;
 updated_payload=jsonb_set(c.payload,'{lessons}',(select jsonb_agg(case when l->>'id'=p_lesson_id then jsonb_set(l,'{priority}',to_jsonb(p_priority)) else l end order by n) from jsonb_array_elements(c.payload->'lessons') with ordinality a(l,n)));
 end if;
 update public.academy_content set payload=updated_payload,updated_at=now() where id=c.id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'set_priority',c.id,jsonb_build_object('priority',p_priority,'lesson_id',p_lesson_id));
end $function$;
-- academy_course_editor
CREATE OR REPLACE FUNCTION public.academy_course_editor(p_course_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.academy_content;d academy_private.course_drafts;
begin
 select * into c from public.academy_content where id=p_course_id and kind='course';
 if c.id is null or not academy_private.can_edit_record(c) then raise exception 'Курс недоступен для редактирования.';end if;
 select * into d from academy_private.course_drafts where course_id=c.id;
 return jsonb_build_object('document',coalesce(d.document,to_jsonb(c)),'live_updated_at',c.updated_at,'draft_updated_at',d.updated_at,'has_draft',d.course_id is not null,'conflict',d.course_id is not null and d.base_updated_at is distinct from c.updated_at);
end $function$;
-- academy_reserve_course_media
CREATE OR REPLACE FUNCTION public.academy_reserve_course_media(p_course_id text, p_filename text, p_mime_type text, p_byte_size bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.academy_content;m public.academy_course_media;ext text;uid uuid:=gen_random_uuid();
begin
 select * into c from public.academy_content where id=p_course_id and kind='course' for update;
 if c.id is null or not academy_private.can_edit_record(c) then raise exception 'Нет доступа к изображениям курса.';end if;
 ext:=case p_mime_type when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' when 'image/gif' then 'gif' when 'video/mp4' then 'mp4' when 'video/webm' then 'webm' when 'application/pdf' then 'pdf' end;
 if ext is null or p_byte_size is null or p_byte_size not between 1 and 52428800 or nullif(trim(p_filename),'') is null or length(p_filename)>240 then raise exception 'Поддерживаются изображения, PDF и видео до 50 МБ.';end if;
 if (select count(*) from public.academy_course_media where course_id=c.id)>=300 then raise exception 'В курсе уже 300 вложений.';end if;
 insert into public.academy_course_media(id,course_id,storage_path,filename,mime_type,byte_size,uploaded_by) values(uid,c.id,c.id||'/'||uid||'.'||ext,p_filename,p_mime_type,p_byte_size,auth.uid()) returning * into m;return to_jsonb(m);
end $function$;
-- can_read_course_media
CREATE OR REPLACE FUNCTION academy_private.can_read_course_media(p_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.academy_course_media m join public.academy_content c on c.id=m.course_id where m.id=p_id and
 (academy_private.can_edit_record(c) or m.status='ready' and c.published and academy_private.can_read_content(c.id) and
 jsonb_path_exists(c.payload,'$.lessons[*].blocks[*] ? (@.image == $ref || @.src == $ref)',jsonb_build_object('ref','course-media:'||m.id))))
$function$;
-- academy_finish_course_media
CREATE OR REPLACE FUNCTION public.academy_finish_course_media(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m public.academy_course_media;c public.academy_content;meta jsonb;
begin
 select * into m from public.academy_course_media where id=p_id for update;select * into c from public.academy_content where id=m.course_id;
 if m.id is null or not academy_private.can_edit_record(c) then raise exception 'Нет доступа к файлу.';end if;
 select metadata into meta from storage.objects where bucket_id='academy-course-media' and name=m.storage_path;
 if meta is null or (meta->>'size')::bigint is distinct from m.byte_size or meta->>'mimetype' is distinct from m.mime_type then raise exception 'Загрузка не завершена.';end if;
 update public.academy_course_media set status='ready' where id=m.id returning * into m;return to_jsonb(m);
end $function$;
-- academy_set_course_audience
CREATE OR REPLACE FUNCTION public.academy_set_course_audience(p_content_id text, p_positions jsonb, p_levels jsonb, p_priorities jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.academy_content; allowed text[]:=array['Официант','Администратор зала','Хостес','Старший бармен','Барбэк','Бармен','Повар','Сотрудник арт','Кальянный мастер','Старший кальянный мастер','Руководитель','Управляющий','Бар-менеджер','Шеф-повар'];
begin
 select * into c from public.academy_content where id=p_content_id for update;
 if c.id is null or c.kind<>'course' or not academy_private.can_edit_record(c) then raise exception 'Недостаточно прав для настройки курса.';end if;
 if jsonb_typeof(p_positions) is distinct from 'array' or jsonb_typeof(p_levels) is distinct from 'array' or jsonb_typeof(p_priorities) is distinct from 'object' then raise exception 'Проверьте категории курса.';end if;
 if jsonb_array_length(p_positions) not between 1 and cardinality(allowed) or exists(select 1 from jsonb_array_elements_text(p_positions) x where x is null or not x=any(allowed)) or (select count(*) from jsonb_array_elements_text(p_positions))<>(select count(distinct x) from jsonb_array_elements_text(p_positions) x) then raise exception 'Выберите хотя бы одну должность без повторов.';end if;
 if jsonb_array_length(p_levels) not between 1 and 2 or exists(select 1 from jsonb_array_elements_text(p_levels) x where x is null or x not in ('trainee','certified')) then raise exception 'Выберите уровень подготовки.';end if;
 if exists(select 1 from jsonb_each_text(p_priorities) x where not p_positions ? x.key or x.value is null or x.value not in ('start','attestation','additional')) then raise exception 'Проверьте приоритеты должностей.';end if;
 update public.academy_content set payload=payload||jsonb_build_object('audiencePositions',p_positions,'audienceLevels',p_levels,'audiencePriorities',p_priorities),updated_at=now() where id=c.id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'course_audience',c.id,jsonb_build_object('positions',p_positions,'levels',p_levels,'priorities',p_priorities));
end $function$;
-- academy_announce_content
CREATE OR REPLACE FUNCTION public.academy_announce_content(p_content_ids text[], p_comment text DEFAULT ''::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor public.academy_profiles;c public.academy_content;first_c public.academy_content;p public.academy_profiles;
 ids text[];snapshot jsonb;key text;notice_title text;notice_body text;recipient_body text;notice_route text;sent integer:=0;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null or actor.role not in ('admin','manager') then raise exception 'Публиковать уведомления может только администратор.';end if;
 select array_agg(distinct x order by x) into ids from unnest(p_content_ids) x;
 if coalesce(array_length(ids,1),0) not between 1 and 30 or length(coalesce(p_comment,''))>1000 then raise exception 'Выберите от 1 до 30 позиций и комментарий до 1000 символов.';end if;
 select * into first_c from public.academy_content where id=ids[1];
 if (select count(*) from public.academy_content where id=any(ids))<>array_length(ids,1) then raise exception 'Материал недоступен.';end if;
 for c in select * from public.academy_content where id=any(ids) loop
 if not c.published or c.kind not in ('course','test','material','menu') or c.kind is distinct from first_c.kind
 or c.restaurant_id is distinct from first_c.restaurant_id or c.department is distinct from first_c.department
 or (c.kind<>'menu' and array_length(ids,1)>1)
 or (c.kind='menu' and (c.payload->>'brand' is distinct from first_c.payload->>'brand' or c.payload->>'menuSection' is distinct from first_c.payload->>'menuSection'))
 or not (actor.role='admin' or case when c.kind='menu' then academy_private.can_edit_menu_for(actor,c)
 else academy_private.can_edit_record(c) end) then raise exception 'Уведомлять можно только об опубликованных материалах своей области.';end if;
 end loop;
 select jsonb_agg(jsonb_build_object('id',d.id,'title',d.title,'payload',d.payload,'files',(select jsonb_agg(f.id order by f.id) from public.academy_material_files f where f.material_id=d.id and f.status='ready')) order by d.id) into snapshot from public.academy_content d where d.id=any(ids);
 key:='publication:'||md5(snapshot::text);
 notice_title:=case first_c.kind when 'course' then 'Курс опубликован: '||first_c.title when 'test' then 'Тест опубликован: '||first_c.title when 'material' then 'Новое в библиотеке: '||first_c.title else 'Обновление меню · '||case first_c.payload->>'brand' when 'rvb' then 'Руки Вверх Бар' else '90-е' end end;
 notice_body:=case when first_c.kind='menu' then (select string_agg(title,E'\n' order by title) from public.academy_content where id=any(ids)) else coalesce(first_c.payload->>'description','') end;
 if nullif(trim(p_comment),'') is not null then notice_body:=notice_body||E'\n'||trim(p_comment);end if;
 notice_route:=case first_c.kind when 'course' then '#/courses/'||first_c.id when 'test' then '#/tests/'||first_c.id when 'material' then '#/library/'||first_c.id else case when array_length(ids,1)=1 then '#/menu/'||first_c.id else '#/menu?brand='||(first_c.payload->>'brand')||'&section='||(first_c.payload->>'menuSection') end end;
 for p in select * from public.academy_profiles where status='active' and id<>actor.id loop
 if exists(select 1 from public.academy_content d where d.id=any(ids) and academy_private.notice_content_for(p,d)) then
 recipient_body:=notice_body;
 if first_c.kind in ('course','test') then recipient_body:=case coalesce(first_c.payload->'audiencePriorities'->>p.position,first_c.payload->>'priority',case first_c.kind when 'test' then 'attestation' else 'additional' end) when 'start' then 'Важно для начала работы' when 'attestation' then 'Аттестация' else 'Дополнительные знания' end||case when nullif(first_c.payload->>'dueAt','') is not null then E'\nСрок: '||left(first_c.payload->>'dueAt',10) else '' end||case when nullif(trim(p_comment),'') is not null then E'\n'||trim(p_comment) else '' end;end if;
 perform academy_private.emit_notice(p.id,key,'publication',notice_title,recipient_body,notice_route,'content',null,ids);sent:=sent+1;end if;end loop;
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'notification_publish',first_c.id,jsonb_build_object('ids',ids,'eligible',sent));return sent;
end $function$;
-- academy_save_course_editor
CREATE OR REPLACE FUNCTION public.academy_save_course_editor(p_document jsonb, p_expected timestamp with time zone DEFAULT NULL::timestamp with time zone, p_draft_expected timestamp with time zone DEFAULT NULL::timestamp with time zone, p_publish boolean DEFAULT false, p_notify boolean DEFAULT false, p_comment text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.academy_content;d academy_private.course_drafts;l jsonb;b jsonb;doc jsonb:=p_document;ids text[];positions text[]:=array['Официант','Администратор зала','Хостес','Старший бармен','Барбэк','Бармен','Бар-менеджер','Повар','Шеф-повар','Сотрудник арт','Кальянный мастер','Старший кальянный мастер','Руководитель','Управляющий'];
begin
 if p_publish is null or doc->>'kind' is distinct from 'course' or nullif(trim(doc->>'title'),'') is null or length(doc->>'title')>240 or octet_length(doc::text)>1048576 or nullif(doc->>'id','') is null then raise exception 'Проверьте название и размер курса.';end if;
 if not academy_private.can_edit_record(jsonb_populate_record(null::public.academy_content,doc)) then raise exception 'Курс вне вашей области доступа.';end if;
 select * into c from public.academy_content where id=doc->>'id' for update;
 if c.id is not null and (c.kind<>'course' or not academy_private.can_edit_record(c) or row(c.restaurant_id,c.department) is distinct from row(doc->>'restaurant_id',doc->>'department')) then raise exception 'Область существующего курса менять здесь нельзя.';end if;
 if c.id is not null and c.updated_at is distinct from p_expected then raise exception 'Курс изменён в другом окне. Обновите редактор; локальный черновик сохранён.';end if;
 select * into d from academy_private.course_drafts where course_id=doc->>'id' for update;
 if d.updated_at is distinct from p_draft_expected then raise exception 'Черновик изменён в другом окне. Обновите редактор.';end if;
 if jsonb_typeof(doc->'payload') is distinct from 'object' or jsonb_typeof(doc->'payload'->'lessons') is distinct from 'array' or jsonb_array_length(doc->'payload'->'lessons') not between 1 and 100 then raise exception 'В курсе должно быть от 1 до 100 занятий.';end if;
 select array_agg(x->>'id') into ids from jsonb_array_elements(doc->'payload'->'lessons') x;
 if exists(select 1 from unnest(ids) x where nullif(x,'') is null) or cardinality(ids)<>(select count(distinct x) from unnest(ids) x) then raise exception 'Занятия должны иметь уникальные идентификаторы.';end if;
 if c.id is not null and exists(select 1 from jsonb_array_elements(coalesce(c.payload->'lessons','[]')) with ordinality x(value,n) where not coalesce(x.value->>'id',(n-1)::text)=any(ids)) then raise exception 'Существующие занятия нельзя удалить: их история обучения должна сохраниться.';end if;
 if jsonb_path_exists(doc->'payload','$.**.correct') or jsonb_path_exists(doc->'payload','$.**.key_snapshot') then raise exception 'Ключи тестов не должны храниться в курсе.';end if;
 if coalesce(doc->'payload'->>'priority','additional') not in ('start','attestation','additional') then raise exception 'Проверьте приоритет курса.';end if;
 if jsonb_typeof(doc->'payload'->'audiencePositions') is distinct from 'array' or jsonb_array_length(doc->'payload'->'audiencePositions')<1 or exists(select 1 from jsonb_array_elements_text(doc->'payload'->'audiencePositions') x where not x=any(positions)) then raise exception 'Выберите должности курса.';end if;
 if jsonb_typeof(doc->'payload'->'audienceLevels') is distinct from 'array' or jsonb_array_length(doc->'payload'->'audienceLevels')<1 or exists(select 1 from jsonb_array_elements_text(doc->'payload'->'audienceLevels') x where x not in ('trainee','certified')) then raise exception 'Выберите уровни подготовки.';end if;
 for l in select value from jsonb_array_elements(doc->'payload'->'lessons') loop
 if nullif(trim(l->>'title'),'') is null then raise exception 'Назовите каждое занятие.';end if;
 if l ? 'blocks' then
 if jsonb_typeof(l->'blocks') is distinct from 'array' or jsonb_array_length(l->'blocks')>100 then raise exception 'В занятии может быть до 100 блоков.';end if;
 if (select count(distinct x->>'id') from jsonb_array_elements(l->'blocks') x)<>jsonb_array_length(l->'blocks') then raise exception 'Блоки должны иметь уникальные идентификаторы.';end if;
 for b in select value from jsonb_array_elements(l->'blocks') loop
 if b->>'type' is null or b->>'type' not in ('hero','heading','text','list','callout','table','image','link','video','pdf','divider') then raise exception 'Неизвестный тип блока.';end if;
 end loop;end if;end loop;
 if c.id is null then
 insert into public.academy_content(id,kind,title,payload,published,restaurant_id,department) values(doc->>'id','course',trim(doc->>'title'),'{}',false,doc->>'restaurant_id',doc->>'department') returning * into c;
 end if;
 if p_publish then
 doc:=doc||jsonb_build_object('published',true);perform public.academy_save_content(doc,null);
 delete from academy_private.course_drafts where course_id=c.id;
 if p_notify then perform public.academy_announce_content(array[c.id],p_comment);end if;
 else
 insert into academy_private.course_drafts(course_id,document,base_updated_at,updated_by) values(c.id,doc,c.updated_at,auth.uid())
 on conflict(course_id) do update set document=excluded.document,base_updated_at=excluded.base_updated_at,updated_at=clock_timestamp(),updated_by=excluded.updated_by;
 end if;
 insert into academy_private.audit_log(actor_id,action,target) values(auth.uid(),case when p_publish then 'course_editor_publish' else 'course_editor_draft' end,c.id);
 return public.academy_course_editor(c.id);
end $function$;
-- can_edit_menu_for
CREATE OR REPLACE FUNCTION academy_private.can_edit_menu_for(a academy_profiles, c academy_content)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select coalesce(a.status='active' and c.kind='menu' and (a.role='admin' or a.operations_director or (a.venue_director and academy_private.venue_document(a,c,true)) or
 (a.role='manager' and a.restaurant_id is not null
 and a.department=case c.payload->>'menuSection' when 'bar' then 'Бар' when 'kitchen' then 'Кухня' end
 and (c.department is null or c.department=a.department)
 and (c.restaurant_id=a.restaurant_id or
 (c.restaurant_id is null and c.department is null and c.payload->>'brand'='90' and c.payload->>'menuSection' in ('bar','kitchen')
 and a.restaurant_id in ('pushkino','khimki','mytishchi'))))),false)
$function$;
-- can_read_content
CREATE OR REPLACE FUNCTION academy_private.can_read_content(p_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.academy_content c join public.academy_profiles p on p.id=auth.uid()
 where c.id=p_id and p.status='active' and case when p.venue_director then academy_private.venue_document(p,c,false) else case when c.id='rvb-bar-handbook'
 then academy_private.can_read_bar_handbook(p,c)
 else ((c.published and (c.restaurant_id is null or c.restaurant_id=p.restaurant_id) and (c.department is null or c.department=p.department))
 or p.role='admin' or p.operations_director or (p.role='manager' and c.restaurant_id=p.restaurant_id and c.department=p.department)
 or (c.kind='menu' and academy_private.can_edit_menu_for(p,c))) end end)
$function$;
-- can_read_bar_handbook
CREATE OR REPLACE FUNCTION academy_private.can_read_bar_handbook(p academy_profiles, c academy_content)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select coalesce(p.status='active' and (not p.venue_director or academy_private.venue_document(p,c,false)) and (p.role='admin' or p.operations_director or
 ((c.published or p.role='manager' and p.restaurant_id='minsk' and p.department='Бар') and
 (p.department='Руководитель' or p.restaurant_id='minsk' and p.department='Бар'))),false)
$function$;
-- academy_ranking
CREATE OR REPLACE FUNCTION public.academy_ranking()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with actor as (
 select * from public.academy_profiles where id=auth.uid() and status='active'
 ), visible as (
 select p.* from public.academy_profiles p cross join actor a where p.status='active' and
 (a.role='admin' or a.operations_director or academy_private.venue_scope(a,p.restaurant_id) or (a.role='manager' and p.restaurant_id=a.restaurant_id and p.department=a.department)
 or (a.role='employee' and p.restaurant_id=a.restaurant_id))
 ), best as (
 select a.user_id,a.test_id,max(a.score::numeric/nullif(a.total,0)) filter(where not a.needs_review) as fraction,
 bool_or(a.passed) as passed from public.academy_attempts a join visible p on p.id=a.user_id
 where a.submitted_at is not null and (coalesce((a.snapshot->>'timeLimitSeconds')::integer,0)=0
 or a.submitted_at<=a.started_at+make_interval(secs=>(a.snapshot->>'timeLimitSeconds')::integer+10))
 group by a.user_id,a.test_id
 ), scores as (
 select user_id,round(avg(fraction)*100,1) as average_score,count(*) as tests_attempted,count(*) filter(where passed) as tests_passed
 from best group by user_id
 ), lessons as (
 select p.user_id,count(*) as lessons_completed from public.academy_progress p join visible v on v.id=p.user_id group by p.user_id
 ), marks as (
 select m.user_id,count(*) filter(where m.status='learned') as menu_learned,count(*) filter(where m.status='repeat') as menu_repeat
 from public.academy_menu_marks m join visible v on v.id=m.user_id group by m.user_id
 )
 select coalesce(jsonb_agg(jsonb_build_object('user_id',p.id,'full_name',p.full_name,'restaurant_id',p.restaurant_id,
 'department',p.department,'position',p.position,'average_score',s.average_score,
 'tests_attempted',coalesce(s.tests_attempted,0),'tests_passed',coalesce(s.tests_passed,0),
 'lessons_completed',coalesce(l.lessons_completed,0),'menu_learned',coalesce(m.menu_learned,0),'menu_repeat',coalesce(m.menu_repeat,0))
 order by s.average_score desc nulls last,coalesce(s.tests_passed,0) desc,p.full_name),'[]'::jsonb)
 from visible p left join scores s on s.user_id=p.id left join lessons l on l.user_id=p.id left join marks m on m.user_id=p.id
$function$;
-- academy_oral_data
CREATE OR REPLACE FUNCTION public.academy_oral_data(p_all boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor public.academy_profiles; viewer boolean; result jsonb;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null then raise exception 'Доступ закрыт.';end if;
 viewer:=academy_private.can_view_oral();
 select jsonb_build_object(
 'viewer',viewer,
 'members',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'restaurant_id',p.restaurant_id,'department',p.department,'position',p.position,'training_level',p.training_level,'general',academy_private.general_training_status(p.id,p.restaurant_id,p.department,p.position),'can_grade_kitchen',academy_private.can_grade_oral(p.restaurant_id,'kitchen') and p.id<>actor.id,'can_grade_bar',academy_private.can_grade_oral(p.restaurant_id,'bar') and p.id<>actor.id) order by p.full_name) from public.academy_profiles p where p.status='active' and (p.id=actor.id or viewer and p_all and (actor.role='admin' or actor.operations_director or academy_private.venue_scope(actor,p.restaurant_id) or p.restaurant_id=actor.restaurant_id))),'[]'::jsonb),
 'assessments',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc,a.id desc) from public.academy_oral_assessments a where a.employee_id=actor.id or viewer and p_all and (actor.role='admin' or actor.operations_director or (academy_private.venue_scope(actor,a.restaurant_id) and exists(select 1 from public.academy_profiles m where m.id=a.employee_id and academy_private.venue_scope(actor,m.restaurant_id))) or a.restaurant_id=actor.restaurant_id and exists(select 1 from public.academy_profiles p where p.id=a.employee_id and p.restaurant_id=actor.restaurant_id))),'[]'::jsonb)) into result;
 return result;
end $function$;
-- academy_assign_work
CREATE OR REPLACE FUNCTION public.academy_assign_work(p_user_id uuid, p_restaurant_id text, p_department text, p_position text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor public.academy_profiles; member public.academy_profiles;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 select * into member from public.academy_profiles where id=p_user_id for update;
 if actor.id is null or member.id is null or not academy_private.can_manage(p_user_id) or (actor.role<>'admin' and not actor.operations_director and not actor.venue_director and (member.id=actor.id or member.role<>'employee')) then raise exception 'Можно менять только рабочие данные сотрудников своей команды.'; end if;
 if actor.venue_director and not academy_private.venue_scope(actor,p_restaurant_id) then raise exception 'Перевод за пределы области управляющего недоступен.';end if;
 if member.venue_director and row(member.restaurant_id,member.department,member.position) is distinct from row(p_restaurant_id,p_department,p_position) then raise exception 'Сначала снимите допуск управляющего перед изменением его области.';end if;
 if not academy_private.valid_work(p_restaurant_id,p_department,p_position) then raise exception 'Проверьте заведение, подразделение и должность.'; end if;
 update public.academy_profiles set restaurant_id=p_restaurant_id,department=p_department,position=p_position,updated_at=now() where id=member.id;
 update public.academy_work_changes set status='cancelled',reviewed_at=now(),reviewed_by=actor.id where user_id=member.id and status='pending';
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'assign_work',member.id::text,jsonb_build_object('from',jsonb_build_object('restaurant',member.restaurant_id,'department',member.department,'position',member.position),'to',jsonb_build_object('restaurant',p_restaurant_id,'department',p_department,'position',p_position)));
end $function$;
-- academy_manage_member
CREATE OR REPLACE FUNCTION public.academy_manage_member(p_user_id uuid, p_status text, p_role text DEFAULT 'employee'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor public.academy_profiles; member public.academy_profiles;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 select * into member from public.academy_profiles where id=p_user_id for update;
 if actor.id is null or member.id is null or not academy_private.can_manage(p_user_id) or p_user_id=auth.uid() then raise exception 'Forbidden';end if;
 if p_status is null or p_status not in ('pending','active','suspended') or p_role is null or p_role not in ('employee','manager','admin') then raise exception 'Invalid status or role';end if;
 if actor.role<>'admin' and (p_role='admin' or not actor.operations_director and (not actor.venue_director and p_role<>'employee' or actor.venue_director and p_role is distinct from member.role)) then raise exception 'Назначать владельцев может только владелец академии.';end if;
 update public.academy_profiles set status=p_status,role=p_role,operations_director=case when p_role='manager' then operations_director else false end,venue_director=case when p_role='manager' then venue_director else false end,updated_at=now() where id=p_user_id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'member',p_user_id::text,jsonb_build_object('status',p_status,'role',p_role));
end $function$;
-- academy_work_change_list
CREATE OR REPLACE FUNCTION public.academy_work_change_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor public.academy_profiles; result jsonb;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null then raise exception 'Доступ закрыт.'; end if;
 select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('can_review',r.user_id<>actor.id and ((actor.role='admin' or actor.operations_director and academy_private.can_manage(r.user_id) or (actor.venue_director and academy_private.venue_scope(actor,r.restaurant_id) and exists(select 1 from public.academy_profiles m where m.id=r.user_id and academy_private.venue_scope(actor,m.restaurant_id) and m.role<>'admin' and not m.operations_director and not m.venue_director))) or (actor.role='manager' and not actor.venue_director and r.original_role='employee' and r.restaurant_id=actor.restaurant_id and r.department=actor.department))) order by r.created_at desc),'[]'::jsonb) into result
 from public.academy_work_changes r where r.user_id=actor.id or (actor.role='admin' or actor.operations_director and academy_private.can_manage(r.user_id) or (actor.venue_director and academy_private.venue_scope(actor,r.restaurant_id) and exists(select 1 from public.academy_profiles m where m.id=r.user_id and academy_private.venue_scope(actor,m.restaurant_id) and m.role<>'admin' and not m.operations_director and not m.venue_director))) or
 (actor.role='manager' and not actor.venue_director and r.original_role='employee' and r.restaurant_id=actor.restaurant_id and r.department=actor.department);
 return result;
end $function$;
-- academy_review_work_change
CREATE OR REPLACE FUNCTION public.academy_review_work_change(p_request_id uuid, p_approve boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor public.academy_profiles; member public.academy_profiles; request public.academy_work_changes; target_user uuid;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null or actor.role not in ('manager','admin') or p_approve is null then raise exception 'Доступ закрыт.'; end if;
 select user_id into target_user from public.academy_work_changes where id=p_request_id;
 select * into member from public.academy_profiles where id=target_user for update;
 select * into request from public.academy_work_changes where id=p_request_id for update;
 if request.id is null or request.status<>'pending' then raise exception 'Заявка уже обработана или недоступна.'; end if;
 if member.id=actor.id or not(actor.role='admin' or actor.operations_director and academy_private.can_manage(member.id) or (actor.venue_director and academy_private.can_manage(member.id) and academy_private.venue_scope(actor,request.restaurant_id)) or (actor.role='manager' and not actor.venue_director and member.role='employee' and request.original_role='employee' and actor.restaurant_id=request.restaurant_id and actor.department=request.department)) then raise exception 'Подтверждение доступно администратору принимающей команды или владельцу.'; end if;
 if member.status<>'active' or member.role is distinct from request.original_role or member.restaurant_id is distinct from request.from_restaurant or member.department is distinct from request.from_department or member.position is distinct from request.from_position then raise exception 'Рабочие данные уже изменились. Попросите сотрудника отменить заявку и отправить новую.'; end if;
 if p_approve then
 update public.academy_profiles set restaurant_id=request.restaurant_id,department=request.department,position=request.position,updated_at=now() where id=member.id;
 end if;
 update public.academy_work_changes set status=case when p_approve then 'approved' else 'rejected' end,reviewed_at=now(),reviewed_by=actor.id where id=request.id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'review_work_change',request.id::text,jsonb_build_object('approved',p_approve,'user_id',member.id,'from',jsonb_build_object('restaurant',member.restaurant_id,'department',member.department,'position',member.position),'to',jsonb_build_object('restaurant',request.restaurant_id,'department',request.department,'position',request.position)));
end $function$;
-- academy_request_work_change
CREATE OR REPLACE FUNCTION public.academy_request_work_change(p_restaurant_id text, p_department text, p_position text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor public.academy_profiles; request_id uuid;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active' for update;
 if actor.venue_director then raise exception 'Сначала владелец или операционный директор должен снять допуск управляющего.';end if;
 if actor.id is null then raise exception 'Доступ закрыт.'; end if;
 if not academy_private.valid_work(p_restaurant_id,p_department,p_position) then raise exception 'Проверьте заведение, подразделение и должность.'; end if;
 if actor.restaurant_id is not distinct from p_restaurant_id and actor.department is not distinct from p_department and actor.position is not distinct from p_position then raise exception 'Выберите новые рабочие данные.'; end if;
 if exists(select 1 from public.academy_work_changes where user_id=actor.id and status='pending') then raise exception 'Сначала дождитесь решения или отмените текущую заявку.'; end if;
 insert into public.academy_work_changes(user_id,full_name,original_role,from_restaurant,from_department,from_position,restaurant_id,department,position)
 values(actor.id,actor.full_name,actor.role,actor.restaurant_id,actor.department,actor.position,p_restaurant_id,p_department,p_position) returning id into request_id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'request_work_change',request_id::text,jsonb_build_object('user_id',actor.id,'restaurant',p_restaurant_id,'department',p_department,'position',p_position));
 return request_id;
end $function$;
-- notice_content_for
CREATE OR REPLACE FUNCTION academy_private.notice_content_for(p academy_profiles, c academy_content)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select case when p.venue_director then c.published and academy_private.venue_document(p,c,false) when academy_private.is_operations_director(p.id) then c.published else coalesce(p.status='active' and c.published
 and (c.restaurant_id is null or c.restaurant_id=p.restaurant_id)
 and (c.department is null or c.department=p.department)
 and (c.kind<>'menu' or c.payload->>'brand'=case when p.restaurant_id='minsk' then 'rvb' when p.restaurant_id in ('pushkino','khimki','mytishchi') then '90' end)
 and (c.kind<>'material' or coalesce(c.payload->>'brand','common') in ('common',case when p.restaurant_id='minsk' then 'rvb' else '90' end))
 and (not c.payload ? 'audiencePositions' or c.payload->'audiencePositions' ? p.position)
 and (not c.payload ? 'audienceLevels' or p.department='Руководитель' or c.payload->'audienceLevels' ? p.training_level)
 and (c.course_id is null or exists(select 1 from public.academy_content parent where parent.id=c.course_id and parent.published
 and (parent.restaurant_id is null or parent.restaurant_id=p.restaurant_id) and (parent.department is null or parent.department=p.department)
 and (not parent.payload ? 'audiencePositions' or parent.payload->'audiencePositions' ? p.position))),false) end
$function$;
-- notice_visible
CREATE OR REPLACE FUNCTION academy_private.notice_visible(n academy_private.notifications, p academy_profiles)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select n.user_id=p.id and case n.scope when 'own' then true when 'content' then
 exists(select 1 from public.academy_content c where c.id=any(n.content_ids) and academy_private.notice_content_for(p,c))
 when 'team' then p.status='active' and exists(select 1 from public.academy_profiles m where m.id=n.subject_id and
 (p.role='admin' or p.operations_director or (p.venue_director and academy_private.venue_scope(p,m.restaurant_id) and m.role<>'admin' and not m.operations_director and not m.venue_director) or p.role='manager' and m.role='employee' and p.restaurant_id=m.restaurant_id and p.department=m.department))
 when 'work' then p.status='active' and exists(select 1 from public.academy_work_changes r where r.id::text=split_part(n.event_key,':',2) and r.user_id<>p.id and
 (p.role='admin' or p.operations_director or (p.venue_director and academy_private.venue_scope(p,r.restaurant_id) and academy_private.venue_scope(p,r.from_restaurant)) or p.role='manager' and not p.venue_director and r.original_role='employee' and p.restaurant_id=r.restaurant_id and p.department=r.department))
 when 'oral' then p.status='active' and exists(select 1 from public.academy_profiles m where m.id=n.subject_id and
 (p.role='admin' or p.operations_director or academy_private.venue_scope(p,m.restaurant_id) or p.role='manager' and p.restaurant_id=m.restaurant_id and ((p.department='Кухня' and p.position='Шеф-повар') or (p.department='Бар' and p.position='Бар-менеджер'))))
 else false end
$function$;
-- notify_team
CREATE OR REPLACE FUNCTION academy_private.notify_team(p_subject uuid, p_key text, p_title text, p_body text, p_route text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.academy_profiles; m public.academy_profiles;
begin
 select * into m from public.academy_profiles where id=p_subject;
 for p in select receiver.* from public.academy_profiles receiver where status='active' and id<>p_subject and
 (role='admin' or (operations_director and m.role<>'admin' and not m.operations_director) or (venue_director and academy_private.venue_scope(receiver,m.restaurant_id) and m.role<>'admin' and not m.operations_director and not m.venue_director) or role='manager' and m.role='employee' and restaurant_id=m.restaurant_id and department=m.department) loop
 perform academy_private.emit_notice(p.id,p_key,'team',p_title,p_body,p_route,'team',p_subject);end loop;
end $function$;
-- refresh_notices
CREATE OR REPLACE FUNCTION academy_private.refresh_notices(p academy_profiles)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m public.academy_profiles; g jsonb; c jsonb;due timestamptz;names text:='';overdue integer:=0;v_division text;recipient public.academy_profiles;attempt record;request public.academy_work_changes;
begin
 if p.status<>'active' then return;end if;
 -- Each inbox refresh does this at most once per hour. No client-supplied recipients.
 insert into academy_private.notification_checks(user_id,checked_at) values(p.id,clock_timestamp()) on conflict(user_id) do update set checked_at=excluded.checked_at where academy_private.notification_checks.checked_at<now()-interval '1 hour';
 if not found then return;end if;
 g:=academy_private.general_training_status(p.id,p.restaurant_id,p.department,p.position);
 for c in select value from jsonb_array_elements(g->'courses') where not (value->>'complete')::boolean union all select value from jsonb_array_elements(g->'tests') where not (value->>'passed')::boolean loop
 select academy_private.notice_due(payload->>'dueAt') into due from public.academy_content where id=c->>'id';
 if due<=now()+interval '3 days' then names:=names||case when names='' then '' else E'\n' end||(c->>'title');end if;end loop;
 if names<>'' and not exists(select 1 from academy_private.notifications where user_id=p.id and category='reminder' and created_at>now()-interval '3 days') then
 perform academy_private.emit_notice(p.id,'reminder:'||floor(extract(epoch from now()))::text,'reminder','Обязательное обучение ждёт завершения',names,'#/courses');end if;
 if p.role in ('admin','manager') then
 for m in select * from public.academy_profiles where id<>p.id and (p.role='admin' or (p.venue_director and academy_private.venue_scope(p,restaurant_id) and role<>'admin' and not operations_director and not venue_director) or role='employee' and restaurant_id=p.restaurant_id and department=p.department) loop
 if m.status='pending' then perform academy_private.emit_notice(p.id,'enrollment:'||m.id,'team','Новая заявка сотрудника',m.full_name,'#/manager/members/'||m.id||'/profile','team',m.id);end if;
 if m.status='active' then
 for attempt in select a.id,t.title from public.academy_attempts a join public.academy_content t on t.id=a.test_id where a.user_id=m.id and a.needs_review and a.submitted_at is not null loop
 perform academy_private.emit_notice(p.id,'review:'||attempt.id,'team','Письменный тест ждёт проверки',m.full_name||' · '||attempt.title,'#/manager','team',m.id);end loop;
 g:=academy_private.general_training_status(m.id,m.restaurant_id,m.department,m.position);
 for c in select value from jsonb_array_elements(g->'courses') where not (value->>'complete')::boolean union all select value from jsonb_array_elements(g->'tests') where not (value->>'passed')::boolean loop
 select academy_private.notice_due(payload->>'dueAt') into due from public.academy_content where id=c->>'id';if due<now() then overdue:=overdue+1;end if;end loop;
 end if;end loop;
 if overdue>0 then perform academy_private.emit_notice(p.id,'overdue:'||(now() at time zone 'Europe/Minsk')::date::text,'digest','Сводка просроченного обучения','Незавершённых обязательных курсов и тестов со сроком: '||overdue||'. Откройте прогресс команды.','#/manager');end if;
 for request in select * from public.academy_work_changes where status='pending' and user_id<>p.id and (p.role='admin' or (p.venue_director and academy_private.venue_scope(p,restaurant_id) and academy_private.venue_scope(p,from_restaurant)) or p.role='manager' and not p.venue_director and original_role='employee' and restaurant_id=p.restaurant_id and department=p.department) loop
 perform academy_private.emit_notice(p.id,'work-review:'||request.id,'work_review','Заявка на смену рабочих данных',request.full_name||' · '||request.position,'#/manager','work',request.user_id);end loop;
 end if;
 -- Readiness is based on the current mandatory curriculum, never on menu marks.
 for m in select * from public.academy_profiles where status='active' and position='Официант' and restaurant_id is not null and
 (p.id=id or p.role='admin' or p.role='manager' and restaurant_id=p.restaurant_id) loop
 g:=academy_private.general_training_status(m.id,m.restaurant_id,m.department,m.position);
 if (g->>'passed')::boolean then
 foreach v_division in array array['kitchen','bar'] loop
 if not coalesce((select a.passed from public.academy_oral_assessments a where a.employee_id=m.id and a.restaurant_id=m.restaurant_id and a.division=v_division order by a.created_at desc,a.id desc limit 1),false) then
 for recipient in select * from public.academy_profiles where status='active' and id<>m.id and
 (role='admin' or role='manager' and restaurant_id=m.restaurant_id and ((v_division='kitchen' and department='Кухня' and position='Шеф-повар') or (v_division='bar' and department='Бар' and position='Бар-менеджер'))) loop
 perform academy_private.emit_notice(recipient.id,'oral-ready:'||m.id||':'||m.restaurant_id||':'||v_division,'attestation','Сотрудник готов к аттестации · '||case v_division when 'bar' then 'Бар' else 'Кухня' end,m.full_name||' завершил обязательное обучение.','#/attestation/members/'||m.id||'?division='||v_division,'oral',m.id);end loop;end if;end loop;end if;end loop;
end $function$;
alter policy course_media_objects_insert on storage.objects with check (((bucket_id = 'academy-course-media'::text) AND (EXISTS ( SELECT 1
 FROM (academy_course_media m
 JOIN academy_content c ON ((c.id = m.course_id)))
 WHERE ((m.storage_path = objects.name) AND (m.status = 'pending'::text) AND (m.uploaded_by = auth.uid()) AND academy_private.can_edit_record(c))))));
alter policy academy_materials_insert on storage.objects with check (((bucket_id = 'academy-materials'::text) AND (EXISTS ( SELECT 1
 FROM (academy_material_files f
 JOIN academy_content c ON ((c.id = f.material_id)))
 WHERE ((f.storage_path = objects.name) AND (f.status = 'pending'::text) AND (f.uploaded_by = auth.uid()) AND (c.kind = 'material'::text) AND academy_private.can_edit_record(c))))));
commit;
