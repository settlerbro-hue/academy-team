-- Requires migration 004 and the approved real bar manager. No persistent test records.
begin;
insert into auth.users(id,email) values
('00000000-0000-4000-8000-000000000061','qa-file-own@example.invalid'),
('00000000-0000-4000-8000-000000000062','qa-file-hall@example.invalid'),
('00000000-0000-4000-8000-000000000063','qa-file-khimki@example.invalid');
insert into public.academy_profiles(id,full_name,restaurant_id,department,status) values
('00000000-0000-4000-8000-000000000061','QA file own','minsk','Бар','active'),
('00000000-0000-4000-8000-000000000062','QA file hall','minsk','Зал','active'),
('00000000-0000-4000-8000-000000000063','QA file Khimki','khimki','Бар','active');
insert into public.academy_content(id,kind,title,restaurant_id,department,payload) values
('qa-file-material','material','QA files','minsk','Бар','{}'),
('qa-file-foreign','material','QA foreign','khimki','Бар','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
do $$ declare f jsonb; n integer; begin
 f:=public.academy_reserve_material_file('qa-file-material','test.pdf','application/pdf',64);
 perform set_config('academy.qa_file_id',f->>'id',true);perform set_config('academy.qa_file_path',f->>'storage_path',true);
 begin perform public.academy_reserve_material_file('qa-file-foreign','test.pdf','application/pdf',64);raise exception 'FAIL foreign upload reservation';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.academy_reserve_material_file('qa-file-material','bad.html','text/html',64);raise exception 'FAIL executable type allowed';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.academy_reserve_material_file('qa-file-material','big.mp4','video/mp4',52428801);raise exception 'FAIL oversized upload';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.academy_finish_material_file((f->>'id')::uuid);raise exception 'FAIL missing object finalized';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 -- Synthetic object metadata exists only inside this transaction, no object bytes are uploaded.
 insert into storage.objects(bucket_id,name,metadata) values('academy-materials',f->>'storage_path','{"size":64,"mimetype":"application/pdf"}');
 begin insert into storage.objects(bucket_id,name,metadata) values('academy-materials','forged/path.pdf','{"size":64,"mimetype":"application/pdf"}');raise exception 'FAIL arbitrary object upload';exception when insufficient_privilege then null;end;
 update storage.objects set metadata='{"size":99,"mimetype":"application/pdf"}' where bucket_id='academy-materials' and name=f->>'storage_path';get diagnostics n=row_count;
 if n<>0 then raise exception 'FAIL uploaded bytes mutable';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000061',true);
do $$ begin
 if exists(select 1 from public.academy_material_files where material_id='qa-file-material') then raise exception 'FAIL pending metadata visible to employee';end if;
 if exists(select 1 from storage.objects where bucket_id='academy-materials' and name=current_setting('academy.qa_file_path')) then raise exception 'FAIL pending object visible to employee';end if;
 begin perform public.academy_reserve_material_file('qa-file-material','test.pdf','application/pdf',64);raise exception 'FAIL employee can upload';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
select public.academy_finish_material_file(current_setting('academy.qa_file_id')::uuid);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000061',true);
do $$ begin
 if not exists(select 1 from public.academy_material_files where material_id='qa-file-material' and status='ready') then raise exception 'FAIL own employee cannot see ready file';end if;
 if not exists(select 1 from storage.objects where bucket_id='academy-materials' and name=current_setting('academy.qa_file_path')) then raise exception 'FAIL own employee cannot read object';end if;
 begin perform public.academy_archive_material_file(current_setting('academy.qa_file_id')::uuid);raise exception 'FAIL employee archives attachment';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000062',true);
do $$ begin
 if exists(select 1 from public.academy_material_files where material_id='qa-file-material') or exists(select 1 from storage.objects where bucket_id='academy-materials' and name=current_setting('academy.qa_file_path')) then raise exception 'FAIL other department reads file';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000063',true);
do $$ begin
 if exists(select 1 from public.academy_material_files where material_id='qa-file-material') or exists(select 1 from storage.objects where bucket_id='academy-materials' and name=current_setting('academy.qa_file_path')) then raise exception 'FAIL other restaurant reads file';end if;
end $$;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
select public.academy_archive_material_file(current_setting('academy.qa_file_id')::uuid,true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000061',true);
do $$ begin
 if exists(select 1 from storage.objects where bucket_id='academy-materials' and name=current_setting('academy.qa_file_path')) then raise exception 'FAIL archived file visible to employee';end if;
end $$;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
select public.academy_archive_material_file(current_setting('academy.qa_file_id')::uuid,false);
reset role;
update public.academy_content set published=false where id='qa-file-material';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000061',true);
do $$ begin
 if exists(select 1 from storage.objects where bucket_id='academy-materials' and name=current_setting('academy.qa_file_path')) then raise exception 'FAIL draft attachment visible to employee';end if;
end $$;
reset role;
select 'PASS: manager scope, private files, upload limits, pending/draft/archive denial, own published file access, foreign department/restaurant denial' as material_files_security;
rollback;
