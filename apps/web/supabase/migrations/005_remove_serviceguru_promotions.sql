-- Apply AFTER the original seed on new installations. Idempotent, reversible unpublishing.
-- Keep staff results, answer keys, restaurant news and useful professional courses.
begin;
update public.academy_content
set published=false, payload=payload || '{"catalogArchiveReason":"serviceguru-platform-promotion"}'::jsonb,
    updated_at=now()
where id in (
 'guru-42875',
 'library-import-1ee5290642','library-import-7b75895542',
 'library-import-a3ace598b1','library-import-c39419578c',
 'library-import-629bbb4b70','library-import-2abfd5b504',
 'announcement-4232a2768736','announcement-39a31bd701f0',
 'announcement-6a9dbb3859da','announcement-b39a1e942c89','announcement-64c3e6d88b7c'
 ) or course_id='guru-42875';

-- Retain the removed lesson in the existing document for recovery; the reader uses lessons only.
update public.academy_content c
set payload=jsonb_set(
 jsonb_set(c.payload,'{catalogArchivedLessons}',
   coalesce(c.payload->'catalogArchivedLessons','[]'::jsonb) ||
   (select jsonb_agg(l) from jsonb_array_elements(c.payload->'lessons') l where l->>'id'='101488')),
 '{lessons}',
 coalesce((select jsonb_agg(l order by n) from jsonb_array_elements(c.payload->'lessons') with ordinality as a(l,n) where l->>'id'<>'101488'),'[]'::jsonb)),
 updated_at=now()
where c.id='guru-43399' and exists(select 1 from jsonb_array_elements(c.payload->'lessons') l where l->>'id'='101488');

update public.academy_content
set payload=jsonb_set(payload,'{description}',to_jsonb(replace(payload->>'description',' Перенесено из вашего ServiceGuru.',''))),updated_at=now()
where payload->>'description' like '% Перенесено из вашего ServiceGuru.%';

update public.academy_content c
set payload=jsonb_set(c.payload,'{lessons}',(
 select jsonb_agg(case when l->>'id'='123016' then jsonb_set(l,'{text}',to_jsonb('Руководство компании'::text)) else l end order by n)
 from jsonb_array_elements(c.payload->'lessons') with ordinality as a(l,n))),updated_at=now()
where c.id='welcome-90';
commit;

select kind,count(*) as unpublished_platform_records
from public.academy_content where payload->>'catalogArchiveReason'='serviceguru-platform-promotion' group by kind;
