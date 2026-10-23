begin;
create table if not exists public.academy_oral_assessments (
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.academy_profiles(id),
 employee_name text not null,employee_position text not null,restaurant_id text not null,
 division text not null check(division in ('kitchen','bar')),scores jsonb not null,
 category_count integer not null check(category_count between 1 and 100),score_total integer not null check(score_total between category_count and category_count*10),
 average numeric generated always as (score_total::numeric/category_count) stored,
 passed boolean generated always as (score_total>=category_count*8) stored,
 examiner_id uuid not null references public.academy_profiles(id),examiner_name text not null,comment text not null default '',
 created_at timestamptz not null default clock_timestamp()
);
create index if not exists academy_oral_employee_scope on public.academy_oral_assessments(employee_id,restaurant_id,division,created_at desc,id desc);
alter table public.academy_oral_assessments enable row level security;
revoke all on public.academy_oral_assessments from public,anon,authenticated;
create or replace function academy_private.can_view_oral() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_profiles p where p.id=auth.uid() and p.status='active' and (p.role in ('admin','manager') or p.department='Руководитель'))
$$;
create or replace function academy_private.can_grade_oral(p_restaurant text,p_division text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_profiles p where p.id=auth.uid() and p.status='active' and (p.role='admin' or (p.role='manager' and p.restaurant_id=p_restaurant and ((p_division='kitchen' and p.department='Кухня' and p.position='Шеф-повар') or (p_division='bar' and p.department='Бар' and p.position='Бар-менеджер')))))
$$;
create or replace function academy_private.waiter_is_certified(p_user uuid,p_restaurant text) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select passed from public.academy_oral_assessments where employee_id=p_user and restaurant_id=p_restaurant and division='kitchen' order by created_at desc,id desc limit 1),false)
 and coalesce((select passed from public.academy_oral_assessments where employee_id=p_user and restaurant_id=p_restaurant and division='bar' order by created_at desc,id desc limit 1),false)
$$;
revoke all on function academy_private.can_view_oral(),academy_private.can_grade_oral(text,text),academy_private.waiter_is_certified(uuid,text) from public,anon,authenticated;
create or replace function academy_private.normalize_training_level() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.department='Руководитель' or new.department is null then new.training_level:=null;
 elsif new.position='Официант' then new.training_level:=case when academy_private.waiter_is_certified(new.id,new.restaurant_id) then 'certified' else 'trainee' end;
 elsif new.training_level is null then new.training_level:='trainee';end if;
 return new;
end $$;
create or replace function public.academy_set_training_level(p_user_id uuid,p_level text) returns void language plpgsql security definer set search_path='' as $$
declare member public.academy_profiles;
begin
 select * into member from public.academy_profiles where id=p_user_id for update;
 if member.id is null or not academy_private.can_manage(p_user_id) then raise exception 'Можно менять уровень только сотрудников своей команды.';end if;
 if member.position='Официант' then raise exception 'Уровень официанта определяется сдачей кухни и бара.';end if;
 if member.department='Руководитель' or member.department is null or p_level is null or p_level not in ('trainee','certified') then raise exception 'Выберите стажёра или аттестованного сотрудника.';end if;
 update public.academy_profiles set training_level=p_level,updated_at=now() where id=p_user_id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'training_level',p_user_id::text,jsonb_build_object('from',member.training_level,'to',p_level));
end $$;
create or replace function public.academy_oral_data(p_all boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; viewer boolean; result jsonb;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null then raise exception 'Доступ закрыт.';end if;
 viewer:=academy_private.can_view_oral();
 select jsonb_build_object(
 'viewer',viewer,
 'members',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'restaurant_id',p.restaurant_id,'department',p.department,'position',p.position,'training_level',p.training_level,'can_grade_kitchen',academy_private.can_grade_oral(p.restaurant_id,'kitchen') and p.id<>actor.id,'can_grade_bar',academy_private.can_grade_oral(p.restaurant_id,'bar') and p.id<>actor.id) order by p.full_name) from public.academy_profiles p where p.status='active' and (p.id=actor.id or viewer and p_all and (actor.role='admin' or p.restaurant_id=actor.restaurant_id))),'[]'::jsonb),
 'assessments',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc,a.id desc) from public.academy_oral_assessments a where a.employee_id=actor.id or viewer and p_all and (actor.role='admin' or a.restaurant_id=actor.restaurant_id and exists(select 1 from public.academy_profiles p where p.id=a.employee_id and p.restaurant_id=actor.restaurant_id))),'[]'::jsonb)) into result;
 return result;
