-- Common 90-е bar menu, editable by bar administrators of its three restaurants.
-- Does not change employee roles, personal data access, or RVB / kitchen scope.
begin;
create or replace function academy_private.can_edit_menu_for(a public.academy_profiles,c public.academy_content) returns boolean
language sql stable set search_path='' as $$
 select coalesce(a.status='active' and c.kind='menu' and (a.role='admin' or
 (a.role='manager' and a.restaurant_id is not null
 and a.department=case c.payload->>'menuSection' when 'bar' then 'Бар' when 'kitchen' then 'Кухня' end
 and (c.department is null or c.department=a.department)
 and (c.restaurant_id=a.restaurant_id or
 (c.restaurant_id is null and c.department is null and c.payload->>'brand'='90' and c.payload->>'menuSection'='bar'
 and a.restaurant_id in ('pushkino','khimki','mytishchi'))))),false)
$$;
revoke all on function academy_private.can_edit_menu_for(public.academy_profiles,public.academy_content) from public,anon,authenticated;
create or replace function public.academy_save_menu(p_document jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; old public.academy_content; proposed public.academy_content;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null or actor.role not in ('admin','manager') or p_document->>'kind' is distinct from 'menu' then raise exception 'Forbidden'; end if;
 if nullif(trim(p_document->>'title'),'') is null or nullif(p_document->>'id','') is null then raise exception 'Complete menu title'; end if;
 if jsonb_typeof(p_document->'payload') is distinct from 'object' or octet_length((p_document->'payload')::text)>100000 then raise exception 'Invalid menu card'; end if;
 if coalesce(p_document->'payload'->>'menuSection','') not in ('bar','kitchen') then raise exception 'Invalid menu section'; end if;
 proposed:=jsonb_populate_record(null::public.academy_content,p_document);
 select * into old from public.academy_content where id=proposed.id;
 if old.id is not null and old.kind<>'menu' then raise exception 'Content type cannot change'; end if;
 if not academy_private.can_edit_menu_for(actor,proposed) or
 (old.id is not null and not academy_private.can_edit_menu_for(actor,old)) then raise exception 'Menu outside administrator scope'; end if;
 if actor.role='manager' then
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
end $$;
revoke all on function public.academy_save_menu(jsonb) from public,anon;
grant execute on function public.academy_save_menu(jsonb) to authenticated;
-- Notification publication uses the same narrow menu scope; recipient filtering is unchanged.
create or replace function public.academy_announce_content(p_content_ids text[],p_comment text default '') returns integer
language plpgsql security definer set search_path='' as $$
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
 else academy_private.can_edit(c.restaurant_id,c.department) end) then raise exception 'Уведомлять можно только об опубликованных материалах своей области.';end if;
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
end $$;


-- Keep unpublished menu cards available to the same administrators who may edit them.
create or replace function academy_private.can_read_content(p_id text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_content c join public.academy_profiles p on p.id=auth.uid()
 where c.id=p_id and p.status='active' and ((c.published and (c.restaurant_id is null or c.restaurant_id=p.restaurant_id) and (c.department is null or c.department=p.department))
 or p.role='admin' or (p.role='manager' and c.restaurant_id=p.restaurant_id and c.department=p.department)
 or (c.kind='menu' and academy_private.can_edit_menu_for(p,c))))
$$;

commit;

