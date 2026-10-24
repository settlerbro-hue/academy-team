begin;
select set_config('request.jwt.claim.sub',(select id::text from public.academy_profiles where role='admin' and status='active' limit 1),true);
-- Actor identity is supplied above; postgres is needed for the private scope helper.
do $$ declare c public.academy_content;p public.academy_profiles;a public.academy_profiles;own_brand text;own_bar text;own_kitchen text;foreign_bar text;foreign_kitchen text;dashboard jsonb;rank_row jsonb;begin
 for c in select distinct on(payload->>'brand',payload->>'menuSection') * from public.academy_content where kind='menu' and published order by payload->>'brand',payload->>'menuSection',id loop
  perform public.academy_save_menu_with_notice(jsonb_set(to_jsonb(c),'{payload,price}','"99 ₽"'),false,'');
  if not exists(select 1 from public.academy_content where id=c.id and payload->>'price'='99 ₽') then raise exception 'Editor save failed %',c.id;end if;
  a.status:='active';a.role:='manager';a.restaurant_id:=case when c.payload->>'brand'='rvb' then 'minsk' else 'mytishchi' end;a.department:=case when c.payload->>'menuSection'='bar' then 'Бар' else 'Кухня' end;
  if not academy_private.can_edit_menu_for(a,c) then raise exception 'Scoped admin denied %',c.id;end if;
  a.department:='Арт';if academy_private.can_edit_menu_for(a,c) then raise exception 'Wrong department edit allowed';end if;
  a.department:=case when c.payload->>'menuSection'='bar' then 'Бар' else 'Кухня' end;a.restaurant_id:=case when c.payload->>'brand'='rvb' then 'mytishchi' else 'minsk' end;
  if academy_private.can_edit_menu_for(a,c) then raise exception 'Wrong brand edit allowed';end if;
 end loop;
 for p in select distinct on(restaurant_id) * from public.academy_profiles where status='active' and restaurant_id in('minsk','mytishchi') order by restaurant_id,id loop
  own_brand:=case when p.restaurant_id='minsk' then 'rvb' else '90' end;
  select id into own_bar from public.academy_content where kind='menu' and published and payload->>'brand'=own_brand and payload->>'menuSection'='bar' limit 1;
  select id into own_kitchen from public.academy_content where kind='menu' and published and payload->>'brand'=own_brand and payload->>'menuSection'='kitchen' limit 1;
  select id into foreign_bar from public.academy_content where kind='menu' and published and payload->>'brand'<>own_brand and payload->>'menuSection'='bar' limit 1;
  select id into foreign_kitchen from public.academy_content where kind='menu' and published and payload->>'brand'<>own_brand and payload->>'menuSection'='kitchen' limit 1;
  perform public.academy_set_mark(own_bar,'learned',p.id);perform public.academy_set_mark(own_kitchen,'repeat',p.id);
  select x into dashboard from jsonb_array_elements(public.academy_manager_dashboard()->'menu_stats') x where x->>'user_id'=p.id::text;
  perform public.academy_set_mark(foreign_bar,'learned',p.id);perform public.academy_set_mark(foreign_kitchen,'repeat',p.id);
  if dashboard is distinct from (select x from jsonb_array_elements(public.academy_manager_dashboard()->'menu_stats') x where x->>'user_id'=p.id::text) then raise exception 'Other brand counted %',p.restaurant_id;end if;
  select x into rank_row from jsonb_array_elements(public.academy_ranking()) x where x->>'user_id'=p.id::text;
  if (rank_row->>'menu_learned')::int<>(dashboard->>'learned')::int or (rank_row->>'menu_repeat')::int<>(dashboard->>'repeat')::int then raise exception 'Ranking/dashboard mismatch';end if;
  perform public.academy_set_mark(own_bar,'not_started',p.id);
  if (select (x->>'learned')::int from jsonb_array_elements(public.academy_manager_dashboard()->'menu_stats') x where x->>'user_id'=p.id::text)<>(dashboard->>'learned')::int-1 then raise exception 'Reset mark not applied';end if;
 end loop;
end $$;

rollback;
select 'PASS: four menu editors save; department/brand isolation; own marks and reset; foreign marks excluded; ranking matches dashboard; all changes rolled back' result;