end $$;
create or replace function public.academy_save_kitchen_oral(p_employee_id uuid,p_restaurant_id text,p_scores jsonb,p_comment text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare member public.academy_profiles; actor public.academy_profiles; total integer; assessment_id uuid;keys text[]:=array['hot','cold','allergens','sauces','pizza','general'];
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 select * into member from public.academy_profiles where id=p_employee_id for update;
 if actor.id is null or member.id is null or member.status<>'active' or member.restaurant_id is null or member.id=actor.id or not academy_private.can_grade_oral(member.restaurant_id,'kitchen') then raise exception 'Оценки кухни выставляет шеф-повар своего заведения или владелец. Самооценивание запрещено.';end if;
 if p_restaurant_id is distinct from member.restaurant_id then raise exception 'Заведение сотрудника изменилось. Обновите кабинет.';end if;
 if jsonb_typeof(p_scores) is distinct from 'object' then raise exception 'Заполните шесть оценок от 1 до 10.';end if;
 if (select count(*) from jsonb_object_keys(p_scores))<>6 or exists(select 1 from unnest(keys) k where not p_scores ? k) or exists(select 1 from jsonb_each(p_scores) s where jsonb_typeof(s.value)<>'number' or s.value::text !~ '^(10|[1-9])$') then raise exception 'По каждой из шести категорий нужна целая оценка от 1 до 10.';end if;
 if p_comment is null or length(p_comment)>3000 then raise exception 'Комментарий должен быть не длиннее 3000 символов.';end if;
 select sum(value::text::integer) into total from jsonb_each(p_scores);
 insert into public.academy_oral_assessments(employee_id,employee_name,employee_position,restaurant_id,division,scores,category_count,score_total,examiner_id,examiner_name,comment)
 values(member.id,member.full_name,member.position,member.restaurant_id,'kitchen',p_scores,6,total,actor.id,actor.full_name,trim(p_comment)) returning id into assessment_id;
 update public.academy_profiles set training_level=training_level,updated_at=now() where id=member.id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'kitchen_oral',assessment_id::text,jsonb_build_object('employee',member.id,'total',total,'passed',total>=48));
 return assessment_id;
end $$;
revoke all on function public.academy_oral_data(boolean),public.academy_save_kitchen_oral(uuid,text,jsonb,text) from public,anon;
grant execute on function public.academy_oral_data(boolean),public.academy_save_kitchen_oral(uuid,text,jsonb,text) to authenticated;
-- Waiters require the latest successful kitchen AND bar assessment in their current restaurant.
update public.academy_profiles set training_level=training_level where position='Официант';

create or replace function academy_private.valid_work(p_restaurant text,p_department text,p_position text)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(p_restaurant in ('minsk','pushkino','khimki','mytishchi') and (
 (p_department='Зал' and p_position in ('Официант','Администратор','Хостес')) or
 (p_department='Бар' and p_position in ('Старший бармен','Барбэк','Бармен','Бар-менеджер')) or
 (p_department='Кухня' and p_position in ('Сотрудник кухни','Шеф-повар')) or
 (p_department='Арт' and p_position='Сотрудник арт') or
 (p_department='Кальян' and p_position='Сотрудник кальянного подразделения') or
 (p_department='Руководитель' and p_position in ('Руководитель','Управляющий'))),false)
$$;
revoke all on function academy_private.valid_work(text,text,text) from public,anon,authenticated;


