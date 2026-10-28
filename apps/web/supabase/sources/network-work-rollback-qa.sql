-- Network affiliation is not a permission grant. No profiles are reassigned.
begin;
alter table public.academy_profiles drop constraint academy_profiles_restaurant_id_check;
alter table public.academy_profiles add constraint academy_profiles_restaurant_id_check check(restaurant_id in ('minsk','pushkino','khimki','mytishchi','network'));
alter table public.academy_profiles add constraint academy_network_work_identity check(restaurant_id is distinct from 'network' or coalesce(department='Руководитель' and position='Управляющий',false));
alter table public.academy_work_changes drop constraint academy_work_changes_restaurant_id_check;
alter table public.academy_work_changes add constraint academy_work_changes_restaurant_id_check check(restaurant_id in ('minsk','pushkino','khimki','mytishchi','network'));
alter table public.academy_work_changes add constraint academy_network_request_identity check(restaurant_id<>'network' or department='Руководитель' and position='Управляющий');
CREATE OR REPLACE FUNCTION academy_private.valid_work(p_restaurant text, p_department text, p_position text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select coalesce((p_restaurant='network' and p_department='Руководитель' and p_position='Управляющий') or p_restaurant in ('minsk','pushkino','khimki','mytishchi') and (
 (p_department='Зал' and p_position in ('Официант','Администратор зала','Хостес')) or
 (p_department='Бар' and p_position in ('Старший бармен','Барбэк','Бармен','Бар-менеджер')) or
 (p_department='Кухня' and p_position in ('Повар','Шеф-повар')) or
 (p_department='Арт' and p_position='Сотрудник арт') or
 (p_department='Кальян' and p_position in ('Кальянный мастер','Старший кальянный мастер')) or
 (p_department='Руководитель' and p_position in ('Руководитель','Управляющий'))),false)
$function$;
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
 on conflict(id) do update set full_name=excluded.full_name,restaurant_id=excluded.restaurant_id,department=excluded.department,position=excluded.position,updated_at=now()
 where academy_profiles.status='pending' and academy_profiles.role='employee' returning * into r;
 if r.id is null then select * into r from public.academy_profiles where id=auth.uid(); end if;
 return r;
end $function$;
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
 update public.academy_profiles set restaurant_id=p_restaurant_id,department=p_department,position=p_position,updated_at=now() where id=member.id;
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
 update public.academy_profiles set restaurant_id=request.restaurant_id,department=request.department,position=request.position,updated_at=now() where id=member.id;
 end if;
 update public.academy_work_changes set status=case when p_approve then 'approved' else 'rejected' end,reviewed_at=now(),reviewed_by=actor.id where id=request.id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'review_work_change',request.id::text,jsonb_build_object('approved',p_approve,'user_id',member.id,'from',jsonb_build_object('restaurant',member.restaurant_id,'department',member.department,'position',member.position),'to',jsonb_build_object('restaurant',request.restaurant_id,'department',request.department,'position',request.position)));
end $function$;
CREATE OR REPLACE FUNCTION public.academy_work_change_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor public.academy_profiles; result jsonb;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null then raise exception 'Доступ закрыт.'; end if;
 select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('can_review',r.user_id<>actor.id and ((actor.role='admin' or actor.operations_director and academy_private.can_manage(r.user_id) or (actor.venue_director and academy_private.venue_scope(actor,r.restaurant_id) and exists(select 1 from public.academy_profiles m where m.id=r.user_id and academy_private.venue_scope(actor,m.restaurant_id) and m.role<>'admin' and not m.operations_director and not m.venue_director))) or (r.restaurant_id<>'network' and r.from_restaurant is distinct from 'network' and actor.role='manager' and not actor.venue_director and r.original_role='employee' and r.restaurant_id=actor.restaurant_id and r.department=actor.department))) order by r.created_at desc),'[]'::jsonb) into result
 from public.academy_work_changes r where r.user_id=actor.id or (actor.role='admin' or actor.operations_director and academy_private.can_manage(r.user_id) or (actor.venue_director and academy_private.venue_scope(actor,r.restaurant_id) and exists(select 1 from public.academy_profiles m where m.id=r.user_id and academy_private.venue_scope(actor,m.restaurant_id) and m.role<>'admin' and not m.operations_director and not m.venue_director))) or
 (r.restaurant_id<>'network' and r.from_restaurant is distinct from 'network' and actor.role='manager' and not actor.venue_director and r.original_role='employee' and r.restaurant_id=actor.restaurant_id and r.department=actor.department);
 return result;
