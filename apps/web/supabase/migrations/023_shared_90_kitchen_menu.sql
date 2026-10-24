-- Common 90-е kitchen: same scoped editing / draft access / notifications as the bar.
-- Existing employee profiles, roles, and learning results are untouched.
begin;
create or replace function academy_private.can_edit_menu_for(a public.academy_profiles,c public.academy_content) returns boolean
language sql stable set search_path='' as $$
 select coalesce(a.status='active' and c.kind='menu' and (a.role='admin' or
 (a.role='manager' and a.restaurant_id is not null
 and a.department=case c.payload->>'menuSection' when 'bar' then 'Бар' when 'kitchen' then 'Кухня' end
 and (c.department is null or c.department=a.department)
 and (c.restaurant_id=a.restaurant_id or
 (c.restaurant_id is null and c.department is null and c.payload->>'brand'='90' and c.payload->>'menuSection' in ('bar','kitchen')
 and a.restaurant_id in ('pushkino','khimki','mytishchi'))))),false)
$$;
revoke all on function academy_private.can_edit_menu_for(public.academy_profiles,public.academy_content) from public,anon,authenticated;
commit;
