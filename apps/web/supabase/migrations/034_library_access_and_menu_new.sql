-- Optional library audiences; existing rows and availability are unchanged.
begin;
create or replace function academy_private.library_audience_for(p public.academy_profiles,c public.academy_content)
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(c.kind<>'material' or c.payload->'libraryAccess'->'enabled' is distinct from 'true'::jsonb
 or p.role='admin' or p.operations_director
 or (p.venue_director and academy_private.venue_document(p,c,false))
 or (p.role='manager' and c.restaurant_id=p.restaurant_id and c.department=p.department)
 or (c.payload->'libraryAccess'->'departments' ? p.department and c.payload->'libraryAccess'->'positions' ? p.position),false)
$$;
create or replace function academy_private.validate_library_access(c public.academy_content)
returns void language plpgsql set search_path='' as $$
declare a jsonb:=c.payload->'libraryAccess'; d text; j text;
begin
 if c.kind<>'material' or a is null then return;end if;
 if jsonb_typeof(a) is distinct from 'object' or jsonb_typeof(a->'enabled') is distinct from 'boolean' then raise exception 'Некорректная настройка доступа';end if;
 if a->'enabled'='false'::jsonb then return;end if;
 if jsonb_typeof(a->'departments') is distinct from 'array' or jsonb_typeof(a->'positions') is distinct from 'array' then raise exception 'Выберите подразделения и должности';end if;
 if jsonb_array_length(a->'departments') not between 1 and 6 or jsonb_array_length(a->'positions') not between 1 and 13 then raise exception 'Выберите подразделения и должности';end if;
 if (select count(distinct value) from jsonb_array_elements(a->'departments'))<>jsonb_array_length(a->'departments') or (select count(distinct value) from jsonb_array_elements(a->'positions'))<>jsonb_array_length(a->'positions') then raise exception 'Повторяющиеся значения доступа';end if;
 for d in select jsonb_array_elements_text(a->'departments') loop
  if d not in ('Зал','Бар','Кухня','Арт','Кальян','Руководитель') or (c.department is not null and c.department<>d) then raise exception 'Подразделение вне области материала';end if;
 end loop;
 for j in select jsonb_array_elements_text(a->'positions') loop
  if j not in ('Официант','Администратор зала','Хостес','Старший бармен','Барбэк','Бармен','Бар-менеджер','Повар','Шеф-повар','Сотрудник арт','Кальянный мастер','Старший кальянный мастер','Управляющий')
   or not exists(select 1 from jsonb_array_elements_text(a->'departments') x where academy_private.valid_work('minsk',x,j)) then raise exception 'Должность вне выбранных подразделений';end if;
 end loop;
end $$;
create or replace function academy_private.validate_menu_news(p jsonb)
returns void language plpgsql set search_path='' as $$
declare until_at timestamptz;
begin
 if not p ? 'isNewItem' then return;end if;
 if jsonb_typeof(p->'isNewItem') is distinct from 'boolean' then raise exception 'Некорректная отметка новинки';end if;
 if p->'isNewItem'='false'::jsonb then return;end if;
 begin until_at:=(p->>'newBadgeUntil')::timestamptz;exception when others then raise exception 'Укажите дату окончания новинки';end;
 if until_at is null or not isfinite(until_at) or until_at<=clock_timestamp() then raise exception 'Дата окончания новинки должна быть в будущем';end if;
end $$;
revoke all on function academy_private.library_audience_for(public.academy_profiles,public.academy_content) from public,anon,authenticated;
revoke all on function academy_private.validate_library_access(public.academy_content) from public,anon,authenticated;
revoke all on function academy_private.validate_menu_news(jsonb) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION academy_private.can_read_content(p_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.academy_content c join public.academy_profiles p on p.id=auth.uid()
 where c.id=p_id and p.status='active' and academy_private.library_audience_for(p,c) and case when p.venue_director then academy_private.venue_document(p,c,false) else case when c.id='rvb-bar-handbook'
 then academy_private.can_read_bar_handbook(p,c)
 else ((c.published and (c.restaurant_id is null or c.restaurant_id=p.restaurant_id) and (c.department is null or c.department=p.department))
 or p.role='admin' or p.operations_director or (p.role='manager' and c.restaurant_id=p.restaurant_id and c.department=p.department)
 or (c.kind='menu' and academy_private.can_edit_menu_for(p,c))) end end)
$function$;
CREATE OR REPLACE FUNCTION academy_private.notice_content_for(p academy_profiles, c academy_content)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select academy_private.library_audience_for(p,c) and case when p.venue_director then c.published and academy_private.venue_document(p,c,false) when academy_private.is_operations_director(p.id) then c.published else coalesce(p.status='active' and c.published
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
 perform academy_private.validate_library_access(jsonb_populate_record(null::public.academy_content,p_document));
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
CREATE OR REPLACE FUNCTION public.academy_save_menu(p_document jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor public.academy_profiles; old public.academy_content; proposed public.academy_content;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null or actor.role not in ('admin','manager') or p_document->>'kind' is distinct from 'menu' then raise exception 'Forbidden'; end if;
 if nullif(trim(p_document->>'title'),'') is null or nullif(p_document->>'id','') is null then raise exception 'Complete menu title'; end if;
 if jsonb_typeof(p_document->'payload') is distinct from 'object' or octet_length((p_document->'payload')::text)>100000 then raise exception 'Invalid menu card'; end if;
 if coalesce(p_document->'payload'->>'menuSection','') not in ('bar','kitchen') then raise exception 'Invalid menu section'; end if;
 perform academy_private.validate_menu_news(p_document->'payload');
 proposed:=jsonb_populate_record(null::public.academy_content,p_document);
 select * into old from public.academy_content where id=proposed.id;
 if old.id is not null and old.kind<>'menu' then raise exception 'Content type cannot change'; end if;
 if not academy_private.can_edit_menu_for(actor,proposed) or
 (old.id is not null and not academy_private.can_edit_menu_for(actor,old)) then raise exception 'Menu outside administrator scope'; end if;
 if actor.role='manager' and not actor.operations_director then
 if old.id is not null and (old.restaurant_id is distinct from proposed.restaurant_id or
 old.payload->>'brand' is distinct from proposed.payload->>'brand' or
 old.payload->>'menuSection' is distinct from proposed.payload->>'menuSection') then raise exception 'Menu scope cannot change'; end if;
 proposed.department:=null;
 end if;
 insert into public.academy_content(id,kind,title,course_id,payload,published,restaurant_id,department)
 values(proposed.id,'menu',trim(proposed.title),null,proposed.payload,coalesce(proposed.published,false),proposed.restaurant_id,proposed.department)
 on conflict(id) do update set title=excluded.title,payload=excluded.payload,published=excluded.published,
 restaurant_id=excluded.restaurant_id,department=excluded.department,updated_at=now();
 insert into academy_private.audit_log(actor_id,action,target) values(auth.uid(),'menu_save',proposed.id);
end $function$;
commit;