end $function$;

do $$
declare uid uuid:=gen_random_uuid(); admin_id uuid:=gen_random_uuid(); owner_id uuid; req uuid; p public.academy_profiles; denied boolean;
begin
 select id into owner_id from public.academy_profiles where role='admin' and status='active' limit 1;
 insert into auth.users(id,aud,role,email) values(uid,'authenticated','authenticated','qa-network-'||uid||'@example.invalid'),(admin_id,'authenticated','authenticated','qa-network-'||admin_id||'@example.invalid');
 insert into public.academy_profiles(id,full_name,status,role,restaurant_id,department,position) values(admin_id,'QA local Admin','active','manager','minsk','Бар','Старший бармен') on conflict(id) do update set status='active',role='manager',restaurant_id='minsk',department='Бар',position='Старший бармен';
 perform set_config('request.jwt.claim.sub',uid::text,true);execute 'set local role authenticated';
 p:=public.academy_enroll('QA network','network','Руководитель','Управляющий');
 if p.status<>'pending' or p.role<>'employee' or p.operations_director or p.venue_director or p.restaurant_id<>'network' then raise exception 'Network enrollment widened access';end if;
 denied:=false;begin perform public.academy_enroll('QA network','network','Бар','Бармен');exception when others then denied:=true;end;if not denied then raise exception 'Network bartender allowed';end if;
 execute 'reset role';
 update public.academy_profiles set status='active',restaurant_id='minsk',department='Бар',position='Бармен' where id=uid;
 perform set_config('request.jwt.claim.sub',uid::text,true);execute 'set local role authenticated';req:=public.academy_request_work_change('network','Руководитель','Управляющий');execute 'reset role';
 if (select restaurant_id<>'minsk' from public.academy_profiles where id=uid) then raise exception 'Request immediately changed venue';end if;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);execute 'set local role authenticated';
 denied:=false;begin perform public.academy_assign_work(uid,'network','Руководитель','Управляющий');exception when others then denied:=true;end;if not denied then raise exception 'Local Admin assigned network affiliation';end if;
 denied:=false;begin perform public.academy_review_work_change(req,true);exception when others then denied:=true;end;if not denied then raise exception 'Local Admin approved network request';end if;
 execute 'reset role';perform set_config('request.jwt.claim.sub',owner_id::text,true);execute 'set local role authenticated';perform public.academy_review_work_change(req,true);execute 'reset role';
 select * into p from public.academy_profiles where id=uid;
 if p.restaurant_id<>'network' or p.department<>'Руководитель' or p.position<>'Управляющий' or p.role<>'employee' or p.operations_director or p.venue_director then raise exception 'Approval altered permissions';end if;
 perform set_config('request.jwt.claim.sub',uid::text,true);execute 'set local role authenticated';
 denied:=false;begin perform public.academy_save_content('{"id":"qa-network-denied","kind":"material","title":"QA denied","restaurant_id":"khimki","department":"Бар","payload":{}}',null);exception when others then denied:=true;end;if not denied then raise exception 'Affiliation granted global editing';end if;
 execute 'reset role';perform set_config('request.jwt.claim.sub',owner_id::text,true);execute 'set local role authenticated';perform public.academy_assign_work(uid,'minsk','Бар','Бармен');execute 'reset role';
 if (select restaurant_id<>'minsk' from public.academy_profiles where id=uid) then raise exception 'Return to a real venue failed';end if;
end $$;
rollback;
select 'PASS: network enrollment remains pending employee; only leadership allowed; request, local Admin denial, owner approval, unchanged roles and no global editing, return to venue. All fixtures rolled back.' result;
