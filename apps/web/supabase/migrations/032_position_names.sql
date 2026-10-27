-- Rename jobs and add the senior hookah job. Existing access roles and learning history are preserved.
begin;
CREATE OR REPLACE FUNCTION public.academy_enroll(p_full_name text, p_restaurant_id text, p_department text, p_position text)
 RETURNS academy_profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.academy_profiles;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_full_name is null or length(trim(p_full_name))<2 or length(p_full_name)>150 then raise exception 'Invalid name'; end if;
 if p_restaurant_id is null or p_restaurant_id not in ('minsk','pushkino','khimki','mytishchi') or p_department is null or p_position is null then raise exception 'Complete your team profile'; end if;
 if not ((p_department='Зал' and p_position in ('Официант','Администратор зала','Хостес')) or
 (p_department='Бар' and p_position in ('Старший бармен','Барбэк','Бармен','Бар-менеджер')) or
 (p_department='Кухня' and p_position in ('Повар','Шеф-повар')) or (p_department='Арт' and p_position='Сотрудник арт') or
 (p_department='Кальян' and p_position in ('Кальянный мастер','Старший кальянный мастер')) or (p_department='Руководитель' and p_position in ('Руководитель','Управляющий'))) then raise exception 'Invalid position'; end if;
 insert into public.academy_profiles(id,full_name,restaurant_id,department,position) values(auth.uid(),trim(p_full_name),p_restaurant_id,p_department,p_position)
 on conflict(id) do update set full_name=excluded.full_name,restaurant_id=excluded.restaurant_id,department=excluded.department,position=excluded.position,updated_at=now()
 where academy_profiles.status='pending' and academy_profiles.role='employee' returning * into r;
 if r.id is null then select * into r from public.academy_profiles where id=auth.uid(); end if;
 return r;
