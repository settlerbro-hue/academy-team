begin;
alter table public.academy_profiles add column if not exists training_level text check(training_level in ('trainee','certified'));
create or replace function academy_private.normalize_training_level() returns trigger language plpgsql set search_path='' as $$
begin
 if new.department='Руководитель' or new.department is null then new.training_level:=null;
 elsif new.training_level is null then new.training_level:='trainee';end if;
 return new;
end $$;
revoke all on function academy_private.normalize_training_level() from public,anon,authenticated;
drop trigger if exists academy_profile_training_level on public.academy_profiles;
create trigger academy_profile_training_level before insert or update on public.academy_profiles for each row execute function academy_private.normalize_training_level();
update public.academy_profiles set training_level=case when department='Руководитель' or department is null then null else coalesce(training_level,'trainee') end;
create or replace function public.academy_set_training_level(p_user_id uuid,p_level text) returns void language plpgsql security definer set search_path='' as $$
declare member public.academy_profiles;
begin
 select * into member from public.academy_profiles where id=p_user_id for update;
 if member.id is null or not academy_private.can_manage(p_user_id) then raise exception 'Можно менять уровень только сотрудников своей команды.';end if;
 if member.department='Руководитель' or member.department is null or p_level is null or p_level not in ('trainee','certified') then raise exception 'Уровень подготовки не применяется к руководителям. Выберите стажёра или аттестованного сотрудника.';end if;
 update public.academy_profiles set training_level=p_level,updated_at=now() where id=p_user_id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'training_level',p_user_id::text,jsonb_build_object('from',member.training_level,'to',p_level));
end $$;
create or replace function public.academy_set_course_audience(p_content_id text,p_positions jsonb,p_levels jsonb,p_priorities jsonb) returns void language plpgsql security definer set search_path='' as $$
declare c public.academy_content; allowed text[]:=array['Официант','Администратор','Хостес','Старший бармен','Барбэк','Бармен','Сотрудник кухни','Сотрудник арт','Сотрудник кальянного подразделения','Руководитель','Управляющий'];
begin
 select * into c from public.academy_content where id=p_content_id for update;
 if c.id is null or c.kind<>'course' or not academy_private.can_edit(c.restaurant_id,c.department) then raise exception 'Недостаточно прав для настройки курса.';end if;
 if jsonb_typeof(p_positions) is distinct from 'array' or jsonb_typeof(p_levels) is distinct from 'array' or jsonb_typeof(p_priorities) is distinct from 'object' then raise exception 'Проверьте категории курса.';end if;
 if jsonb_array_length(p_positions) not between 1 and 11 or exists(select 1 from jsonb_array_elements_text(p_positions) x where x is null or not x=any(allowed)) or (select count(*) from jsonb_array_elements_text(p_positions))<>(select count(distinct x) from jsonb_array_elements_text(p_positions) x) then raise exception 'Выберите хотя бы одну должность без повторов.';end if;
 if jsonb_array_length(p_levels) not between 1 and 2 or exists(select 1 from jsonb_array_elements_text(p_levels) x where x is null or x not in ('trainee','certified')) then raise exception 'Выберите уровень подготовки.';end if;
 if exists(select 1 from jsonb_each_text(p_priorities) x where not p_positions ? x.key or x.value is null or x.value not in ('start','attestation','additional')) then raise exception 'Проверьте приоритеты должностей.';end if;
 update public.academy_content set payload=payload||jsonb_build_object('audiencePositions',p_positions,'audienceLevels',p_levels,'audiencePriorities',p_priorities),updated_at=now() where id=c.id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'course_audience',c.id,jsonb_build_object('positions',p_positions,'levels',p_levels,'priorities',p_priorities));
end $$;
revoke all on function public.academy_set_training_level(uuid,text),public.academy_set_course_audience(text,jsonb,jsonb,jsonb) from public,anon;
grant execute on function public.academy_set_training_level(uuid,text),public.academy_set_course_audience(text,jsonb,jsonb,jsonb) to authenticated;
-- Assign relevant audiences once; further changes are preserved.
update public.academy_content set payload=payload||jsonb_build_object(
 'audiencePositions',to_jsonb(case
 when id='waiter-internship' then array['Официант']
 when id='waiter-standards' or id='guru-25724' then array['Официант','Администратор']
 when id='hostess-standards' then array['Хостес','Администратор']
 when id in ('guru-42932','guru-43399','guru-25811') then array['Администратор','Старший бармен','Руководитель','Управляющий']
 when id in ('guru-50011','guru-51132','guru-44607','guru-36651') then array['Бармен','Старший бармен','Барбэк','Официант','Администратор']
 when id in ('guru-50012','guru-44033') then array['Сотрудник кухни','Официант','Администратор','Хостес']
 when id in ('guru-44663','guru-44662') then array['Официант','Администратор','Хостес','Бармен','Старший бармен']
 else array['Официант','Администратор','Хостес','Старший бармен','Барбэк','Бармен','Сотрудник кухни','Сотрудник арт','Сотрудник кальянного подразделения','Руководитель','Управляющий'] end),
 'audienceLevels',case when id='waiter-internship' then '["trainee"]'::jsonb else '["trainee","certified"]'::jsonb end,'audiencePriorities','{}'::jsonb)
where kind='course' and not payload ? 'audiencePositions';
commit;
select count(*) as courses_categorized from public.academy_content where kind='course' and payload ? 'audiencePositions';

