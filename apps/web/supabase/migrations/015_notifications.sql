-- In-site notifications. No browser push, email, or external delivery.
begin;
create table academy_private.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.academy_profiles(id) on delete cascade,
 event_key text not null, category text not null, title text not null, body text not null default '', route text not null,
 scope text not null default 'own' check(scope in ('own','content','team','oral','work')),
 subject_id uuid references public.academy_profiles(id), content_ids text[] not null default '{}',
 created_at timestamptz not null default clock_timestamp(), read_at timestamptz,
 unique(user_id,event_key)
);
create index notifications_inbox on academy_private.notifications(user_id,created_at desc);
create table academy_private.notification_checks(user_id uuid primary key references public.academy_profiles(id) on delete cascade,checked_at timestamptz not null);
revoke all on academy_private.notifications,academy_private.notification_checks from public,anon,authenticated;

create function academy_private.notice_content_for(p public.academy_profiles,c public.academy_content) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce(p.status='active' and c.published
 and (c.restaurant_id is null or c.restaurant_id=p.restaurant_id)
 and (c.department is null or c.department=p.department)
 and (c.kind<>'menu' or c.payload->>'brand'=case when p.restaurant_id='minsk' then 'rvb' when p.restaurant_id in ('pushkino','khimki','mytishchi') then '90' end)
 and (c.kind<>'material' or coalesce(c.payload->>'brand','common') in ('common',case when p.restaurant_id='minsk' then 'rvb' else '90' end))
 and (not c.payload ? 'audiencePositions' or c.payload->'audiencePositions' ? p.position)
 and (not c.payload ? 'audienceLevels' or p.department='Руководитель' or c.payload->'audienceLevels' ? p.training_level)
 and (c.course_id is null or exists(select 1 from public.academy_content parent where parent.id=c.course_id and parent.published
 and (parent.restaurant_id is null or parent.restaurant_id=p.restaurant_id) and (parent.department is null or parent.department=p.department)
 and (not parent.payload ? 'audiencePositions' or parent.payload->'audiencePositions' ? p.position))),false)
$$;
create function academy_private.notice_visible(n academy_private.notifications,p public.academy_profiles) returns boolean
language sql stable security definer set search_path='' as $$
 select n.user_id=p.id and case n.scope when 'own' then true when 'content' then
 exists(select 1 from public.academy_content c where c.id=any(n.content_ids) and academy_private.notice_content_for(p,c))
 when 'team' then p.status='active' and exists(select 1 from public.academy_profiles m where m.id=n.subject_id and
 (p.role='admin' or p.role='manager' and m.role='employee' and p.restaurant_id=m.restaurant_id and p.department=m.department))
 when 'work' then p.status='active' and exists(select 1 from public.academy_work_changes r where r.id::text=split_part(n.event_key,':',2) and r.user_id<>p.id and
 (p.role='admin' or p.role='manager' and r.original_role='employee' and p.restaurant_id=r.restaurant_id and p.department=r.department))
 when 'oral' then p.status='active' and exists(select 1 from public.academy_profiles m where m.id=n.subject_id and
 (p.role='admin' or p.role='manager' and p.restaurant_id=m.restaurant_id and ((p.department='Кухня' and p.position='Шеф-повар') or (p.department='Бар' and p.position='Бар-менеджер'))))
 else false end
$$;
create function academy_private.emit_notice(p_user uuid,p_key text,p_category text,p_title text,p_body text,p_route text,p_scope text default 'own',p_subject uuid default null,p_ids text[] default '{}')
returns void language sql security definer set search_path='' as $$
 insert into academy_private.notifications(user_id,event_key,category,title,body,route,scope,subject_id,content_ids)
 values(p_user,p_key,p_category,left(p_title,200),left(p_body,4000),p_route,p_scope,p_subject,p_ids) on conflict(user_id,event_key) do nothing
$$;
create function academy_private.notify_team(p_subject uuid,p_key text,p_title text,p_body text,p_route text)
returns void language plpgsql security definer set search_path='' as $$
declare p public.academy_profiles; m public.academy_profiles;
begin
 select * into m from public.academy_profiles where id=p_subject;
 for p in select * from public.academy_profiles where status='active' and id<>p_subject and
 (role='admin' or role='manager' and m.role='employee' and restaurant_id=m.restaurant_id and department=m.department) loop
 perform academy_private.emit_notice(p.id,p_key,'team',p_title,p_body,p_route,'team',p_subject);end loop;
