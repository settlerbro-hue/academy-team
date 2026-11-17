begin;

-- Preserve the production access function, including policies installed by content updates.
do $access$
declare
  definition text := pg_get_functiondef('academy_private.can_read_content(text)'::regprocedure);
  anchor constant text := 'where c.id=p_id and p.status=''active''';
  scope constant text := 'and (coalesce(c.payload->>''trainingBrand'','''') = '''' or p.role=''admin'' or p.operations_director or (c.payload->>''trainingBrand''=''rvb'' and p.restaurant_id=''minsk'') or (c.payload->>''trainingBrand''=''90'' and p.restaurant_id in (''pushkino'',''khimki'',''mytishchi'')))';
begin
  if position('trainingBrand' in definition) = 0 then
    if position(anchor in definition) = 0 then
      raise exception 'Unexpected training access definition';
    end if;
    insert into academy_private.audit_log(action,target,details)
    values ('training_brand_access_before','academy_private.can_read_content',jsonb_build_object('definition',definition));
    execute replace(definition,anchor,anchor||' '||scope);
  end if;
end $access$;

-- Versions can reuse original files referenced by both courses. New files belong
-- to the course where they were uploaded and retain the existing storage policies.
create or replace function academy_private.can_read_course_media(p_id uuid)
returns boolean
language sql stable security definer set search_path=''
as $media$
  select exists (
    select 1
    from public.academy_course_media m
    join public.academy_content c on c.id=m.course_id
      or (c.kind='course' and c.payload->>'trainingSourceId'=m.course_id)
    where m.id=p_id and (
      (c.id=m.course_id and academy_private.can_edit_record(c))
      or (m.status='ready' and c.published and academy_private.can_read_content(c.id) and
        jsonb_path_exists(c.payload,'$.lessons[*].blocks[*] ? (@.image == $ref || @.src == $ref)',
          jsonb_build_object('ref','course-media:'||m.id)))
    )
  )
$media$;

commit;
