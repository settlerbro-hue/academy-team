begin;
create or replace function academy_private.general_training_status(p_user uuid,p_restaurant text,p_department text,p_position text)
returns jsonb language sql stable security definer set search_path='' as $$
with required_courses as (
 select c.* from public.academy_content c where c.kind='course' and c.published
 and (c.restaurant_id is null or c.restaurant_id=p_restaurant) and (c.department is null or c.department=p_department)
 and (not c.payload ? 'audiencePositions' or c.payload->'audiencePositions' ? p_position)
 and coalesce(c.payload->'audiencePriorities'->>p_position,c.payload->>'priority','additional') in ('start','attestation')
), required_tests as (
 select t.* from public.academy_content t where t.kind='test' and t.published
 and (t.restaurant_id is null or t.restaurant_id=p_restaurant) and (t.department is null or t.department=p_department)
 and (not t.payload ? 'audiencePositions' or t.payload->'audiencePositions' ? p_position)
 and (exists(select 1 from required_courses c where c.id=t.course_id) or
 (t.course_id is null and coalesce(t.payload->>'priority','attestation') in ('start','attestation')))
), test_status as (
 select t.id,t.title,t.course_id,exists(select 1 from public.academy_attempts a where a.user_id=p_user and a.test_id=t.id and a.submitted_at is not null and a.passed and not a.needs_review and a.total>0 and
 (coalesce((a.snapshot->>'timeLimitSeconds')::integer,0)=0 or a.submitted_at<=a.started_at+make_interval(secs=>(a.snapshot->>'timeLimitSeconds')::integer+10))) as passed from required_tests t
), course_status as (
 select c.id,c.title,coalesce(c.payload->'audiencePriorities'->>p_position,c.payload->>'priority','additional') as priority,
 (select count(*) from jsonb_array_elements(case when jsonb_typeof(c.payload->'lessons')='array' then c.payload->'lessons' else '[]'::jsonb end)) as total,
 (select count(*) from jsonb_array_elements(case when jsonb_typeof(c.payload->'lessons')='array' then c.payload->'lessons' else '[]'::jsonb end) with ordinality l(value,n) where exists(select 1 from public.academy_progress p where p.user_id=p_user and p.course_id=c.id and p.lesson_id=coalesce(l.value->>'id',(l.n-1)::text))) as done,
 (select count(*) from test_status t where t.course_id=c.id) as tests_total,
 (select count(*) from test_status t where t.course_id=c.id and t.passed) as tests_passed
 from required_courses c
), completed_courses as (
 select c.*,((total>0 or tests_total>0) and done=total and tests_total=tests_passed) as complete from course_status c
)
select jsonb_build_object('passed',((select count(*) from completed_courses)+(select count(*) from test_status)>0 and not exists(select 1 from completed_courses where not complete) and not exists(select 1 from test_status where not passed)),
 'courses_total',(select count(*) from completed_courses),'courses_completed',(select count(*) from completed_courses where complete),
 'tests_total',(select count(*) from test_status),'tests_passed',(select count(*) from test_status where passed),
 'courses',coalesce((select jsonb_agg(to_jsonb(c) order by case c.priority when 'start' then 0 else 1 end,c.title) from completed_courses c),'[]'::jsonb),
 'tests',coalesce((select jsonb_agg(to_jsonb(t) order by t.title) from test_status t),'[]'::jsonb))
$$;
create or replace function academy_private.waiter_is_certified(p_user uuid,p_restaurant text,p_department text,p_position text) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select passed from public.academy_oral_assessments where employee_id=p_user and restaurant_id=p_restaurant and division='kitchen' order by created_at desc,id desc limit 1),false)
 and coalesce((select passed from public.academy_oral_assessments where employee_id=p_user and restaurant_id=p_restaurant and division='bar' order by created_at desc,id desc limit 1),false)
 and coalesce((academy_private.general_training_status(p_user,p_restaurant,p_department,p_position)->>'passed')::boolean,false)
$$;
create or replace function academy_private.waiter_is_certified(p_user uuid,p_restaurant text) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select academy_private.waiter_is_certified(p.id,p_restaurant,p.department,p.position) from public.academy_profiles p where p.id=p_user),false)
$$;
create or replace function academy_private.normalize_training_level() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.department='Руководитель' or new.department is null then new.training_level:=null;
 elsif new.position='Официант' then new.training_level:=case when academy_private.waiter_is_certified(new.id,new.restaurant_id,new.department,new.position) then 'certified' else 'trainee' end;
 elsif new.training_level is null then new.training_level:='trainee';end if;
 return new;
