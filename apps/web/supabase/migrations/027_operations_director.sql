-- Explicit operations access. A job title alone never grants these permissions.
begin;
alter table public.academy_profiles add column if not exists operations_director boolean not null default false;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='academy_operations_identity' and conrelid='public.academy_profiles'::regclass) then
  alter table public.academy_profiles add constraint academy_operations_identity check(not operations_director or coalesce(role='manager' and department='Руководитель' and position='Операционный директор' and restaurant_id is null,false));
 end if;
end $$;
create or replace function academy_private.is_operations_director(p_user uuid default auth.uid()) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_profiles where id=p_user and status='active' and role='manager' and operations_director)
$$;
revoke all on function academy_private.is_operations_director(uuid) from public,anon;
grant execute on function academy_private.is_operations_director(uuid) to authenticated;
create or replace function academy_private.can_manage(p_user_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_profiles a join public.academy_profiles b on b.id=p_user_id
 where a.id=auth.uid() and a.status='active' and (a.role='admin' or (a.operations_director and b.role<>'admin' and not b.operations_director and b.id<>a.id) or (a.role='manager' and a.restaurant_id=b.restaurant_id and a.department=b.department and b.role='employee')))
$$;

create or replace function academy_private.can_edit(p_restaurant text,p_department text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_profiles a where a.id=auth.uid() and a.status='active' and
 (a.role='admin' or a.operations_director or (a.role='manager' and p_restaurant=a.restaurant_id and p_department=a.department)))
$$;

create or replace function academy_private.can_edit_menu_for(a public.academy_profiles,c public.academy_content) returns boolean
language sql stable set search_path='' as $$
 select coalesce(a.status='active' and c.kind='menu' and (a.role='admin' or a.operations_director or
 (a.role='manager' and a.restaurant_id is not null
 and a.department=case c.payload->>'menuSection' when 'bar' then 'Бар' when 'kitchen' then 'Кухня' end
 and (c.department is null or c.department=a.department)
 and (c.restaurant_id=a.restaurant_id or
 (c.restaurant_id is null and c.department is null and c.payload->>'brand'='90' and c.payload->>'menuSection' in ('bar','kitchen')
 and a.restaurant_id in ('pushkino','khimki','mytishchi'))))),false)
$$;

create or replace function academy_private.can_read_content(p_id text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_content c join public.academy_profiles p on p.id=auth.uid()
 where c.id=p_id and p.status='active' and case when c.id='rvb-bar-handbook'
 then academy_private.can_read_bar_handbook(p,c)
 else ((c.published and (c.restaurant_id is null or c.restaurant_id=p.restaurant_id) and (c.department is null or c.department=p.department))
 or p.role='admin' or p.operations_director or (p.role='manager' and c.restaurant_id=p.restaurant_id and c.department=p.department)
 or (c.kind='menu' and academy_private.can_edit_menu_for(p,c))) end)
$$;

create or replace function academy_private.can_read_bar_handbook(p public.academy_profiles,c public.academy_content)
returns boolean language sql stable set search_path='' as $$
 select coalesce(p.status='active' and (p.role='admin' or p.operations_director or
 ((c.published or p.role='manager' and p.restaurant_id='minsk' and p.department='Бар') and
 (p.department='Руководитель' or p.restaurant_id='minsk' and p.department='Бар'))),false)
$$;

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
 if actor.role='manager' and not actor.operations_director then
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

create or replace function public.academy_ranking() returns jsonb
language sql stable security definer set search_path='' as $$
 with actor as (
 select * from public.academy_profiles where id=auth.uid() and status='active'
 ), visible as (
 select p.* from public.academy_profiles p cross join actor a where p.status='active' and
 (a.role='admin' or a.operations_director or (a.role='manager' and p.restaurant_id=a.restaurant_id and p.department=a.department)
 or (a.role='employee' and p.restaurant_id=a.restaurant_id))
 ), best as (
 select a.user_id,a.test_id,max(a.score::numeric/nullif(a.total,0)) filter(where not a.needs_review) as fraction,
 bool_or(a.passed) as passed from public.academy_attempts a join visible p on p.id=a.user_id
 where a.submitted_at is not null and (coalesce((a.snapshot->>'timeLimitSeconds')::integer,0)=0
 or a.submitted_at<=a.started_at+make_interval(secs=>(a.snapshot->>'timeLimitSeconds')::integer+10))
 group by a.user_id,a.test_id
 ), scores as (
 select user_id,round(avg(fraction)*100,1) as average_score,count(*) as tests_attempted,count(*) filter(where passed) as tests_passed
 from best group by user_id
 ), lessons as (
 select p.user_id,count(*) as lessons_completed from public.academy_progress p join visible v on v.id=p.user_id group by p.user_id
 ), marks as (
 select m.user_id,count(*) filter(where m.status='learned') as menu_learned,count(*) filter(where m.status='repeat') as menu_repeat
 from public.academy_menu_marks m join visible v on v.id=m.user_id group by m.user_id
 )
 select coalesce(jsonb_agg(jsonb_build_object('user_id',p.id,'full_name',p.full_name,'restaurant_id',p.restaurant_id,
 'department',p.department,'position',p.position,'average_score',s.average_score,
 'tests_attempted',coalesce(s.tests_attempted,0),'tests_passed',coalesce(s.tests_passed,0),
 'lessons_completed',coalesce(l.lessons_completed,0),'menu_learned',coalesce(m.menu_learned,0),'menu_repeat',coalesce(m.menu_repeat,0))
 order by s.average_score desc nulls last,coalesce(s.tests_passed,0) desc,p.full_name),'[]'::jsonb)
 from visible p left join scores s on s.user_id=p.id left join lessons l on l.user_id=p.id left join marks m on m.user_id=p.id