end $$;

create function public.academy_announce_content(p_content_ids text[],p_comment text default '') returns integer
language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles;c public.academy_content;first_c public.academy_content;p public.academy_profiles;
 ids text[];snapshot jsonb;key text;notice_title text;notice_body text;recipient_body text;notice_route text;sent integer:=0;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null or actor.role not in ('admin','manager') then raise exception 'Публиковать уведомления может только администратор.';end if;
 select array_agg(distinct x order by x) into ids from unnest(p_content_ids) x;
 if coalesce(array_length(ids,1),0) not between 1 and 30 or length(coalesce(p_comment,''))>1000 then raise exception 'Выберите от 1 до 30 позиций и комментарий до 1000 символов.';end if;
 select * into first_c from public.academy_content where id=ids[1];
 if (select count(*) from public.academy_content where id=any(ids))<>array_length(ids,1) then raise exception 'Материал недоступен.';end if;
 for c in select * from public.academy_content where id=any(ids) loop
 if not c.published or c.kind not in ('course','test','material','menu') or c.kind is distinct from first_c.kind
 or c.restaurant_id is distinct from first_c.restaurant_id or c.department is distinct from first_c.department
 or (c.kind<>'menu' and array_length(ids,1)>1)
 or (c.kind='menu' and (c.payload->>'brand' is distinct from first_c.payload->>'brand' or c.payload->>'menuSection' is distinct from first_c.payload->>'menuSection'))
 or not (actor.role='admin' or case when c.kind='menu' then c.restaurant_id=actor.restaurant_id and actor.department=case c.payload->>'menuSection' when 'kitchen' then 'Кухня' else 'Бар' end
 else academy_private.can_edit(c.restaurant_id,c.department) end) then raise exception 'Уведомлять можно только об опубликованных материалах своей области.';end if;
 end loop;
 select jsonb_agg(jsonb_build_object('id',d.id,'title',d.title,'payload',d.payload,'files',(select jsonb_agg(f.id order by f.id) from public.academy_material_files f where f.material_id=d.id and f.status='ready')) order by d.id) into snapshot from public.academy_content d where d.id=any(ids);
 key:='publication:'||md5(snapshot::text);
 notice_title:=case first_c.kind when 'course' then 'Курс опубликован: '||first_c.title when 'test' then 'Тест опубликован: '||first_c.title when 'material' then 'Новое в библиотеке: '||first_c.title else 'Обновление меню · '||case first_c.payload->>'brand' when 'rvb' then 'Руки Вверх Бар' else '90-е' end end;
 notice_body:=case when first_c.kind='menu' then (select string_agg(title,E'\n' order by title) from public.academy_content where id=any(ids)) else coalesce(first_c.payload->>'description','') end;
 if nullif(trim(p_comment),'') is not null then notice_body:=notice_body||E'\n'||trim(p_comment);end if;
 notice_route:=case first_c.kind when 'course' then '#/courses/'||first_c.id when 'test' then '#/tests/'||first_c.id when 'material' then '#/library/'||first_c.id else case when array_length(ids,1)=1 then '#/menu/'||first_c.id else '#/menu?brand='||(first_c.payload->>'brand')||'&section='||(first_c.payload->>'menuSection') end end;
 for p in select * from public.academy_profiles where status='active' and id<>actor.id loop
 if exists(select 1 from public.academy_content d where d.id=any(ids) and academy_private.notice_content_for(p,d)) then
 recipient_body:=notice_body;
 if first_c.kind in ('course','test') then recipient_body:=case coalesce(first_c.payload->'audiencePriorities'->>p.position,first_c.payload->>'priority',case first_c.kind when 'test' then 'attestation' else 'additional' end) when 'start' then 'Важно для начала работы' when 'attestation' then 'Аттестация' else 'Дополнительные знания' end||case when nullif(first_c.payload->>'dueAt','') is not null then E'\nСрок: '||left(first_c.payload->>'dueAt',10) else '' end||case when nullif(trim(p_comment),'') is not null then E'\n'||trim(p_comment) else '' end;end if;
 perform academy_private.emit_notice(p.id,key,'publication',notice_title,recipient_body,notice_route,'content',null,ids);sent:=sent+1;end if;end loop;
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'notification_publish',first_c.id,jsonb_build_object('ids',ids,'eligible',sent));return sent;
end $$;

