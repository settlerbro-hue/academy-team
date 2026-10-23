begin;
create table academy_private.course_drafts(course_id text primary key references public.academy_content(id),document jsonb not null,base_updated_at timestamptz not null,updated_at timestamptz not null default clock_timestamp(),updated_by uuid not null);
revoke all on academy_private.course_drafts from public,anon,authenticated;
create function public.academy_course_editor(p_course_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.academy_content;d academy_private.course_drafts;
begin
 select * into c from public.academy_content where id=p_course_id and kind='course';
 if c.id is null or not academy_private.can_edit(c.restaurant_id,c.department) then raise exception 'Курс недоступен для редактирования.';end if;
 select * into d from academy_private.course_drafts where course_id=c.id;
 return jsonb_build_object('document',coalesce(d.document,to_jsonb(c)),'live_updated_at',c.updated_at,'draft_updated_at',d.updated_at,'has_draft',d.course_id is not null,'conflict',d.course_id is not null and d.base_updated_at is distinct from c.updated_at);
end $$;
create function public.academy_save_course_editor(p_document jsonb,p_expected timestamptz default null,p_draft_expected timestamptz default null,p_publish boolean default false,p_notify boolean default false,p_comment text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.academy_content;d academy_private.course_drafts;l jsonb;b jsonb;doc jsonb:=p_document;ids text[];positions text[]:=array['Официант','Администратор','Хостес','Старший бармен','Барбэк','Бармен','Бар-менеджер','Сотрудник кухни','Шеф-повар','Сотрудник арт','Сотрудник кальянного подразделения','Руководитель','Управляющий'];
begin
 if p_publish is null or doc->>'kind' is distinct from 'course' or nullif(trim(doc->>'title'),'') is null or length(doc->>'title')>240 or octet_length(doc::text)>1048576 or nullif(doc->>'id','') is null then raise exception 'Проверьте название и размер курса.';end if;
 if not academy_private.can_edit(doc->>'restaurant_id',doc->>'department') then raise exception 'Курс вне вашей области доступа.';end if;
 select * into c from public.academy_content where id=doc->>'id' for update;
 if c.id is not null and (c.kind<>'course' or not academy_private.can_edit(c.restaurant_id,c.department) or row(c.restaurant_id,c.department) is distinct from row(doc->>'restaurant_id',doc->>'department')) then raise exception 'Область существующего курса менять здесь нельзя.';end if;
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
end $$;

create table public.academy_course_media(id uuid primary key default gen_random_uuid(),course_id text not null references public.academy_content(id),storage_path text not null unique,filename text not null,mime_type text not null,byte_size bigint not null check(byte_size between 1 and 52428800),status text not null default 'pending' check(status in ('pending','ready')),created_at timestamptz not null default now(),uploaded_by uuid not null);
alter table public.academy_course_media enable row level security;
revoke all on public.academy_course_media from public,anon,authenticated;grant select on public.academy_course_media to authenticated;
create function academy_private.can_read_course_media(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_course_media m join public.academy_content c on c.id=m.course_id where m.id=p_id and
 (academy_private.can_edit(c.restaurant_id,c.department) or m.status='ready' and c.published and academy_private.can_read_content(c.id) and
 jsonb_path_exists(c.payload,'$.lessons[*].blocks[*] ? (@.image == $ref || @.src == $ref)',jsonb_build_object('ref','course-media:'||m.id))))
$$;
create policy course_media_read on public.academy_course_media for select to authenticated using(academy_private.can_read_course_media(id));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('academy-course-media','academy-course-media',false,52428800,array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','application/pdf']);
create policy course_media_objects_read on storage.objects for select to authenticated using(bucket_id='academy-course-media' and exists(select 1 from public.academy_course_media m where m.storage_path=name and academy_private.can_read_course_media(m.id)));
create policy course_media_objects_insert on storage.objects for insert to authenticated with check(bucket_id='academy-course-media' and exists(select 1 from public.academy_course_media m join public.academy_content c on c.id=m.course_id where m.storage_path=name and m.status='pending' and m.uploaded_by=auth.uid() and academy_private.can_edit(c.restaurant_id,c.department)));
create function public.academy_reserve_course_media(p_course_id text,p_filename text,p_mime_type text,p_byte_size bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.academy_content;m public.academy_course_media;ext text;uid uuid:=gen_random_uuid();
begin
 select * into c from public.academy_content where id=p_course_id and kind='course' for update;
 if c.id is null or not academy_private.can_edit(c.restaurant_id,c.department) then raise exception 'Нет доступа к изображениям курса.';end if;
 ext:=case p_mime_type when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' when 'image/gif' then 'gif' when 'video/mp4' then 'mp4' when 'video/webm' then 'webm' when 'application/pdf' then 'pdf' end;
 if ext is null or p_byte_size is null or p_byte_size not between 1 and 52428800 or nullif(trim(p_filename),'') is null or length(p_filename)>240 then raise exception 'Поддерживаются изображения, PDF и видео до 50 МБ.';end if;
 if (select count(*) from public.academy_course_media where course_id=c.id)>=300 then raise exception 'В курсе уже 300 вложений.';end if;
 insert into public.academy_course_media(id,course_id,storage_path,filename,mime_type,byte_size,uploaded_by) values(uid,c.id,c.id||'/'||uid||'.'||ext,p_filename,p_mime_type,p_byte_size,auth.uid()) returning * into m;return to_jsonb(m);
end $$;
create function public.academy_finish_course_media(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.academy_course_media;c public.academy_content;meta jsonb;
begin
 select * into m from public.academy_course_media where id=p_id for update;select * into c from public.academy_content where id=m.course_id;
 if m.id is null or not academy_private.can_edit(c.restaurant_id,c.department) then raise exception 'Нет доступа к файлу.';end if;
 select metadata into meta from storage.objects where bucket_id='academy-course-media' and name=m.storage_path;
 if meta is null or (meta->>'size')::bigint is distinct from m.byte_size or meta->>'mimetype' is distinct from m.mime_type then raise exception 'Загрузка не завершена.';end if;
 update public.academy_course_media set status='ready' where id=m.id returning * into m;return to_jsonb(m);
end $$;
revoke all on function public.academy_course_editor(text),public.academy_save_course_editor(jsonb,timestamptz,timestamptz,boolean,boolean,text),public.academy_reserve_course_media(text,text,text,bigint),public.academy_finish_course_media(uuid) from public,anon;
grant execute on function public.academy_course_editor(text),public.academy_save_course_editor(jsonb,timestamptz,timestamptz,boolean,boolean,text),public.academy_reserve_course_media(text,text,text,bigint),public.academy_finish_course_media(uuid) to authenticated;
revoke all on function academy_private.can_read_course_media(uuid) from public,anon;grant execute on function academy_private.can_read_course_media(uuid) to authenticated;
commit;