end $$;
create or replace function academy_private.sync_learning_attestation() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op<>'INSERT' then update public.academy_profiles set training_level=training_level where id=old.user_id and position='Официант';end if;
 if tg_op<>'DELETE' then update public.academy_profiles set training_level=training_level where id=new.user_id and position='Официант';end if;
 return null;
end $$;
create trigger academy_progress_attestation after insert or update or delete on public.academy_progress for each row execute function academy_private.sync_learning_attestation();
create trigger academy_attempt_attestation after insert or update or delete on public.academy_attempts for each row execute function academy_private.sync_learning_attestation();
create or replace function academy_private.sync_curriculum_attestation() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.academy_profiles set training_level=training_level where position='Официант';return null;
end $$;
create trigger academy_curriculum_attestation after insert or update or delete on public.academy_content for each statement execute function academy_private.sync_curriculum_attestation();
revoke all on function academy_private.general_training_status(uuid,text,text,text),academy_private.waiter_is_certified(uuid,text,text,text),academy_private.waiter_is_certified(uuid,text),academy_private.normalize_training_level(),academy_private.sync_learning_attestation(),academy_private.sync_curriculum_attestation() from public,anon,authenticated;

create or replace function public.academy_save_bar_oral(p_employee_id uuid,p_restaurant_id text,p_scores jsonb,p_comment text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare member public.academy_profiles; actor public.academy_profiles; total integer; assessment_id uuid;keys text[]:=array['wine','spirits','beer','cocktails','nonalcoholic','specials','alternatives','pairing'];
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 select * into member from public.academy_profiles where id=p_employee_id for update;
 if actor.id is null or member.id is null or member.status<>'active' or member.restaurant_id is null or member.id=actor.id or not academy_private.can_grade_oral(member.restaurant_id,'bar') then raise exception 'Оценки бара выставляет бар-менеджер своего заведения или владелец. Самооценивание запрещено.';end if;
 if p_restaurant_id is distinct from member.restaurant_id then raise exception 'Заведение сотрудника изменилось. Обновите кабинет.';end if;
 if jsonb_typeof(p_scores) is distinct from 'object' then raise exception 'Заполните восемь оценок от 1 до 10.';end if;
 if (select count(*) from jsonb_object_keys(p_scores))<>8 or exists(select 1 from unnest(keys) k where not p_scores ? k) or exists(select 1 from jsonb_each(p_scores) s where jsonb_typeof(s.value)<>'number' or s.value::text !~ '^(10|[1-9])$') then raise exception 'По каждой из восьми категорий нужна целая оценка от 1 до 10.';end if;
 if p_comment is null or length(p_comment)>3000 then raise exception 'Комментарий должен быть не длиннее 3000 символов.';end if;
 select sum(value::text::integer) into total from jsonb_each(p_scores);
 insert into public.academy_oral_assessments(employee_id,employee_name,employee_position,restaurant_id,division,scores,category_count,score_total,examiner_id,examiner_name,comment)
 values(member.id,member.full_name,member.position,member.restaurant_id,'bar',p_scores,8,total,actor.id,actor.full_name,trim(p_comment)) returning id into assessment_id;
 update public.academy_profiles set training_level=training_level,updated_at=now() where id=member.id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(actor.id,'bar_oral',assessment_id::text,jsonb_build_object('employee',member.id,'total',total,'passed',total>=64));
 return assessment_id;
end $$;

create or replace function public.academy_oral_data(p_all boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; viewer boolean; result jsonb;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null then raise exception 'Доступ закрыт.';end if;
 viewer:=academy_private.can_view_oral();
 select jsonb_build_object(
 'viewer',viewer,
 'members',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'restaurant_id',p.restaurant_id,'department',p.department,'position',p.position,'training_level',p.training_level,'general',academy_private.general_training_status(p.id,p.restaurant_id,p.department,p.position),'can_grade_kitchen',academy_private.can_grade_oral(p.restaurant_id,'kitchen') and p.id<>actor.id,'can_grade_bar',academy_private.can_grade_oral(p.restaurant_id,'bar') and p.id<>actor.id) order by p.full_name) from public.academy_profiles p where p.status='active' and (p.id=actor.id or viewer and p_all and (actor.role='admin' or p.restaurant_id=actor.restaurant_id))),'[]'::jsonb),
 'assessments',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc,a.id desc) from public.academy_oral_assessments a where a.employee_id=actor.id or viewer and p_all and (actor.role='admin' or a.restaurant_id=actor.restaurant_id and exists(select 1 from public.academy_profiles p where p.id=a.employee_id and p.restaurant_id=actor.restaurant_id))),'[]'::jsonb)) into result;
 return result;
end $$;