create function public.academy_save_content_with_notice(p_document jsonb,p_keys jsonb default null,p_notify boolean default false,p_comment text default '') returns void language plpgsql security definer set search_path='' as $$
begin
 perform public.academy_save_content(p_document,p_keys);
 if p_notify and coalesce((p_document->>'published')::boolean,false) then perform public.academy_announce_content(array[p_document->>'id'],p_comment);end if;
end $$;
create function public.academy_save_menu_with_notice(p_document jsonb,p_notify boolean default false,p_comment text default '') returns void language plpgsql security definer set search_path='' as $$
begin
 perform public.academy_save_menu(p_document);
 if p_notify and coalesce((p_document->>'published')::boolean,false) then perform public.academy_announce_content(array[p_document->>'id'],p_comment);end if;
end $$;

create function academy_private.notification_profile_event() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
 if new.status='pending' then
 perform academy_private.emit_notice(new.id,'enrolled:'||new.id,'account','Заявка принята','Администратор проверит данные и откроет доступ к обучению.','#/profile');
 perform academy_private.notify_team(new.id,'enrollment:'||new.id,'Новая заявка сотрудника',new.full_name,'#/manager/members/'||new.id||'/profile');end if;
 else
 if new.status is distinct from old.status then
 perform academy_private.emit_notice(new.id,'access:'||new.status||':'||new.updated_at::text,'account',case new.status when 'active' then 'Доступ к обучению открыт' when 'suspended' then 'Доступ приостановлен' else 'Заявка ожидает подтверждения' end,'Подробности можно уточнить у администратора своего заведения.','#/profile');end if;
 if row(new.restaurant_id,new.department,new.position) is distinct from row(old.restaurant_id,old.department,old.position) then
 perform academy_private.emit_notice(new.id,'work:'||new.updated_at::text,'account','Рабочие данные изменены',coalesce(new.department,'')||' · '||coalesce(new.position,'')||E'\nЗаведение и актуальный учебный план доступны в профиле.','#/profile');end if;
 if new.position='Официант' and new.training_level='certified' and old.training_level is distinct from 'certified' then
 perform academy_private.emit_notice(new.id,'certified:'||new.restaurant_id||':'||new.updated_at::text,'attestation','Вы — аттестованный сотрудник','Сданы общая аттестация, кухня и бар.','#/profile');
 perform academy_private.notify_team(new.id,'certified:'||new.id||':'||new.updated_at::text,'Сотрудник прошёл три аттестации',new.full_name,'#/attestation/members/'||new.id);end if;
 end if;
 if new.status='active' and new.position='Официант' then perform academy_private.notify_readiness(new);end if;
 return null;
end $$;
create trigger academy_notification_profile after insert or update on public.academy_profiles for each row execute function academy_private.notification_profile_event();

create function academy_private.notification_work_event() returns trigger language plpgsql security definer set search_path='' as $$
declare p public.academy_profiles;
begin
 if tg_op='INSERT' then
 perform academy_private.emit_notice(new.user_id,'work-request:'||new.id,'account','Заявка на перевод отправлена',new.department||' · '||new.position,'#/profile');
 for p in select * from public.academy_profiles where status='active' and id<>new.user_id and (role='admin' or role='manager' and new.original_role='employee' and restaurant_id=new.restaurant_id and department=new.department) loop
 -- Receiving administrator can already read this request via academy_work_change_list.
 perform academy_private.emit_notice(p.id,'work-review:'||new.id,'work_review','Заявка на смену рабочих данных',new.full_name||' · '||new.position,'#/manager','work',new.user_id);end loop;
 elsif new.status is distinct from old.status then
 perform academy_private.emit_notice(new.user_id,'work-result:'||new.id||':'||new.status,'account',case new.status when 'approved' then 'Перевод подтверждён' when 'rejected' then 'Заявка на перевод отклонена' else 'Заявка на перевод отменена' end,new.department||' · '||new.position,'#/profile');end if;return null;
