-- Library bar techcards belong to the whole Bar department.
begin;
do $guard$ begin if (select count(*) from public.academy_content where id in ('bar-techcards','rvb-bar-techcards') and kind='material' and department='Бар')<>2 then raise exception 'Techcard scope changed';end if;end $guard$;
update public.academy_content set payload=jsonb_set(payload,'{libraryAccess}',$audience${"enabled":true,"departments":["Бар"],"positions":["Старший бармен","Барбэк","Бармен","Бар-менеджер"]}$audience$::jsonb),updated_at=now() where id in ('bar-techcards','rvb-bar-techcards') and kind='material' and payload->'libraryAccess' is distinct from $audience${"enabled":true,"departments":["Бар"],"positions":["Старший бармен","Барбэк","Бармен","Бар-менеджер"]}$audience$::jsonb;
do $qa$
declare c public.academy_content;p public.academy_profiles;dep text;pos text;allowed boolean;expected boolean;
begin
 for c in select * from public.academy_content where id in ('bar-techcards','rvb-bar-techcards') loop
  perform academy_private.validate_library_access(c);
  foreach dep in array array['Бар','Зал','Кухня','Арт','Кальян','Руководитель'] loop
   foreach pos in array array['Старший бармен','Барбэк','Бармен','Бар-менеджер','Официант','Администратор зала','Хостес','Повар','Шеф-повар','Сотрудник арт','Кальянный мастер','Старший кальянный мастер','Управляющий'] loop
    p:=jsonb_populate_record(null::public.academy_profiles,jsonb_build_object('role','employee','status','active','department',dep,'position',pos,'restaurant_id','minsk','operations_director',false,'venue_director',false));
    expected:=dep='Бар' and pos in ('Старший бармен','Барбэк','Бармен','Бар-менеджер');
    if academy_private.library_audience_for(p,c) is distinct from expected then raise exception 'Audience check failed';end if;
   end loop;
  end loop;
  for p in select * from public.academy_profiles loop
   perform set_config('request.jwt.claim.sub',p.id::text,true);
   allowed:=academy_private.can_read_content(c.id);
   if p.status='active' and p.role not in ('admin') and not coalesce(p.operations_director,false) and not coalesce(p.venue_director,false) and p.department is distinct from 'Бар' and allowed then raise exception 'Other department can read techcard';end if;
   if p.status='active' and p.department='Бар' and p.position in ('Старший бармен','Барбэк','Бармен','Бар-менеджер') and (c.restaurant_id is null or c.restaurant_id=p.restaurant_id) and not allowed then raise exception 'Bar employee cannot read techcard';end if;
  end loop;
 end loop;
 perform set_config('request.jwt.claim.sub','',true);
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='academy_content' and qual like '%can_read_content%') then raise exception 'Content read policy not found';end if;
end $qa$;
commit;
select title as "Материал",department as "Подразделение",payload->'libraryAccess'->'positions' as "Должности",'Проверено' as "Доступ" from public.academy_content where id in ('bar-techcards','rvb-bar-techcards') order by id;
