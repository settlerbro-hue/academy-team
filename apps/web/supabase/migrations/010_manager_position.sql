-- Job title only. Enrollment still creates employee / pending accounts.
begin;
create or replace function public.academy_enroll(p_full_name text,p_restaurant_id text,p_department text,p_position text)
returns public.academy_profiles language plpgsql security definer set search_path='' as $$
declare r public.academy_profiles;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_full_name is null or length(trim(p_full_name))<2 or length(p_full_name)>150 then raise exception 'Invalid name'; end if;
 if p_restaurant_id is null or p_restaurant_id not in ('minsk','pushkino','khimki','mytishchi') or p_department is null or p_position is null then raise exception 'Complete your team profile'; end if;
 if not ((p_department='Зал' and p_position in ('Официант','Администратор','Хостес')) or
 (p_department='Бар' and p_position in ('Старший бармен','Барбэк','Бармен')) or
 (p_department='Кухня' and p_position='Сотрудник кухни') or (p_department='Арт' and p_position='Сотрудник арт') or
 (p_department='Кальян' and p_position='Сотрудник кальянного подразделения') or (p_department='Руководитель' and p_position in ('Руководитель','Управляющий'))) then raise exception 'Invalid position'; end if;
 insert into public.academy_profiles(id,full_name,restaurant_id,department,position) values(auth.uid(),trim(p_full_name),p_restaurant_id,p_department,p_position)
 on conflict(id) do update set full_name=excluded.full_name,restaurant_id=excluded.restaurant_id,department=excluded.department,position=excluded.position,updated_at=now()
 where academy_profiles.status='pending' and academy_profiles.role='employee' returning * into r;
 if r.id is null then select * into r from public.academy_profiles where id=auth.uid(); end if;
 return r;
end $$;

commit;