end $$;
create trigger academy_notification_work after insert or update on public.academy_work_changes for each row execute function academy_private.notification_work_event();

create function academy_private.notification_attempt_event() returns trigger language plpgsql security definer set search_path='' as $$
declare t text; m text;
begin
 select title into t from public.academy_content where id=new.test_id;
 if new.submitted_at is not null and old.submitted_at is null and new.needs_review then
 select full_name into m from public.academy_profiles where id=new.user_id;
 perform academy_private.notify_team(new.user_id,'review:'||new.id,'Письменный тест ждёт проверки',m||' · '||t,'#/manager');end if;
 if new.reviewed_at is not null and new.reviewed_at is distinct from old.reviewed_at then
 perform academy_private.emit_notice(new.user_id,'reviewed:'||new.id||':'||new.reviewed_at::text,'learning','Письменный ответ проверен',t||E'\n'||case when new.passed then 'Тест пройден.' else 'Повторите материал и попробуйте снова.' end||case when nullif(new.feedback,'') is not null then E'\n'||new.feedback else '' end,'#/tests/'||new.test_id||'/results/'||new.id);end if;return null;
end $$;
create trigger academy_notification_attempt after update on public.academy_attempts for each row execute function academy_private.notification_attempt_event();
create function academy_private.notification_oral_event() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform academy_private.emit_notice(new.employee_id,'oral:'||new.id,'attestation','Результат аттестации · '||case new.division when 'bar' then 'Бар' else 'Кухня' end,
 'Средний балл: '||round(new.average,2)::text||' / 10. '||case when new.passed then 'Сдано.' else 'Не сдано.' end||case when nullif(new.comment,'') is not null then E'\n'||new.comment else '' end,'#/profile');return null;
end $$;
create trigger academy_notification_oral after insert on public.academy_oral_assessments for each row execute function academy_private.notification_oral_event();

create function academy_private.notice_due(p text) returns timestamptz language plpgsql immutable set search_path='' as $$
begin return (p::date+1)::timestamp at time zone 'Europe/Minsk';exception when others then return null;end $$;
create function academy_private.notify_readiness(m public.academy_profiles) returns void language plpgsql security definer set search_path='' as $$
declare g jsonb;v_division text;recipient public.academy_profiles;
begin
 if m.status<>'active' or m.position<>'Официант' or m.restaurant_id is null then return;end if;
 g:=academy_private.general_training_status(m.id,m.restaurant_id,m.department,m.position);
 if not (g->>'passed')::boolean then return;end if;
 foreach v_division in array array['kitchen','bar'] loop
 if not coalesce((select a.passed from public.academy_oral_assessments a where a.employee_id=m.id and a.restaurant_id=m.restaurant_id and a.division=v_division order by a.created_at desc,a.id desc limit 1),false) then
 for recipient in select * from public.academy_profiles where status='active' and id<>m.id and
 (role='admin' or role='manager' and restaurant_id=m.restaurant_id and ((v_division='kitchen' and department='Кухня' and position='Шеф-повар') or (v_division='bar' and department='Бар' and position='Бар-менеджер'))) loop
 perform academy_private.emit_notice(recipient.id,'oral-ready:'||m.id||':'||m.restaurant_id||':'||v_division,'attestation','Сотрудник готов к аттестации · '||case v_division when 'bar' then 'Бар' else 'Кухня' end,m.full_name||' завершил обязательное обучение.','#/attestation/members/'||m.id||'?division='||v_division,'oral',m.id);end loop;end if;end loop;
