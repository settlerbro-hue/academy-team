begin;

do $guides$
declare
  guide_ids constant text[] := array['bar-wine-guide','bar-beer-guide','bar-drinks-guide'];
  audience constant jsonb := '{"enabled":true,"departments":["Бар","Зал"],"positions":["Старший бармен","Барбэк","Бармен","Бар-менеджер","Официант","Администратор зала","Хостес"]}';
  guide public.academy_content;
  checked integer := 0;
begin
  for guide in select * from public.academy_content where id = any(guide_ids) order by id for update loop
    if guide.kind <> 'material' or guide.published is distinct from true
       or guide.restaurant_id is not null or guide.payload->>'brand' is distinct from 'common'
       or not coalesce(
         (guide.department = 'Бар' and not (guide.payload ? 'libraryAccess'))
         or (guide.department is null and guide.payload->'libraryAccess' = audience), false
       ) then
      raise exception 'Unexpected audience or scope for %', guide.id;
    end if;
    guide.department := null;
    guide.payload := jsonb_set(guide.payload, '{libraryAccess}', audience);
    perform academy_private.validate_library_access(guide);
    update public.academy_content
    set department = guide.department, payload = guide.payload, updated_at = now()
    where id = guide.id and (department is distinct from guide.department or payload is distinct from guide.payload);
    checked := checked + 1;
  end loop;
  if checked <> cardinality(guide_ids) then raise exception 'Expected three bar guides'; end if;
end;
$guides$;

commit;
