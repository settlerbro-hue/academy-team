-- A dedicated handbook audience; all existing content access remains unchanged.
begin;
create or replace function academy_private.can_read_bar_handbook(p public.academy_profiles,c public.academy_content)
returns boolean language sql stable set search_path='' as $$
 select coalesce(p.status='active' and (p.role='admin' or
 ((c.published or p.role='manager' and p.restaurant_id='minsk' and p.department='Бар') and
 (p.department='Руководитель' or p.restaurant_id='minsk' and p.department='Бар'))),false)
$$;
revoke all on function academy_private.can_read_bar_handbook(public.academy_profiles,public.academy_content) from public,anon,authenticated;
create or replace function academy_private.can_read_content(p_id text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_content c join public.academy_profiles p on p.id=auth.uid()
 where c.id=p_id and p.status='active' and case when c.id='rvb-bar-handbook'
 then academy_private.can_read_bar_handbook(p,c)
 else ((c.published and (c.restaurant_id is null or c.restaurant_id=p.restaurant_id) and (c.department is null or c.department=p.department))
 or p.role='admin' or (p.role='manager' and c.restaurant_id=p.restaurant_id and c.department=p.department)
 or (c.kind='menu' and academy_private.can_edit_menu_for(p,c))) end)
$$;
-- Even a known storage path cannot bypass the handbook's audience.
drop policy if exists rvb_bar_handbook_assets_restricted on storage.objects;
create policy rvb_bar_handbook_assets_restricted on storage.objects as restrictive for select to authenticated
using(bucket_id<>'academy-assets' or name not like 'assets/library/rvb-bar-handbook/%'
 or academy_private.can_read_content('rvb-bar-handbook'));
commit;
