-- Canonical network job and a display-only personal caption. No role or permission grants.
begin;
alter table public.academy_profiles add column position_caption text;
alter table public.academy_work_changes add column position_caption text;
alter table public.academy_profiles drop constraint academy_network_work_identity;
alter table public.academy_work_changes drop constraint academy_network_request_identity;
update public.academy_profiles set position='Управляющая компания' where restaurant_id='network';
update public.academy_work_changes set position='Управляющая компания' where restaurant_id='network';
update public.academy_work_changes set from_position='Управляющая компания' where from_restaurant='network';
alter table public.academy_profiles add constraint academy_network_work_identity check(restaurant_id is distinct from 'network' or coalesce(department='Руководитель' and position='Управляющая компания',false));
alter table public.academy_work_changes add constraint academy_network_request_identity check(restaurant_id<>'network' or department='Руководитель' and position='Управляющая компания');
alter table public.academy_profiles add constraint academy_caption_value check(position_caption is null or (restaurant_id='network' and char_length(position_caption) between 1 and 100 and position_caption !~ '[[:cntrl:]]'));
alter table public.academy_work_changes add constraint academy_request_caption_value check(position_caption is null or (restaurant_id='network' and char_length(position_caption) between 1 and 100 and position_caption !~ '[[:cntrl:]]'));
CREATE OR REPLACE FUNCTION academy_private.valid_work(p_restaurant text, p_department text, p_position text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select coalesce((p_restaurant='network' and p_department='Руководитель' and p_position='Управляющая компания') or p_restaurant in ('minsk','pushkino','khimki','mytishchi') and (
 (p_department='Зал' and p_position in ('Официант','Администратор зала','Хостес')) or
 (p_department='Бар' and p_position in ('Старший бармен','Барбэк','Бармен','Бар-менеджер')) or
 (p_department='Кухня' and p_position in ('Повар','Шеф-повар')) or
 (p_department='Арт' and p_position='Сотрудник арт') or
 (p_department='Кальян' and p_position in ('Кальянный мастер','Старший кальянный мастер')) or
 (p_department='Руководитель' and p_position in ('Руководитель','Управляющий'))),false)
$function$;

CREATE OR REPLACE FUNCTION public.academy_assign_work(p_user_id uuid, p_restaurant_id text, p_department text, p_position text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor public.academy_profiles; member public.academy_profiles;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 select * into member from public.academy_profiles where id=p_user_id for update;
 if actor.id is null or member.id is null or not academy_private.can_manage(p_user_id) or (actor.role<>'admin' and not actor.operations_director and not actor.venue_director and (member.id=actor.id or member.role<>'employee')) then raise exception 'Можно менять только рабочие данные сотрудников своей команды.'; end if;
 if actor.venue_director and not academy_private.venue_scope(actor,p_restaurant_id) then raise exception 'Перевод за пределы области управляющего недоступен.';end if;
 if member.venue_director and row(member.restaurant_id,member.department,member.position) is distinct from row(p_restaurant_id,p_department,p_position) then raise exception 'Сначала снимите допуск управляющего перед изменением его области.';end if;
 if (p_restaurant_id='network' or member.restaurant_id='network') and actor.role<>'admin' and not actor.operations_director then raise exception 'Сетевую принадлежность назначает владелец или операционный директор.';end if;
 if not academy_private.valid_work(p_restaurant_id,p_department,p_position) then raise exception 'Проверьте заведение, подразделение и должность.'; end if;
 update public.academy_profiles set restaurant_id=p_restaurant_id,department=p_department,position=p_position,position_caption=case when p_restaurant_id='network' then position_caption else null end,updated_at=now() where id=member.id;
 update public.academy_work_changes set status='cancelled',reviewed_at=now(),reviewed_by=actor.id where user_id=member.id and status='pending';
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'assign_work',member.id::text,jsonb_build_object('from',jsonb_build_object('restaurant',member.restaurant_id,'department',member.department,'position',member.position),'to',jsonb_build_object('restaurant',p_restaurant_id,'department',p_department,'position',p_position)));
end $function$;

CREATE OR REPLACE FUNCTION public.academy_review_work_change(p_request_id uuid, p_approve boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor public.academy_profiles; member public.academy_profiles; request public.academy_work_changes; target_user uuid;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null or actor.role not in ('manager','admin') or p_approve is null then raise exception 'Доступ закрыт.'; end if;
 select user_id into target_user from public.academy_work_changes where id=p_request_id;
 select * into member from public.academy_profiles where id=target_user for update;
 select * into request from public.academy_work_changes where id=p_request_id for update;
 if request.id is null or request.status<>'pending' then raise exception 'Заявка уже обработана или недоступна.'; end if;
 if (request.restaurant_id='network' or member.restaurant_id='network') and actor.role<>'admin' and not actor.operations_director then raise exception 'Сетевую заявку подтверждает владелец или операционный директор.';end if;
 if member.id=actor.id or not(actor.role='admin' or actor.operations_director and academy_private.can_manage(member.id) or (actor.venue_director and academy_private.can_manage(member.id) and academy_private.venue_scope(actor,request.restaurant_id)) or (actor.role='manager' and not actor.venue_director and member.role='employee' and request.original_role='employee' and actor.restaurant_id=request.restaurant_id and actor.department=request.department)) then raise exception 'Подтверждение доступно администратору принимающей команды или владельцу.'; end if;
 if member.status<>'active' or member.role is distinct from request.original_role or member.restaurant_id is distinct from request.from_restaurant or member.department is distinct from request.from_department or member.position is distinct from request.from_position then raise exception 'Рабочие данные уже изменились. Попросите сотрудника отменить заявку и отправить новую.'; end if;
 if p_approve then
 update public.academy_profiles set restaurant_id=request.restaurant_id,department=request.department,position=request.position,position_caption=case when request.restaurant_id='network' then request.position_caption else null end,updated_at=now() where id=member.id;
 end if;
 update public.academy_work_changes set status=case when p_approve then 'approved' else 'rejected' end,reviewed_at=now(),reviewed_by=actor.id where id=request.id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'review_work_change',request.id::text,jsonb_build_object('approved',p_approve,'user_id',member.id,'from',jsonb_build_object('restaurant',member.restaurant_id,'department',member.department,'position',member.position),'to',jsonb_build_object('restaurant',request.restaurant_id,'department',request.department,'position',request.position)));
end $function$;

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
 if not academy_private.valid_work(p_restaurant_id,p_department,p_position) then raise exception 'Проверьте заведение, подразделение и должность.';end if;
 insert into public.academy_profiles(id,full_name,restaurant_id,department,position) values(auth.uid(),trim(p_full_name),p_restaurant_id,p_department,p_position)
 on conflict(id) do update set full_name=excluded.full_name,restaurant_id=excluded.restaurant_id,department=excluded.department,position=excluded.position,position_caption=case when excluded.restaurant_id='network' then academy_profiles.position_caption else null end,updated_at=now()
 where academy_profiles.status='pending' and academy_profiles.role='employee' returning * into r;
 if r.id is null then select * into r from public.academy_profiles where id=auth.uid(); end if;
 return r;
end $function$;

create or replace function public.academy_set_position_caption(p_caption text,p_user_id uuid default null,p_request_id uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; member public.academy_profiles; r public.academy_work_changes; caption text:=nullif(trim(p_caption),'');target uuid:=coalesce(p_user_id,auth.uid());
begin
 if auth.uid() is null or (p_user_id is not null and p_request_id is not null) then raise exception 'Доступ закрыт';end if;
 if caption is not null and (char_length(caption)>100 or caption ~ '[[:cntrl:]]') then raise exception 'Подпись: одна строка, до 100 символов';end if;
 select * into actor from public.academy_profiles where id=auth.uid();
 if actor.id is null or actor.status not in ('active','pending') then raise exception 'Доступ закрыт';end if;
 if p_request_id is not null then
  select * into r from public.academy_work_changes where id=p_request_id for update;
  if r.id is null or r.status<>'pending' or r.restaurant_id<>'network' or actor.status<>'active' or not (r.user_id=actor.id or (actor.role='admin' or actor.operations_director) and academy_private.can_manage(r.user_id)) then raise exception 'Заявка недоступна';end if;
  update public.academy_work_changes set position_caption=caption where id=r.id;
 else
  select * into member from public.academy_profiles where id=target for update;
  if member.id is null or member.restaurant_id<>'network' or actor.status not in ('active','pending') or not (member.id=actor.id or actor.status='active' and academy_private.can_manage(member.id)) then raise exception 'Профиль недоступен';end if;
  update public.academy_profiles set position_caption=caption,updated_at=now() where id=member.id;
 end if;
 insert into academy_private.audit_log(actor_id,action,target) values(auth.uid(),'position_caption',coalesce(p_request_id,target)::text);
end $$;
revoke all on function public.academy_set_position_caption(text,uuid,uuid) from public,anon;
grant execute on function public.academy_set_position_caption(text,uuid,uuid) to authenticated;
commit;