revoke all on function public.academy_save_bar_oral(uuid,text,jsonb,text) from public,anon;
grant execute on function public.academy_save_bar_oral(uuid,text,jsonb,text) to authenticated;
insert into public.academy_content(id,kind,title,published,restaurant_id,department,payload) values('bar-oral-guide','material','Устная аттестация бара РВБ — шпаргалка',true,null,null,'{"brand":"rvb","description":"Восемь категорий и примеры вопросов устной аттестации бара.","body":"Структура подготовки и примеры вопросов по бару. Вопросы могут меняться.\n\nВосемь равнозначных категорий, оценки от 1 до 10. Средний балл от 8 — бар сдан.\n\nВино\nЗнание винной карты, правильная подача, рекомендации гостю.\n1. Назвать популярные позиции вин из карты: стиль, сорт винограда, страна, год.\n2. Подобрать вино к трём блюдам меню и объяснить простыми словами.\n\nКрепкий алкоголь\nКатегории, способы подачи, вкусовые профили, базовые замены.\n1. Объяснить основные категории и ходовые позиции бара.\n2. Предложить крепкий напиток под запрос.\n\nПиво\nСтили, крепость, вкус, рекомендации к закускам.\n1. Описать стили и вкус пяти позиций пивной карты.\n2. Предложить пиво к закуске, мясу, острой еде или лёгкому вечеру.\n\nКоктейли\nСоставы, вкус, крепость, рекомендации.\n1. Назвать состав и вкус десяти коктейлей из карты.\n2. Подобрать коктейль по запросу гостя: кислый, сладкий, крепкий или освежающий.\n\nБ/А\nБезалкогольные напитки, лимонады, чай и кофе.\n1. Предложить семь безалкогольных вариантов под разные запросы.\n\nСпецпредложения\nАкции, сезонные позиции, выгодные предложения, дополнительные продажи.\n1. Рассказать актуальные спецпредложения.\n2. Нативно предложить дополнительную позицию в диалоге с гостем.\n\nАльтернативы\nЗамены отсутствующих позиций, работа с ограничениями, гибкость.\n1. Предложить замену отсутствующей позиции: вино, крепкий алкоголь, коктейль, Б/А.\n\nПейринг\nПодбор напитка к блюду, ситуации и вкусовому запросу.\n1. Подобрать напитки к блюдам: мясо, рыба, десерт, острое, закуски.","guide":{"title":"Устная аттестация по бару","intro":"Структура подготовки и примеры вопросов по бару. Вопросы могут меняться.","threshold":8,"categories":[{"id":"wine","title":"Вино","topics":"Знание винной карты, правильная подача, рекомендации гостю.","questions":["Назвать популярные позиции вин из карты: стиль, сорт винограда, страна, год.","Подобрать вино к трём блюдам меню и объяснить простыми словами."]},{"id":"spirits","title":"Крепкий алкоголь","topics":"Категории, способы подачи, вкусовые профили, базовые замены.","questions":["Объяснить основные категории и ходовые позиции бара.","Предложить крепкий напиток под запрос."]},{"id":"beer","title":"Пиво","topics":"Стили, крепость, вкус, рекомендации к закускам.","questions":["Описать стили и вкус пяти позиций пивной карты.","Предложить пиво к закуске, мясу, острой еде или лёгкому вечеру."]},{"id":"cocktails","title":"Коктейли","topics":"Составы, вкус, крепость, рекомендации.","questions":["Назвать состав и вкус десяти коктейлей из карты.","Подобрать коктейль по запросу гостя: кислый, сладкий, крепкий или освежающий."]},{"id":"nonalcoholic","title":"Б/А","topics":"Безалкогольные напитки, лимонады, чай и кофе.","questions":["Предложить семь безалкогольных вариантов под разные запросы."]},{"id":"specials","title":"Спецпредложения","topics":"Акции, сезонные позиции, выгодные предложения, дополнительные продажи.","questions":["Рассказать актуальные спецпредложения.","Нативно предложить дополнительную позицию в диалоге с гостем."]},{"id":"alternatives","title":"Альтернативы","topics":"Замены отсутствующих позиций, работа с ограничениями, гибкость.","questions":["Предложить замену отсутствующей позиции: вино, крепкий алкоголь, коктейль, Б/А."]},{"id":"pairing","title":"Пейринг","topics":"Подбор напитка к блюду, ситуации и вкусовому запросу.","questions":["Подобрать напитки к блюдам: мясо, рыба, десерт, острое, закуски."]}]}}'::jsonb) on conflict(id) do nothing;
update public.academy_profiles set training_level=training_level where position='Официант';
commit;

