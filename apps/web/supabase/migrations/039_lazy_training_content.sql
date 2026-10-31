-- Lightweight catalog. Existing content and RLS policies are unchanged.
begin;
create or replace function public.academy_content_catalog(p_kind text default null,p_query text default null)
returns setof public.academy_content language sql stable security invoker set search_path='' as $catalog$
 select jsonb_populate_record(c,jsonb_build_object('payload',case when c.kind='menu' then c.payload else
 (c.payload-array['lessons','questions','blocks','body','html','content','text','sections','files','attachments','images','pages','url','file','video','links','answers','answerKeys','guide','categories'])
 ||jsonb_build_object('_catalogOnly',true)
 ||case when c.kind='course' then jsonb_build_object('lessons',coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
 'id',coalesce(l.value->>'id',(l.ordinality-1)::text),'title',l.value->'title','priority',l.value->'priority','dueAt',l.value->'dueAt',
 'images',case when l.ordinality=1 and coalesce(l.value->'images'->0,jsonb_path_query_first(l.value,'$.blocks[*] ? (@.type == "hero").image')) is not null then jsonb_build_array(coalesce(l.value->'images'->0,jsonb_path_query_first(l.value,'$.blocks[*] ? (@.type == "hero").image'))) end
 )) order by l.ordinality) from jsonb_array_elements(case when jsonb_typeof(c.payload->'lessons')='array' then c.payload->'lessons' else '[]'::jsonb end) with ordinality l(value,ordinality)),'[]'::jsonb))
 when c.kind='test' then jsonb_build_object('questionCount',case when jsonb_typeof(c.payload->'questions')='array' then jsonb_array_length(c.payload->'questions') else 0 end) else '{}'::jsonb end end))
 from public.academy_content c
 where (p_kind is null or c.kind=p_kind)
 and (c.published or exists(select 1 from public.academy_profiles p where p.id=auth.uid() and p.role<>'employee'))
 and (nullif(trim(p_query),'') is null or position(lower(p_query) in lower(c.title||' '||c.payload::text))>0)
$catalog$;
create or replace function public.academy_lesson_content(p_course_id text,p_lesson_id text)
returns jsonb language sql stable security invoker set search_path='' as $lesson$
 select l.value||jsonb_build_object('id',coalesce(l.value->>'id',(l.ordinality-1)::text)) from public.academy_content c
 cross join lateral jsonb_array_elements(case when jsonb_typeof(c.payload->'lessons')='array' then c.payload->'lessons' else '[]'::jsonb end) with ordinality l(value,ordinality)
 where c.id=p_course_id and c.kind='course' and coalesce(l.value->>'id',(l.ordinality-1)::text)=p_lesson_id
 and (c.published or exists(select 1 from public.academy_profiles p where p.id=auth.uid() and p.role<>'employee')) limit 1
$lesson$;
revoke all on function public.academy_content_catalog(text,text),public.academy_lesson_content(text,text) from public,anon;
grant execute on function public.academy_content_catalog(text,text),public.academy_lesson_content(text,text) to authenticated;
-- Summary records are read-only; reject accidental saves even from an older editor.
create or replace function academy_private.reject_catalog_payload() returns trigger language plpgsql set search_path='' as $guard$
begin if new.payload ? '_catalogOnly' then raise exception 'Сначала загрузите полное содержимое материала';end if;return new;end $guard$;
revoke all on function academy_private.reject_catalog_payload() from public,anon,authenticated;
create or replace trigger academy_reject_catalog_payload before insert or update on public.academy_content for each row execute function academy_private.reject_catalog_payload();
commit;

notify pgrst,'reload schema';