$$;

create or replace function public.academy_oral_data(p_all boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; viewer boolean; result jsonb;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null then raise exception 'Доступ закрыт.';end if;
 viewer:=academy_private.can_view_oral();
 select jsonb_build_object(
 'viewer',viewer,
 'members',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'restaurant_id',p.restaurant_id,'department',p.department,'position',p.position,'training_level',p.training_level,'general',academy_private.general_training_status(p.id,p.restaurant_id,p.department,p.position),'can_grade_kitchen',academy_private.can_grade_oral(p.restaurant_id,'kitchen') and p.id<>actor.id,'can_grade_bar',academy_private.can_grade_oral(p.restaurant_id,'bar') and p.id<>actor.id) order by p.full_name) from public.academy_profiles p where p.status='active' and (p.id=actor.id or viewer and p_all and (actor.role='admin' or actor.operations_director or p.restaurant_id=actor.restaurant_id))),'[]'::jsonb),
 'assessments',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc,a.id desc) from public.academy_oral_assessments a where a.employee_id=actor.id or viewer and p_all and (actor.role='admin' or actor.operations_director or a.restaurant_id=actor.restaurant_id and exists(select 1 from public.academy_profiles p where p.id=a.employee_id and p.restaurant_id=actor.restaurant_id))),'[]'::jsonb)) into result;
 return result;
end $$;

create or replace function public.academy_work_change_list() returns jsonb language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; result jsonb;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null then raise exception 'Доступ закрыт.'; end if;
 select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('can_review',r.user_id<>actor.id and ((actor.role='admin' or actor.operations_director and academy_private.can_manage(r.user_id)) or (actor.role='manager' and r.original_role='employee' and r.restaurant_id=actor.restaurant_id and r.department=actor.department))) order by r.created_at desc),'[]'::jsonb) into result
 from public.academy_work_changes r where r.user_id=actor.id or (actor.role='admin' or actor.operations_director and academy_private.can_manage(r.user_id)) or
 (actor.role='manager' and r.original_role='employee' and r.restaurant_id=actor.restaurant_id and r.department=actor.department);
 return result;
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
 if member.id=actor.id or not(actor.role='admin' or actor.operations_director and academy_private.can_manage(member.id) or (actor.role='manager' and member.role='employee' and request.original_role='employee' and actor.restaurant_id=request.restaurant_id and actor.department=request.department)) then raise exception 'Подтверждение доступно администратору принимающей команды или владельцу.'; end if;
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
 if actor.id is null or member.id is null or not academy_private.can_manage(p_user_id) or (actor.role<>'admin' and not actor.operations_director and (member.id=actor.id or member.role<>'employee')) then raise exception 'Можно менять только рабочие данные сотрудников своей команды.'; end if;
 if not academy_private.valid_work(p_restaurant_id,p_department,p_position) then raise exception 'Проверьте заведение, подразделение и должность.'; end if;
 update public.academy_profiles set restaurant_id=p_restaurant_id,department=p_department,position=p_position,updated_at=now() where id=member.id;
 update public.academy_work_changes set status='cancelled',reviewed_at=now(),reviewed_by=actor.id where user_id=member.id and status='pending';
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'assign_work',member.id::text,jsonb_build_object('from',jsonb_build_object('restaurant',member.restaurant_id,'department',member.department,'position',member.position),'to',jsonb_build_object('restaurant',p_restaurant_id,'department',p_department,'position',p_position)));
end $$;

