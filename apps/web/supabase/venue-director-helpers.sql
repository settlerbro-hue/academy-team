-- Venue director access approved by the owner. Assigns no accounts.
alter table public.academy_profiles add column if not exists venue_director boolean not null default false;
alter table public.academy_profiles add column if not exists venue_director_base_role text check(venue_director_base_role in ('employee','manager'));
alter table public.academy_profiles add constraint academy_venue_director_identity check(not venue_director or coalesce((role='manager' and not operations_director and position='Управляющий' and department='Руководитель' and restaurant_id in ('minsk','pushkino','khimki','mytishchi')),false));
create or replace function academy_private.venue_scope(a public.academy_profiles,r text) returns boolean language sql stable set search_path='' as $$
 select coalesce(a.status='active' and a.role='manager' and a.venue_director and a.position='Управляющий' and a.department='Руководитель' and ((a.restaurant_id='minsk' and r='minsk') or (a.restaurant_id in ('pushkino','khimki','mytishchi') and r in ('pushkino','khimki','mytishchi'))),false)
$$;
create or replace function academy_private.venue_document(a public.academy_profiles,c public.academy_content,editing boolean) returns boolean language plpgsql stable security definer set search_path='' as $$
declare brand text; p public.academy_content; required text[];
begin
 if not coalesce(a.venue_director and a.status='active' and a.role='manager' and a.position='Управляющий' and a.department='Руководитель' and not a.operations_director,false) then return false;end if;
 brand:=case when a.restaurant_id='minsk' then 'rvb' else '90' end;
 if c.course_id is not null then
  select * into p from public.academy_content where id=c.course_id and kind='course' and course_id is null;
  if p.id is null or not academy_private.venue_document(a,p,false) then return false;end if;
 end if;
 if c.restaurant_id is not null then return academy_private.venue_scope(a,c.restaurant_id) and coalesce(c.payload->>'brand',brand) in (brand,'common');end if;
 if c.payload->>'brand' in ('rvb','90') then return c.payload->>'brand'=brand;end if;
 if c.course_id is not null then
  return p.id is not null and academy_private.venue_document(a,p,editing);
 end if;
 if jsonb_typeof(c.payload->'requiredRestaurantIds')='array' and jsonb_array_length(c.payload->'requiredRestaurantIds')>0 then
  select array_agg(value) into required from jsonb_array_elements_text(c.payload->'requiredRestaurantIds');
  return case when editing then not exists(select 1 from unnest(required) r where not academy_private.venue_scope(a,r)) else exists(select 1 from unnest(required) r where academy_private.venue_scope(a,r)) end;
 end if;
 return not editing and c.published;
end $$;
create or replace function academy_private.can_edit_record(c public.academy_content) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select case when a.venue_director then academy_private.venue_document(a,c,true) else academy_private.can_edit(c.restaurant_id,c.department) end from public.academy_profiles a where a.id=auth.uid()),false)
$$;
create or replace function academy_private.can_manage(p_user_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_profiles a join public.academy_profiles b on b.id=p_user_id where a.id=auth.uid() and a.status='active' and
 (a.role='admin' or a.operations_director and b.role<>'admin' and not b.operations_director and b.id<>a.id or
 a.venue_director and academy_private.venue_scope(a,b.restaurant_id) and b.role<>'admin' and not b.operations_director and not b.venue_director and b.id<>a.id or
 a.role='manager' and not a.venue_director and a.restaurant_id=b.restaurant_id and a.department=b.department and b.role='employee'))
$$;
create or replace function academy_private.can_edit(p_restaurant text,p_department text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_profiles a where a.id=auth.uid() and a.status='active' and (a.role='admin' or a.operations_director or academy_private.venue_scope(a,p_restaurant) or a.role='manager' and not a.venue_director and p_restaurant=a.restaurant_id and p_department=a.department))
$$;
create or replace function public.academy_set_venue_director(p_user_id uuid,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
declare a public.academy_profiles;b public.academy_profiles;
begin
 select * into a from public.academy_profiles where id=auth.uid() and status='active';
 if a.id is null or not(a.role='admin' or a.operations_director) then raise exception 'Допуск управляющего выдаёт владелец или операционный директор.' using errcode='42501';end if;
 select * into b from public.academy_profiles where id=p_user_id for update;
 if b.id is null or b.id=a.id or b.role='admin' or b.operations_director or b.status<>'active' or b.position is distinct from 'Управляющий' or b.department is distinct from 'Руководитель' or b.restaurant_id is null or p_enabled is null then raise exception 'Выберите активного управляющего с указанным заведением.';end if;
 update public.academy_profiles set venue_director=p_enabled,role=case when p_enabled then 'manager' when b.venue_director then coalesce(b.venue_director_base_role,'employee') else b.role end,
 venue_director_base_role=case when p_enabled then case when b.venue_director then b.venue_director_base_role else b.role end else null end,updated_at=now() where id=b.id;
 update public.academy_work_changes set status='cancelled',reviewed_at=now(),reviewed_by=a.id where user_id=b.id and status='pending';
 insert into academy_private.audit_log(actor_id,action,target,details) values(a.id,'set_venue_director',b.id::text,jsonb_build_object('enabled',p_enabled,'restaurant',b.restaurant_id,'brand',case when b.restaurant_id='minsk' then 'rvb' else '90' end));
end $$;
revoke all on function public.academy_set_venue_director(uuid,boolean) from public,anon;
grant execute on function public.academy_set_venue_director(uuid,boolean) to authenticated;
revoke all on function academy_private.venue_scope(public.academy_profiles,text),academy_private.venue_document(public.academy_profiles,public.academy_content,boolean),academy_private.can_edit_record(public.academy_content) from public,anon;
grant execute on function academy_private.venue_scope(public.academy_profiles,text),academy_private.venue_document(public.academy_profiles,public.academy_content,boolean),academy_private.can_edit_record(public.academy_content) to authenticated;
