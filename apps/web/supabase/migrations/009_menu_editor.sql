-- Menu cards are readable by the restaurant team (department NULL).
-- A manager may edit only cards of their restaurant AND their menu section.
begin;
create or replace function public.academy_save_menu(p_document jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; old public.academy_content;
 rid text:=p_document->>'restaurant_id'; section text:=p_document->'payload'->>'menuSection'; dep text;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null or actor.role not in ('admin','manager') or p_document->>'kind' is distinct from 'menu' then raise exception 'Forbidden'; end if;
 if nullif(trim(p_document->>'title'),'') is null or nullif(p_document->>'id','') is null then raise exception 'Complete menu title'; end if;
 if jsonb_typeof(p_document->'payload') is distinct from 'object' or octet_length((p_document->'payload')::text)>100000 then raise exception 'Invalid menu card'; end if;
 if section not in ('bar','kitchen') or section is null then raise exception 'Invalid menu section'; end if;
 select * into old from public.academy_content where id=p_document->>'id';
 if old.id is not null and old.kind<>'menu' then raise exception 'Content type cannot change'; end if;
 dep:=p_document->>'department';
 if actor.role='manager' then
  if rid is distinct from actor.restaurant_id or actor.restaurant_id is null or
   actor.department is distinct from (case when section='kitchen' then 'Кухня' else 'Бар' end) then raise exception 'Menu outside manager scope'; end if;
  if old.id is not null and (old.restaurant_id is distinct from actor.restaurant_id or
   old.payload->>'menuSection' is distinct from section or (old.department is not null and old.department is distinct from actor.department)) then raise exception 'Menu outside manager scope'; end if;
  -- A menu is studied by the whole restaurant, regardless of employee department.
  dep:=null;
 end if;
 insert into public.academy_content(id,kind,title,course_id,payload,published,restaurant_id,department)
 values(p_document->>'id','menu',trim(p_document->>'title'),null,p_document->'payload',coalesce((p_document->>'published')::boolean,false),rid,dep)
 on conflict(id) do update set title=excluded.title,payload=excluded.payload,published=excluded.published,
 restaurant_id=excluded.restaurant_id,department=excluded.department,updated_at=now();
 insert into academy_private.audit_log(actor_id,action,target) values(auth.uid(),'menu_save',p_document->>'id');
end $$;
revoke all on function public.academy_save_menu(jsonb) from public,anon;
grant execute on function public.academy_save_menu(jsonb) to authenticated;
commit;
