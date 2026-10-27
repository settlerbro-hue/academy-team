-- Reserve the existing operations position and access for Alexander Kucher only.
-- No account is promoted, demoted, or otherwise changed by this migration.
begin;
do $$ begin
 if not exists(select 1 from public.academy_profiles p join auth.users u on u.id=p.id where p.id='d4c13a7d-27c6-434d-812b-6bd477166573' and u.email='alexkucher26@gmail.com' and p.operations_director and p.role='manager' and p.position='Операционный директор') then
  raise exception 'Expected existing operations director account not found';
 end if;
 if not exists(select 1 from pg_constraint where conname='academy_single_operations_person' and conrelid='public.academy_profiles'::regclass) then
  alter table public.academy_profiles add constraint academy_single_operations_person check(
   id='d4c13a7d-27c6-434d-812b-6bd477166573'::uuid or
   (not operations_director and position is distinct from 'Операционный директор'));
 end if;
end $$;
create or replace function public.academy_set_operations_director(p_user_id uuid,p_enabled boolean) returns public.academy_profiles language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; member public.academy_profiles; result public.academy_profiles;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active' and role='admin';
 if actor.id is null then raise exception 'Этот доступ изменяет только владелец академии.' using errcode='42501';end if;
 if p_user_id is distinct from 'd4c13a7d-27c6-434d-812b-6bd477166573'::uuid then
  raise exception 'Должность операционного директора закреплена только за Александром Кучером.' using errcode='42501';
 end if;
 select * into member from public.academy_profiles where id=p_user_id for update;
 if member.id is null or member.id=actor.id or member.role='admin' or member.status<>'active' or p_enabled is null then raise exception 'Выберите активного сотрудника. Права владельца через эту форму не меняются.';end if;
 update public.academy_profiles set operations_director=p_enabled,
 role=case when p_enabled then 'manager' else role end,
 department=case when p_enabled then 'Руководитель' else department end,
 position=case when p_enabled then 'Операционный директор' else 'Управляющий' end,
 restaurant_id=case when p_enabled then null else restaurant_id end,updated_at=now()
 where id=p_user_id returning * into result;
 update public.academy_work_changes set status='cancelled',reviewed_at=now(),reviewed_by=actor.id where user_id=p_user_id and status='pending';
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'set_operations_director',p_user_id::text,jsonb_build_object('enabled',p_enabled,'previous_role',member.role,'previous_restaurant',member.restaurant_id,'previous_department',member.department,'previous_position',member.position));
 return result;
end $$;
commit;
select full_name,position,operations_director from public.academy_profiles where operations_director or position='Операционный директор';
