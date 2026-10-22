begin;
create table if not exists public.academy_material_files (
 id uuid primary key default gen_random_uuid(),
 material_id text not null references public.academy_content(id) on delete cascade,
 storage_path text not null unique,
 filename text not null, mime_type text not null, byte_size bigint not null,
 status text not null default 'pending' check(status in ('pending','ready','archived')),
 uploaded_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(byte_size>0 and byte_size<=52428800),
 check(mime_type in ('application/pdf','image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm'))
);
create index if not exists academy_material_files_material_idx on public.academy_material_files(material_id);
alter table public.academy_material_files enable row level security;
revoke all on public.academy_material_files from public,anon,authenticated;
grant select on public.academy_material_files to authenticated;
create or replace function academy_private.can_read_material_file(p_material text,p_status text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_content c where c.id=p_material and c.kind='material'
 and (academy_private.can_edit(c.restaurant_id,c.department)
 or (p_status='ready' and c.published and academy_private.can_read_content(c.id))))
$$;
revoke all on function academy_private.can_read_material_file(text,text) from public,anon;
grant execute on function academy_private.can_read_material_file(text,text) to authenticated;
drop policy if exists material_files_read on public.academy_material_files;
create policy material_files_read on public.academy_material_files for select to authenticated
using(academy_private.can_read_material_file(material_id,status));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('academy-materials','academy-materials',false,52428800,
array['application/pdf','image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists academy_materials_read on storage.objects;
create policy academy_materials_read on storage.objects for select to authenticated using(
 bucket_id='academy-materials' and exists(select 1 from public.academy_material_files f
 where f.storage_path=name and academy_private.can_read_material_file(f.material_id,f.status))
);
drop policy if exists academy_materials_insert on storage.objects;
create policy academy_materials_insert on storage.objects for insert to authenticated with check(
 bucket_id='academy-materials' and exists(select 1 from public.academy_material_files f
 join public.academy_content c on c.id=f.material_id where f.storage_path=name and f.status='pending'
 and f.uploaded_by=auth.uid() and c.kind='material' and academy_private.can_edit(c.restaurant_id,c.department))
);
-- No UPDATE or DELETE policies: uploaded bytes are immutable, removal is reversible metadata archiving.
create or replace function public.academy_reserve_material_file(p_material_id text,p_filename text,p_mime_type text,p_byte_size bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.academy_content; f public.academy_material_files; ext text; file_id uuid:=gen_random_uuid();
begin
 select * into c from public.academy_content where id=p_material_id and kind='material' for update;
 if c.id is null or not academy_private.can_edit(c.restaurant_id,c.department) then raise exception 'Forbidden'; end if;
 ext:=case p_mime_type when 'application/pdf' then 'pdf' when 'image/jpeg' then 'jpg' when 'image/png' then 'png'
 when 'image/webp' then 'webp' when 'image/gif' then 'gif' when 'video/mp4' then 'mp4' when 'video/webm' then 'webm' end;
 if ext is null or p_byte_size is null or p_byte_size<=0 or p_byte_size>52428800 then raise exception 'Unsupported file or size limit'; end if;
 if p_filename is null or length(trim(p_filename))=0 or length(p_filename)>240 then raise exception 'Invalid filename'; end if;
 if (select count(*) from public.academy_material_files where material_id=c.id and status<>'archived')>=10 then raise exception 'Maximum 10 files per material'; end if;
 insert into public.academy_material_files(id,material_id,storage_path,filename,mime_type,byte_size,uploaded_by)
 values(file_id,c.id,c.id||'/'||file_id::text||'.'||ext,left(regexp_replace(p_filename,'[[:cntrl:]]','','g'),200),p_mime_type,p_byte_size,auth.uid()) returning * into f;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'material_file_reserve',f.id::text,jsonb_build_object('material_id',c.id));
 return to_jsonb(f);
end $$;
create or replace function public.academy_finish_material_file(p_file_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare f public.academy_material_files; c public.academy_content; object_meta jsonb;
begin
 select * into f from public.academy_material_files where id=p_file_id for update;
 select * into c from public.academy_content where id=f.material_id and kind='material';
 if f.id is null or c.id is null or not academy_private.can_edit(c.restaurant_id,c.department) then raise exception 'Forbidden'; end if;
 select metadata into object_meta from storage.objects where bucket_id='academy-materials' and name=f.storage_path;
 if object_meta is null or (object_meta->>'size')::bigint is distinct from f.byte_size
 or object_meta->>'mimetype' is distinct from f.mime_type then raise exception 'Upload not complete or file metadata mismatch'; end if;
 update public.academy_material_files set status='ready',updated_at=now() where id=f.id returning * into f;
 insert into academy_private.audit_log(actor_id,action,target) values(auth.uid(),'material_file_ready',f.id::text);
 return to_jsonb(f);
end $$;
create or replace function public.academy_archive_material_file(p_file_id uuid,p_archived boolean default true)
returns void language plpgsql security definer set search_path='' as $$
declare f public.academy_material_files; c public.academy_content;
begin
 select * into f from public.academy_material_files where id=p_file_id for update;
 select * into c from public.academy_content where id=f.material_id and kind='material';
 if f.id is null or c.id is null or not academy_private.can_edit(c.restaurant_id,c.department) then raise exception 'Forbidden'; end if;
 if p_archived is distinct from true then perform public.academy_finish_material_file(f.id);
 else update public.academy_material_files set status='archived',updated_at=now() where id=f.id; end if;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'material_file_archive',f.id::text,jsonb_build_object('archived',p_archived));
end $$;
revoke all on function public.academy_reserve_material_file(text,text,text,bigint),public.academy_finish_material_file(uuid),public.academy_archive_material_file(uuid,boolean) from public,anon;
grant execute on function public.academy_reserve_material_file(text,text,text,bigint),public.academy_finish_material_file(uuid),public.academy_archive_material_file(uuid,boolean) to authenticated;
commit;