create or replace function academy_private.notice_visible(n academy_private.notifications,p public.academy_profiles) returns boolean
language sql stable security definer set search_path='' as $$
 select n.user_id=p.id and case n.scope when 'own' then true when 'content' then
 exists(select 1 from public.academy_content c where c.id=any(n.content_ids) and academy_private.notice_content_for(p,c))
 when 'team' then p.status='active' and exists(select 1 from public.academy_profiles m where m.id=n.subject_id and
 (p.role='admin' or p.operations_director or p.role='manager' and m.role='employee' and p.restaurant_id=m.restaurant_id and p.department=m.department))
 when 'work' then p.status='active' and exists(select 1 from public.academy_work_changes r where r.id::text=split_part(n.event_key,':',2) and r.user_id<>p.id and
 (p.role='admin' or p.operations_director or p.role='manager' and r.original_role='employee' and p.restaurant_id=r.restaurant_id and p.department=r.department))
 when 'oral' then p.status='active' and exists(select 1 from public.academy_profiles m where m.id=n.subject_id and
 (p.role='admin' or p.operations_director or p.role='manager' and p.restaurant_id=m.restaurant_id and ((p.department='Кухня' and p.position='Шеф-повар') or (p.department='Бар' and p.position='Бар-менеджер'))))
 else false end
$$;

create or replace function academy_private.notify_team(p_subject uuid,p_key text,p_title text,p_body text,p_route text)
returns void language plpgsql security definer set search_path='' as $$
declare p public.academy_profiles; m public.academy_profiles;
begin
 select * into m from public.academy_profiles where id=p_subject;
 for p in select * from public.academy_profiles where status='active' and id<>p_subject and
 (role='admin' or (operations_director and m.role<>'admin' and not m.operations_director) or role='manager' and m.role='employee' and restaurant_id=m.restaurant_id and department=m.department) loop
 perform academy_private.emit_notice(p.id,p_key,'team',p_title,p_body,p_route,'team',p_subject);end loop;
end $$;

create or replace function academy_private.notice_content_for(p public.academy_profiles,c public.academy_content) returns boolean
language sql stable security definer set search_path='' as $$
 select case when academy_private.is_operations_director(p.id) then c.published else coalesce(p.status='active' and c.published
 and (c.restaurant_id is null or c.restaurant_id=p.restaurant_id)
 and (c.department is null or c.department=p.department)
 and (c.kind<>'menu' or c.payload->>'brand'=case when p.restaurant_id='minsk' then 'rvb' when p.restaurant_id in ('pushkino','khimki','mytishchi') then '90' end)
 and (c.kind<>'material' or coalesce(c.payload->>'brand','common') in ('common',case when p.restaurant_id='minsk' then 'rvb' else '90' end))
 and (not c.payload ? 'audiencePositions' or c.payload->'audiencePositions' ? p.position)
 and (not c.payload ? 'audienceLevels' or p.department='Руководитель' or c.payload->'audienceLevels' ? p.training_level)
 and (c.course_id is null or exists(select 1 from public.academy_content parent where parent.id=c.course_id and parent.published
 and (parent.restaurant_id is null or parent.restaurant_id=p.restaurant_id) and (parent.department is null or parent.department=p.department)
 and (not parent.payload ? 'audiencePositions' or parent.payload->'audiencePositions' ? p.position))),false) end
$$;

create or replace function academy_private.valid_work(p_restaurant text,p_department text,p_position text)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(p_restaurant in ('minsk','pushkino','khimki','mytishchi') and (
 (p_department='Зал' and p_position in ('Официант','Администратор','Хостес')) or
 (p_department='Бар' and p_position in ('Старший бармен','Барбэк','Бармен','Бар-менеджер')) or
 (p_department='Кухня' and p_position in ('Сотрудник кухни','Шеф-повар')) or
 (p_department='Арт' and p_position='Сотрудник арт') or
 (p_department='Кальян' and p_position='Сотрудник кальянного подразделения') or
 (p_department='Руководитель' and p_position in ('Руководитель','Управляющий','Операционный директор'))),false)
$$;
create or replace function public.academy_manage_member(p_user_id uuid,p_status text,p_role text default 'employee') returns void language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; member public.academy_profiles;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 select * into member from public.academy_profiles where id=p_user_id for update;
 if actor.id is null or member.id is null or not academy_private.can_manage(p_user_id) or p_user_id=auth.uid() then raise exception 'Forbidden';end if;
 if p_status is null or p_status not in ('pending','active','suspended') or p_role is null or p_role not in ('employee','manager','admin') then raise exception 'Invalid status or role';end if;
 if actor.role<>'admin' and (p_role='admin' or not actor.operations_director and p_role<>'employee') then raise exception 'Назначать владельцев может только владелец академии.';end if;
 update public.academy_profiles set status=p_status,role=p_role,operations_director=case when p_role='manager' then operations_director else false end,updated_at=now() where id=p_user_id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'member',p_user_id::text,jsonb_build_object('status',p_status,'role',p_role));
end $$;
create or replace function public.academy_set_operations_director(p_user_id uuid,p_enabled boolean) returns public.academy_profiles language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; member public.academy_profiles; result public.academy_profiles;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active' and role='admin';
 if actor.id is null then raise exception 'Этот доступ назначает только владелец академии.' using errcode='42501';end if;
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
revoke all on function public.academy_set_operations_director(uuid,boolean) from public,anon;
grant execute on function public.academy_set_operations_director(uuid,boolean) to authenticated;
commit;
