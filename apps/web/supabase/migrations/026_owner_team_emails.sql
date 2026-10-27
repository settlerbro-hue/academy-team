-- Contact emails are returned only to the active academy owner.
-- They are never copied to public profiles, ranking, course payloads or exports.
begin;
create or replace function public.academy_owner_team_emails() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.academy_profiles where id=auth.uid() and status='active' and role='admin') then
  raise exception 'Доступ к почте сотрудников есть только у владельца академии.' using errcode='42501';
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',p.id,'email',u.email) order by p.full_name,p.id)
 from public.academy_profiles p join auth.users u on u.id=p.id),'[]'::jsonb);
end $$;
revoke all on function public.academy_owner_team_emails() from public,anon;
grant execute on function public.academy_owner_team_emails() to authenticated;
commit;
