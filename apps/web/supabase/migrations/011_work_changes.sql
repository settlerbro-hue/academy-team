begin;
create table if not exists public.academy_work_changes (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.academy_profiles(id),
 full_name text not null,original_role text not null,from_restaurant text,from_department text,from_position text,
 restaurant_id text not null check(restaurant_id in ('minsk','pushkino','khimki','mytishchi')),
 department text not null,position text not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
 created_at timestamptz not null default now(),reviewed_at timestamptz,reviewed_by uuid references public.academy_profiles(id)
);
create unique index if not exists academy_one_work_change_pending on public.academy_work_changes(user_id) where status='pending';
alter table public.academy_work_changes enable row level security;
revoke all on public.academy_work_changes from public,anon,authenticated;

create or replace function academy_private.valid_work(p_restaurant text,p_department text,p_position text)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(p_restaurant in ('minsk','pushkino','khimki','mytishchi') and (
 (p_department='Зал' and p_position in ('Официант','Администратор','Хостес')) or
 (p_department='Бар' and p_position in ('Старший бармен','Барбэк','Бармен')) or
 (p_department='Кухня' and p_position='Сотрудник кухни') or
 (p_department='Арт' and p_position='Сотрудник арт') or
 (p_department='Кальян' and p_position='Сотрудник кальянного подразделения') or
 (p_department='Руководитель' and p_position in ('Руководитель','Управляющий'))),false)
$$;
revoke all on function academy_private.valid_work(text,text,text) from public,anon,authenticated;

create or replace function public.academy_work_change_list() returns jsonb language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; result jsonb;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null then raise exception 'Доступ закрыт.'; end if;
 select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('can_review',r.user_id<>actor.id and (actor.role='admin' or (actor.role='manager' and r.original_role='employee' and r.restaurant_id=actor.restaurant_id and r.department=actor.department))) order by r.created_at desc),'[]'::jsonb) into result
 from public.academy_work_changes r where r.user_id=actor.id or actor.role='admin' or
 (actor.role='manager' and r.original_role='employee' and r.restaurant_id=actor.restaurant_id and r.department=actor.department);
 return result;
end $$;

create or replace function public.academy_request_work_change(p_restaurant_id text,p_department text,p_position text)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; request_id uuid;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active' for update;
 if actor.id is null then raise exception 'Доступ закрыт.'; end if;
 if not academy_private.valid_work(p_restaurant_id,p_department,p_position) then raise exception 'Проверьте заведение, подразделение и должность.'; end if;
 if actor.restaurant_id is not distinct from p_restaurant_id and actor.department is not distinct from p_department and actor.position is not distinct from p_position then raise exception 'Выберите новые рабочие данные.'; end if;
 if exists(select 1 from public.academy_work_changes where user_id=actor.id and status='pending') then raise exception 'Сначала дождитесь решения или отмените текущую заявку.'; end if;
 insert into public.academy_work_changes(user_id,full_name,original_role,from_restaurant,from_department,from_position,restaurant_id,department,position)
 values(actor.id,actor.full_name,actor.role,actor.restaurant_id,actor.department,actor.position,p_restaurant_id,p_department,p_position) returning id into request_id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'request_work_change',request_id::text,jsonb_build_object('user_id',actor.id,'restaurant',p_restaurant_id,'department',p_department,'position',p_position));
 return request_id;
end $$;

create or replace function public.academy_cancel_work_change(p_request_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not academy_private.is_active() then raise exception 'Доступ закрыт.'; end if;
 update public.academy_work_changes set status='cancelled',reviewed_at=now(),reviewed_by=auth.uid() where id=p_request_id and user_id=auth.uid() and status='pending';
 if not found then raise exception 'Заявка уже обработана или недоступна.'; end if;
 insert into academy_private.audit_log(actor_id,action,target) values(auth.uid(),'cancel_work_change',p_request_id::text);
end $$;

create or replace function public.academy_review_work_change(p_request_id uuid,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; member public.academy_profiles; request public.academy_work_changes; target_user uuid;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null or actor.role not in ('manager','admin') or p_approve is null then raise exception 'Доступ закрыт.'; end if;
 select user_id into target_user from public.academy_work_changes where id=p_request_id;
 select * into member from public.academy_profiles where id=target_user for update;
 select * into request from public.academy_work_changes where id=p_request_id for update;
 if request.id is null or request.status<>'pending' then raise exception 'Заявка уже обработана или недоступна.'; end if;
 if member.id=actor.id or not(actor.role='admin' or (actor.role='manager' and member.role='employee' and request.original_role='employee' and actor.restaurant_id=request.restaurant_id and actor.department=request.department)) then raise exception 'Подтверждение доступно администратору принимающей команды или владельцу.'; end if;
 if member.status<>'active' or member.role is distinct from request.original_role or member.restaurant_id is distinct from request.from_restaurant or member.department is distinct from request.from_department or member.position is distinct from request.from_position then raise exception 'Рабочие данные уже изменились. Попросите сотрудника отменить заявку и отправить новую.'; end if;
 if p_approve then
 update public.academy_profiles set restaurant_id=request.restaurant_id,department=request.department,position=request.position,updated_at=now() where id=member.id;
 end if;
 update public.academy_work_changes set status=case when p_approve then 'approved' else 'rejected' end,reviewed_at=now(),reviewed_by=actor.id where id=request.id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'review_work_change',request.id::text,jsonb_build_object('approved',p_approve,'user_id',member.id,'from',jsonb_build_object('restaurant',member.restaurant_id,'department',member.department,'position',member.position),'to',jsonb_build_object('restaurant',request.restaurant_id,'department',request.department,'position',request.position)));
end $$;

create or replace function public.academy_assign_work(p_user_id uuid,p_restaurant_id text,p_department text,p_position text)
returns void language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; member public.academy_profiles;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 select * into member from public.academy_profiles where id=p_user_id for update;
 if actor.id is null or member.id is null or not academy_private.can_manage(p_user_id) or (actor.role<>'admin' and (member.id=actor.id or member.role<>'employee')) then raise exception 'Можно менять только рабочие данные сотрудников своей команды.'; end if;
 if not academy_private.valid_work(p_restaurant_id,p_department,p_position) then raise exception 'Проверьте заведение, подразделение и должность.'; end if;
 update public.academy_profiles set restaurant_id=p_restaurant_id,department=p_department,position=p_position,updated_at=now() where id=member.id;
 update public.academy_work_changes set status='cancelled',reviewed_at=now(),reviewed_by=actor.id where user_id=member.id and status='pending';
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'assign_work',member.id::text,jsonb_build_object('from',jsonb_build_object('restaurant',member.restaurant_id,'department',member.department,'position',member.position),'to',jsonb_build_object('restaurant',p_restaurant_id,'department',p_department,'position',p_position)));
end $$;
revoke all on function public.academy_work_change_list(),public.academy_request_work_change(text,text,text),public.academy_cancel_work_change(uuid),public.academy_review_work_change(uuid,boolean),public.academy_assign_work(uuid,text,text,text) from public,anon;
grant execute on function public.academy_work_change_list(),public.academy_request_work_change(text,text,text),public.academy_cancel_work_change(uuid),public.academy_review_work_change(uuid,boolean),public.academy_assign_work(uuid,text,text,text) to authenticated;
commit;