create or replace function public.academy_enroll(p_full_name text,p_restaurant_id text,p_department text,p_position text)
returns public.academy_profiles language plpgsql security definer set search_path='' as $$
declare r public.academy_profiles;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_full_name is null or length(trim(p_full_name))<2 or length(p_full_name)>150 then raise exception 'Invalid name'; end if;
 if p_restaurant_id is null or p_restaurant_id not in ('minsk','pushkino','khimki','mytishchi') or p_department is null or p_position is null then raise exception 'Complete your team profile'; end if;
 if not ((p_department='Зал' and p_position in ('Официант','Администратор','Хостес')) or
 (p_department='Бар' and p_position in ('Старший бармен','Барбэк','Бармен','Бар-менеджер')) or
 (p_department='Кухня' and p_position in ('Сотрудник кухни','Шеф-повар')) or (p_department='Арт' and p_position='Сотрудник арт') or
 (p_department='Кальян' and p_position='Сотрудник кальянного подразделения') or (p_department='Руководитель' and p_position in ('Руководитель','Управляющий'))) then raise exception 'Invalid position'; end if;
 insert into public.academy_profiles(id,full_name,restaurant_id,department,position) values(auth.uid(),trim(p_full_name),p_restaurant_id,p_department,p_position)
 on conflict(id) do update set full_name=excluded.full_name,restaurant_id=excluded.restaurant_id,department=excluded.department,position=excluded.position,updated_at=now()
 where academy_profiles.status='pending' and academy_profiles.role='employee' returning * into r;
 if r.id is null then select * into r from public.academy_profiles where id=auth.uid(); end if;
 return r;
end $$;


create or replace function public.academy_set_course_audience(p_content_id text,p_positions jsonb,p_levels jsonb,p_priorities jsonb) returns void language plpgsql security definer set search_path='' as $$
declare c public.academy_content; allowed text[]:=array['Официант','Администратор','Хостес','Старший бармен','Барбэк','Бармен','Сотрудник кухни','Сотрудник арт','Сотрудник кальянного подразделения','Руководитель','Управляющий','Бар-менеджер','Шеф-повар'];
begin
 select * into c from public.academy_content where id=p_content_id for update;
 if c.id is null or c.kind<>'course' or not academy_private.can_edit(c.restaurant_id,c.department) then raise exception 'Недостаточно прав для настройки курса.';end if;
 if jsonb_typeof(p_positions) is distinct from 'array' or jsonb_typeof(p_levels) is distinct from 'array' or jsonb_typeof(p_priorities) is distinct from 'object' then raise exception 'Проверьте категории курса.';end if;
 if jsonb_array_length(p_positions) not between 1 and 13 or exists(select 1 from jsonb_array_elements_text(p_positions) x where x is null or not x=any(allowed)) or (select count(*) from jsonb_array_elements_text(p_positions))<>(select count(distinct x) from jsonb_array_elements_text(p_positions) x) then raise exception 'Выберите хотя бы одну должность без повторов.';end if;
 if jsonb_array_length(p_levels) not between 1 and 2 or exists(select 1 from jsonb_array_elements_text(p_levels) x where x is null or x not in ('trainee','certified')) then raise exception 'Выберите уровень подготовки.';end if;
 if exists(select 1 from jsonb_each_text(p_priorities) x where not p_positions ? x.key or x.value is null or x.value not in ('start','attestation','additional')) then raise exception 'Проверьте приоритеты должностей.';end if;
 update public.academy_content set payload=payload||jsonb_build_object('audiencePositions',p_positions,'audienceLevels',p_levels,'audiencePriorities',p_priorities),updated_at=now() where id=c.id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'course_audience',c.id,jsonb_build_object('positions',p_positions,'levels',p_levels,'priorities',p_priorities));
end $$;