end $$;
create function academy_private.refresh_notices(p public.academy_profiles) returns void language plpgsql security definer set search_path='' as $$
declare m public.academy_profiles; g jsonb; c jsonb;due timestamptz;names text:='';overdue integer:=0;v_division text;recipient public.academy_profiles;attempt record;request public.academy_work_changes;
begin
 if p.status<>'active' then return;end if;
 -- Each inbox refresh does this at most once per hour. No client-supplied recipients.
 insert into academy_private.notification_checks(user_id,checked_at) values(p.id,clock_timestamp()) on conflict(user_id) do update set checked_at=excluded.checked_at where academy_private.notification_checks.checked_at<now()-interval '1 hour';
 if not found then return;end if;
 g:=academy_private.general_training_status(p.id,p.restaurant_id,p.department,p.position);
 for c in select value from jsonb_array_elements(g->'courses') where not (value->>'complete')::boolean union all select value from jsonb_array_elements(g->'tests') where not (value->>'passed')::boolean loop
 select academy_private.notice_due(payload->>'dueAt') into due from public.academy_content where id=c->>'id';
 if due<=now()+interval '3 days' then names:=names||case when names='' then '' else E'\n' end||(c->>'title');end if;end loop;
 if names<>'' and not exists(select 1 from academy_private.notifications where user_id=p.id and category='reminder' and created_at>now()-interval '3 days') then
 perform academy_private.emit_notice(p.id,'reminder:'||floor(extract(epoch from now()))::text,'reminder','Обязательное обучение ждёт завершения',names,'#/courses');end if;
 if p.role in ('admin','manager') then
 for m in select * from public.academy_profiles where id<>p.id and (p.role='admin' or role='employee' and restaurant_id=p.restaurant_id and department=p.department) loop
 if m.status='pending' then perform academy_private.emit_notice(p.id,'enrollment:'||m.id,'team','Новая заявка сотрудника',m.full_name,'#/manager/members/'||m.id||'/profile','team',m.id);end if;
 if m.status='active' then
 for attempt in select a.id,t.title from public.academy_attempts a join public.academy_content t on t.id=a.test_id where a.user_id=m.id and a.needs_review and a.submitted_at is not null loop
 perform academy_private.emit_notice(p.id,'review:'||attempt.id,'team','Письменный тест ждёт проверки',m.full_name||' · '||attempt.title,'#/manager','team',m.id);end loop;
 g:=academy_private.general_training_status(m.id,m.restaurant_id,m.department,m.position);
 for c in select value from jsonb_array_elements(g->'courses') where not (value->>'complete')::boolean union all select value from jsonb_array_elements(g->'tests') where not (value->>'passed')::boolean loop
 select academy_private.notice_due(payload->>'dueAt') into due from public.academy_content where id=c->>'id';if due<now() then overdue:=overdue+1;end if;end loop;
 end if;end loop;
 if overdue>0 then perform academy_private.emit_notice(p.id,'overdue:'||(now() at time zone 'Europe/Minsk')::date::text,'digest','Сводка просроченного обучения','Незавершённых обязательных курсов и тестов со сроком: '||overdue||'. Откройте прогресс команды.','#/manager');end if;
 for request in select * from public.academy_work_changes where status='pending' and user_id<>p.id and (p.role='admin' or p.role='manager' and original_role='employee' and restaurant_id=p.restaurant_id and department=p.department) loop
 perform academy_private.emit_notice(p.id,'work-review:'||request.id,'work_review','Заявка на смену рабочих данных',request.full_name||' · '||request.position,'#/manager','work',request.user_id);end loop;
 end if;
 -- Readiness is based on the current mandatory curriculum, never on menu marks.
 for m in select * from public.academy_profiles where status='active' and position='Официант' and restaurant_id is not null and
 (p.id=id or p.role='admin' or p.role='manager' and restaurant_id=p.restaurant_id) loop
 g:=academy_private.general_training_status(m.id,m.restaurant_id,m.department,m.position);
 if (g->>'passed')::boolean then
 foreach v_division in array array['kitchen','bar'] loop
 if not coalesce((select a.passed from public.academy_oral_assessments a where a.employee_id=m.id and a.restaurant_id=m.restaurant_id and a.division=v_division order by a.created_at desc,a.id desc limit 1),false) then
 for recipient in select * from public.academy_profiles where status='active' and id<>m.id and
 (role='admin' or role='manager' and restaurant_id=m.restaurant_id and ((v_division='kitchen' and department='Кухня' and position='Шеф-повар') or (v_division='bar' and department='Бар' and position='Бар-менеджер'))) loop
 perform academy_private.emit_notice(recipient.id,'oral-ready:'||m.id||':'||m.restaurant_id||':'||v_division,'attestation','Сотрудник готов к аттестации · '||case v_division when 'bar' then 'Бар' else 'Кухня' end,m.full_name||' завершил обязательное обучение.','#/attestation/members/'||m.id||'?division='||v_division,'oral',m.id);end loop;end if;end loop;end if;end loop;