end $function$;
CREATE OR REPLACE FUNCTION public.academy_save_course_editor(p_document jsonb, p_expected timestamp with time zone DEFAULT NULL::timestamp with time zone, p_draft_expected timestamp with time zone DEFAULT NULL::timestamp with time zone, p_publish boolean DEFAULT false, p_notify boolean DEFAULT false, p_comment text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.academy_content;d academy_private.course_drafts;l jsonb;b jsonb;doc jsonb:=p_document;ids text[];positions text[]:=array['Официант','Администратор зала','Хостес','Старший бармен','Барбэк','Бармен','Бар-менеджер','Повар','Шеф-повар','Сотрудник арт','Кальянный мастер','Старший кальянный мастер','Руководитель','Управляющий'];
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
end $function$;
CREATE OR REPLACE FUNCTION public.academy_set_course_audience(p_content_id text, p_positions jsonb, p_levels jsonb, p_priorities jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.academy_content; allowed text[]:=array['Официант','Администратор зала','Хостес','Старший бармен','Барбэк','Бармен','Повар','Сотрудник арт','Кальянный мастер','Старший кальянный мастер','Руководитель','Управляющий','Бар-менеджер','Шеф-повар'];
begin
 select * into c from public.academy_content where id=p_content_id for update;
 if c.id is null or c.kind<>'course' or not academy_private.can_edit(c.restaurant_id,c.department) then raise exception 'Недостаточно прав для настройки курса.';end if;
 if jsonb_typeof(p_positions) is distinct from 'array' or jsonb_typeof(p_levels) is distinct from 'array' or jsonb_typeof(p_priorities) is distinct from 'object' then raise exception 'Проверьте категории курса.';end if;
 if jsonb_array_length(p_positions) not between 1 and cardinality(allowed) or exists(select 1 from jsonb_array_elements_text(p_positions) x where x is null or not x=any(allowed)) or (select count(*) from jsonb_array_elements_text(p_positions))<>(select count(distinct x) from jsonb_array_elements_text(p_positions) x) then raise exception 'Выберите хотя бы одну должность без повторов.';end if;
 if jsonb_array_length(p_levels) not between 1 and 2 or exists(select 1 from jsonb_array_elements_text(p_levels) x where x is null or x not in ('trainee','certified')) then raise exception 'Выберите уровень подготовки.';end if;
 if exists(select 1 from jsonb_each_text(p_priorities) x where not p_positions ? x.key or x.value is null or x.value not in ('start','attestation','additional')) then raise exception 'Проверьте приоритеты должностей.';end if;
 update public.academy_content set payload=payload||jsonb_build_object('audiencePositions',p_positions,'audienceLevels',p_levels,'audiencePriorities',p_priorities),updated_at=now() where id=c.id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'course_audience',c.id,jsonb_build_object('positions',p_positions,'levels',p_levels,'priorities',p_priorities));
end $function$;
CREATE OR REPLACE FUNCTION academy_private.valid_work(p_restaurant text, p_department text, p_position text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select coalesce(p_restaurant in ('minsk','pushkino','khimki','mytishchi') and (
 (p_department='Зал' and p_position in ('Официант','Администратор зала','Хостес')) or
 (p_department='Бар' and p_position in ('Старший бармен','Барбэк','Бармен','Бар-менеджер')) or
 (p_department='Кухня' and p_position in ('Повар','Шеф-повар')) or
 (p_department='Арт' and p_position='Сотрудник арт') or
 (p_department='Кальян' and p_position in ('Кальянный мастер','Старший кальянный мастер')) or
 (p_department='Руководитель' and p_position in ('Руководитель','Управляющий'))),false)
$function$;
create or replace function pg_temp.rename_positions(v jsonb) returns jsonb language plpgsql as $$
declare result jsonb; e record; item jsonb; k text; target text;
begin
 if jsonb_typeof(v)='string' then return to_jsonb(case v#>>'{}' when 'Администратор' then 'Администратор зала' when 'Сотрудник кухни' then 'Повар' when 'Сотрудник кальянного подразделения' then 'Кальянный мастер' else v#>>'{}' end);end if;
 if jsonb_typeof(v)='array' then
  result:='[]';for item in select value from jsonb_array_elements(v) loop
   if item='"Сотрудник кальянного подразделения"'::jsonb then result:=result||jsonb_build_array('Кальянный мастер','Старший кальянный мастер');else result:=result||jsonb_build_array(pg_temp.rename_positions(item));end if;
  end loop;return result;
 end if;
 if jsonb_typeof(v)='object' then
  result:='{}';for e in select * from jsonb_each(v) loop
   if e.key='Сотрудник кальянного подразделения' then
    foreach target in array array['Кальянный мастер','Старший кальянный мастер'] loop if not v ? target then result:=result||jsonb_build_object(target,pg_temp.rename_positions(e.value));end if;end loop;
   else k:=case e.key when 'Администратор' then 'Администратор зала' when 'Сотрудник кухни' then 'Повар' else e.key end;
    if k=e.key or not v ? k then result:=result||jsonb_build_object(k,pg_temp.rename_positions(e.value));end if;
   end if;
  end loop;return result;
 end if;return v;
end $$;
create temp table position_identity_before on commit drop as select id,role,status,operations_director,restaurant_id,department from public.academy_profiles;
create temp table position_old_content_versions on commit drop as select id,updated_at from public.academy_content;
update public.academy_profiles set position=case position when 'Администратор' then 'Администратор зала' when 'Сотрудник кухни' then 'Повар' when 'Сотрудник кальянного подразделения' then 'Кальянный мастер' end,updated_at=now() where position in ('Администратор','Сотрудник кухни','Сотрудник кальянного подразделения');
update public.academy_work_changes set position=case position when 'Администратор' then 'Администратор зала' when 'Сотрудник кухни' then 'Повар' when 'Сотрудник кальянного подразделения' then 'Кальянный мастер' else position end,from_position=case from_position when 'Администратор' then 'Администратор зала' when 'Сотрудник кухни' then 'Повар' when 'Сотрудник кальянного подразделения' then 'Кальянный мастер' else from_position end where position in ('Администратор','Сотрудник кухни','Сотрудник кальянного подразделения') or from_position in ('Администратор','Сотрудник кухни','Сотрудник кальянного подразделения');
update public.academy_content set payload=pg_temp.rename_positions(payload),updated_at=now() where payload is distinct from pg_temp.rename_positions(payload);
update academy_private.course_drafts d set document=pg_temp.rename_positions(d.document),base_updated_at=case when d.base_updated_at=o.updated_at then c.updated_at else d.base_updated_at end from public.academy_content c join position_old_content_versions o on o.id=c.id where d.course_id=c.id;
do $verify$ begin if exists(select 1 from position_identity_before b join public.academy_profiles p using(id) where row(b.role,b.status,b.operations_director,b.restaurant_id,b.department) is distinct from row(p.role,p.status,p.operations_director,p.restaurant_id,p.department)) then raise exception 'Position rename changed access identity';end if;end $verify$;
commit;
select full_name,role,position,restaurant_id,department,operations_director from public.academy_profiles where status='active' and (role in ('admin','manager') or department='Руководитель') order by role,full_name;