update public.academy_content set payload=jsonb_set(payload,'{audiencePositions}',(payload->'audiencePositions') || case when (payload->'audiencePositions' ? 'Бармен' or payload->'audiencePositions' ? 'Руководитель') and not payload->'audiencePositions' ? 'Бар-менеджер' then '["Бар-менеджер"]'::jsonb else '[]'::jsonb end || case when (payload->'audiencePositions' ? 'Сотрудник кухни' or payload->'audiencePositions' ? 'Руководитель') and not payload->'audiencePositions' ? 'Шеф-повар' then '["Шеф-повар"]'::jsonb else '[]'::jsonb end) where kind='course' and jsonb_typeof(payload->'audiencePositions')='array';
insert into public.academy_content(id,kind,title,published,restaurant_id,department,payload) values('kitchen-oral-guide','material','Устная аттестация кухни РВБ — шпаргалка',true,null,null,'{"brand":"rvb","description":"Структура устной аттестации, темы и примеры вопросов по кухне РВБ.","body":"Ниже — структура подготовки и примеры вопросов. Вопросы на аттестации могут меняться.\n\nОценки: 1–10 по каждой из шести категорий. Кухня сдана при среднем балле от 8. Официант аттестован после сдачи кухни и бара.\n\nГорячий цех\nГарниры, виды мяса, соусы, подача, украшения и посуда.\n1. Назови по одному блюду из говядины, свинины, курицы, индейки, рыбы и морепродуктов.\n2. Красочно опиши пять самых популярных позиций.\n\nХолодный цех\nХолодные закуски на компанию и порционные, заправки в салатах, подача, тарелки для подачи, десерты.\n1. Распиши полностью состав трёх холодных закусок из рыбы.\n2. Назови салаты, в составе которых есть горчица — любая.\n\nАллергены\nКакие продукты из нашего меню могут вызывать аллергическую реакцию.\n1. В состав каких заправок для салатов входит лимонный сок?\n2. Можем ли мы убрать из блюда «Побег из курятника» аллерген? Если да — что это за аллерген?\n\nСоусы\nФудпэйринг, составы, выход, замена.\n1. Подбери по два соуса к блюдам «Настоящему индейцу», «Стейк Пиканья», «Картофель фри». Соусы повторяться не должны.\n2. В каких горячих блюдах мы можем заменить соус, который входит в состав самого блюда, а не подаётся дополнительно?\n\nПицца\nПеречень пицц и дополнительные ингредиенты.\n1. Назови горячие закуски, которые готовятся на основе теста для пиццы.\n2. Перечисли пять видов пиццы с разными начинками.\n\nОбщие знания\nЗамена ингредиентов, лояльность гостя, софт-скиллы.\n1. На раздаче стоят блюда для позиции, которую ведёшь не ты. Твои действия.\n2. Стол из шести человек, из них двое детей до 11 лет, просит детский стульчик и цветные карандаши и фломастеры. Твои действия.","guide":{"title":"Устная аттестация по кухне","intro":"Ниже — структура подготовки и примеры вопросов. Вопросы на аттестации могут меняться.","threshold":8,"categories":[{"id":"hot","title":"Горячий цех","topics":"Гарниры, виды мяса, соусы, подача, украшения и посуда.","questions":["Назови по одному блюду из говядины, свинины, курицы, индейки, рыбы и морепродуктов.","Красочно опиши пять самых популярных позиций."]},{"id":"cold","title":"Холодный цех","topics":"Холодные закуски на компанию и порционные, заправки в салатах, подача, тарелки для подачи, десерты.","questions":["Распиши полностью состав трёх холодных закусок из рыбы.","Назови салаты, в составе которых есть горчица — любая."]},{"id":"allergens","title":"Аллергены","topics":"Какие продукты из нашего меню могут вызывать аллергическую реакцию.","questions":["В состав каких заправок для салатов входит лимонный сок?","Можем ли мы убрать из блюда «Побег из курятника» аллерген? Если да — что это за аллерген?"]},{"id":"sauces","title":"Соусы","topics":"Фудпэйринг, составы, выход, замена.","questions":["Подбери по два соуса к блюдам «Настоящему индейцу», «Стейк Пиканья», «Картофель фри». Соусы повторяться не должны.","В каких горячих блюдах мы можем заменить соус, который входит в состав самого блюда, а не подаётся дополнительно?"]},{"id":"pizza","title":"Пицца","topics":"Перечень пицц и дополнительные ингредиенты.","questions":["Назови горячие закуски, которые готовятся на основе теста для пиццы.","Перечисли пять видов пиццы с разными начинками."]},{"id":"general","title":"Общие знания","topics":"Замена ингредиентов, лояльность гостя, софт-скиллы.","questions":["На раздаче стоят блюда для позиции, которую ведёшь не ты. Твои действия.","Стол из шести человек, из них двое детей до 11 лет, просит детский стульчик и цветные карандаши и фломастеры. Твои действия."]}]}}'::jsonb) on conflict(id) do nothing;
commit;

