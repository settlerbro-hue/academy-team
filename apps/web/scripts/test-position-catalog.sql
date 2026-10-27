-- No lasting test-profile changes.
begin;
do $$
declare p record; g jsonb;
begin
 if not academy_private.valid_work('minsk','Кухня','Повар') or not academy_private.valid_work('khimki','Кальян','Кальянный мастер') or not academy_private.valid_work('mytishchi','Кальян','Старший кальянный мастер') or not academy_private.valid_work('pushkino','Зал','Администратор зала') then raise exception 'New job missing';end if;
 if academy_private.valid_work('minsk','Зал','Администратор') or academy_private.valid_work('minsk','Кухня','Сотрудник кухни') or academy_private.valid_work('minsk','Кальян','Сотрудник кальянного подразделения') or academy_private.valid_work('minsk','Руководитель','Операционный директор') then raise exception 'Retired or reserved job offered';end if;
 if exists(select 1 from public.academy_profiles where position in ('Администратор','Сотрудник кухни','Сотрудник кальянного подразделения')) then raise exception 'Old profile names remain';end if;
 if exists(select 1 from public.academy_content where payload->'audiencePositions' ?| array['Администратор','Сотрудник кухни','Сотрудник кальянного подразделения'] or payload->'audiencePriorities' ?| array['Администратор','Сотрудник кухни','Сотрудник кальянного подразделения']) then raise exception 'Old course audience remains';end if;
 select id into p from public.academy_profiles where role='employee' and status='active' limit 1;
 g:=academy_private.general_training_status(p.id,'minsk','Зал','Администратор зала');
 if not g->'courses' @>jsonb_build_array(jsonb_build_object('id','guru-25811','priority','start')) then raise exception 'Administrator programme priority lost';end if;
 g:=academy_private.general_training_status(p.id,'minsk','Зал','Официант');if (g->>'tests_total')::integer<>47 then raise exception 'Waiter programme changed';end if;
 g:=academy_private.general_training_status(p.id,'minsk','Зал','Хостес');if (g->>'tests_total')::integer<>28 then raise exception 'Hostess programme changed';end if;
 if not exists(select 1 from public.academy_profiles where id='d4c13a7d-27c6-434d-812b-6bd477166573' and operations_director) then raise exception 'Kucher access changed';end if;
end $$;
rollback;
select 'PASS: new job validation, profiles and course audiences, venue priorities, waiter47/hostess28 and unique Kucher access preserved.' result;