end $$;

create function academy_private.run_notification_digest() returns void language plpgsql security definer set search_path='' as $$
declare p public.academy_profiles;
begin for p in select * from public.academy_profiles where status='active' loop perform academy_private.refresh_notices(p);end loop;end $$;
-- Supabase's database scheduler sends in-site reminders even when nobody has the site open.
create extension if not exists pg_cron;
select cron.schedule('academy-notifications-hourly','0 * * * *','select academy_private.run_notification_digest()');

create function public.academy_notifications(p_limit integer default 30,p_unread boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.academy_profiles;r jsonb;
begin
 select * into p from public.academy_profiles where id=auth.uid();if p.id is null then raise exception 'Войдите в аккаунт.';end if;
 perform academy_private.refresh_notices(p);
 select jsonb_build_object('as_of',clock_timestamp(),'unread',(select count(*) from academy_private.notifications n where n.read_at is null and academy_private.notice_visible(n,p)),
 'total',(select count(*) from academy_private.notifications n where academy_private.notice_visible(n,p) and (not p_unread or n.read_at is null)),
 'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc) from
 (select n.id,n.category,n.title,n.body,n.route,n.created_at,n.read_at,
 coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'title',c.title,'kind',c.kind) order by c.title) from public.academy_content c where c.id=any(n.content_ids) and academy_private.notice_content_for(p,c)),'[]'::jsonb) as targets
 from academy_private.notifications n where academy_private.notice_visible(n,p) and (not p_unread or n.read_at is null) order by n.created_at desc,n.id desc limit greatest(1,least(coalesce(p_limit,30),200))) x),'[]'::jsonb)) into r;return r;
end $$;
create function public.academy_read_notifications(p_id uuid default null,p_through timestamptz default null) returns void language plpgsql security definer set search_path='' as $$
declare p public.academy_profiles;
begin
 select * into p from public.academy_profiles where id=auth.uid();if p.id is null then raise exception 'Войдите в аккаунт.';end if;
 if p_id is null and p_through is null then raise exception 'Выберите уведомление.';end if;
 update academy_private.notifications n set read_at=clock_timestamp() where n.read_at is null and academy_private.notice_visible(n,p) and
 ((p_id is not null and n.id=p_id) or (p_id is null and n.created_at<=least(p_through,clock_timestamp())));
end $$;
-- Keep previously granted private RLS helper permissions; new helpers are callable only by definer RPCs/triggers.
revoke all on function academy_private.notice_content_for(public.academy_profiles,public.academy_content),academy_private.notice_visible(academy_private.notifications,public.academy_profiles),academy_private.emit_notice(uuid,text,text,text,text,text,text,uuid,text[]),academy_private.notify_team(uuid,text,text,text,text),academy_private.notification_profile_event(),academy_private.notification_work_event(),academy_private.notification_attempt_event(),academy_private.notification_oral_event(),academy_private.notice_due(text),academy_private.refresh_notices(public.academy_profiles),academy_private.notify_readiness(public.academy_profiles),academy_private.run_notification_digest() from public,anon,authenticated;
revoke all on function public.academy_notifications(integer,boolean),public.academy_read_notifications(uuid,timestamptz),public.academy_announce_content(text[],text),public.academy_save_content_with_notice(jsonb,jsonb,boolean,text),public.academy_save_menu_with_notice(jsonb,boolean,text) from public,anon;
grant execute on function public.academy_notifications(integer,boolean),public.academy_read_notifications(uuid,timestamptz),public.academy_announce_content(text[],text),public.academy_save_content_with_notice(jsonb,jsonb,boolean,text),public.academy_save_menu_with_notice(jsonb,boolean,text) to authenticated;
insert into academy_private.notifications(user_id,event_key,category,title,body,route)
select id,'notifications-launched:v1','account','Уведомления теперь в академии',
 'Здесь будут новые курсы, изменения меню, файлы библиотеки и результаты обучения. Нажмите на колокольчик, чтобы открыть ленту.','#/notifications'
from public.academy_profiles where status='active' on conflict(user_id,event_key) do nothing;
commit;
