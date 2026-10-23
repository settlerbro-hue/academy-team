begin;
alter table public.academy_profiles add column if not exists avatar_data text;
alter table public.academy_profiles add column if not exists birth_date date;
alter table public.academy_profiles add column if not exists gender text;
alter table public.academy_profiles add column if not exists team_joined_on date;

create or replace function public.academy_update_profile(p_user_id uuid,p_full_name text,p_birth_date date default null,p_gender text default null,p_team_joined_on date default null,p_avatar_data text default null)
returns public.academy_profiles language plpgsql security definer set search_path='' as $$
declare result public.academy_profiles;
begin
 if not academy_private.is_active() or not (p_user_id=auth.uid() or academy_private.can_manage(p_user_id)) then raise exception 'Forbidden'; end if;
 if length(trim(p_full_name)) not between 2 and 100 then raise exception 'Укажите имя и фамилию (2–100 символов).'; end if;
 if p_birth_date>current_date or p_birth_date<date '1900-01-01' then raise exception 'Проверьте дату рождения.'; end if;
 if p_gender is not null and p_gender not in ('female','male','unspecified') then raise exception 'Проверьте значение пола.'; end if;
 if p_team_joined_on>current_date or p_team_joined_on<date '1900-01-01' then raise exception 'Проверьте дату вступления.'; end if;
 if p_avatar_data is not null and (length(p_avatar_data)>180000 or p_avatar_data !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$') then raise exception 'Выберите фото JPG, PNG или WebP.'; end if;
 update public.academy_profiles set full_name=trim(p_full_name),birth_date=p_birth_date,gender=p_gender,
 team_joined_on=p_team_joined_on,avatar_data=p_avatar_data,updated_at=now() where id=p_user_id returning * into result;
 if result.id is null then raise exception 'Профиль не найден.'; end if;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'update_profile',p_user_id::text,'{"fields":["full_name","birth_date","gender","team_joined_on","avatar_data"]}'::jsonb);
 return result;
end $$;
revoke all on function public.academy_update_profile(uuid,text,date,text,date,text) from public,anon;
grant execute on function public.academy_update_profile(uuid,text,date,text,date,text) to authenticated;

create or replace function public.academy_set_priority(p_content_id text,p_priority text,p_lesson_id text default null)
returns void language plpgsql security definer set search_path='' as $$
declare c public.academy_content; updated_payload jsonb;
begin
 select * into c from public.academy_content where id=p_content_id for update;
 if c.id is null or c.kind not in ('course','test') or not academy_private.can_edit(c.restaurant_id,c.department) then raise exception 'Forbidden'; end if;
 if p_priority not in ('start','attestation','additional') then raise exception 'Неверный приоритет.'; end if;
 if p_lesson_id is null then updated_payload=jsonb_set(c.payload,'{priority}',to_jsonb(p_priority));
 else
  if not exists(select 1 from jsonb_array_elements(c.payload->'lessons') l where l->>'id'=p_lesson_id) then raise exception 'Урок не найден.'; end if;
  updated_payload=jsonb_set(c.payload,'{lessons}',(select jsonb_agg(case when l->>'id'=p_lesson_id then jsonb_set(l,'{priority}',to_jsonb(p_priority)) else l end order by n) from jsonb_array_elements(c.payload->'lessons') with ordinality a(l,n)));
 end if;
 update public.academy_content set payload=updated_payload,updated_at=now() where id=c.id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'set_priority',c.id,jsonb_build_object('priority',p_priority,'lesson_id',p_lesson_id));
end $$;
revoke all on function public.academy_set_priority(text,text,text) from public,anon;
grant execute on function public.academy_set_priority(text,text,text) to authenticated;

-- Initial priorities can be changed individually by an authorized editor.
update public.academy_content set payload=jsonb_set(payload,'{priority}',to_jsonb(case
 when kind='test' then 'attestation'
 when id in ('welcome-90','waiter-standards','hostess-standards','waiter-internship','guru-43403','guru-42932') then 'start'
 when id in ('guru-50011','guru-50012','guru-51132') then 'attestation'
 else 'additional' end::text)) where kind in ('course','test') and not payload ? 'priority';
commit;
