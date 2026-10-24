begin;
do $$
declare sample record; actual boolean; doc public.academy_content;
begin
 select * into strict doc from public.academy_content where id='rvb-bar-handbook';
 for sample in select * from (values
 ('Владелец','admin','active',null::text,null::text,true),
 ('Бармен РВБ','employee','active','minsk','Бар',true),
 ('Барбэк РВБ','employee','active','minsk','Бар',true),
 ('Администратор бара РВБ','manager','active','minsk','Бар',true),
 ('Управляющий РВБ','employee','active','minsk','Руководитель',true),
 ('Управляющий 90-е','employee','active','khimki','Руководитель',true),
 ('Бар 90-е','employee','active','khimki','Бар',false),
 ('Администратор бара 90-е','manager','active','mytishchi','Бар',false),
 ('Зал РВБ','employee','active','minsk','Зал',false),
 ('Кухня РВБ','manager','active','minsk','Кухня',false),
 ('Неподтверждённая заявка','employee','pending','minsk','Бар',false),
 ('Закрытый доступ','employee','suspended','minsk','Бар',false)
 ) as v(label,role,status,restaurant,department,expected)
 loop
  actual:=academy_private.can_read_bar_handbook(jsonb_populate_record(null::public.academy_profiles,jsonb_build_object('role',sample.role,'status',sample.status,'restaurant_id',sample.restaurant,'department',sample.department)),doc);
  if actual is distinct from sample.expected then raise exception 'Audience check failed: %',sample.label;end if;
 end loop;
 if not exists(select 1 from storage.objects where bucket_id='academy-assets' and name='assets/library/rvb-bar-handbook/bar-plan.png') then raise exception 'Bar plan missing';end if;
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='rvb_bar_handbook_assets_restricted' and permissive='RESTRICTIVE') then raise exception 'Missing restrictive image policy';end if;
end $$;
rollback;
begin;
do $$
declare member record; visible_cards integer; visible_files integer; expected boolean;
begin
 for member in select * from public.academy_profiles where status='active'
 loop
  expected:=member.role='admin' or member.department='Руководитель' or member.restaurant_id='minsk' and member.department='Бар';
  perform set_config('request.jwt.claim.sub',member.id::text,true);
  execute 'set local role authenticated';
  select count(*) into visible_cards from public.academy_content where id='rvb-bar-handbook';
  select count(*) into visible_files from storage.objects where bucket_id='academy-assets' and name='assets/library/rvb-bar-handbook/bar-plan.png';
  execute 'reset role';
  if (visible_cards=1) is distinct from expected or (visible_files=1) is distinct from expected then raise exception 'RLS failed for existing profile: %',member.id;end if;
 end loop;
end $$;
rollback;
select 'PASS: 12 audience cases, actual authenticated content/file RLS for every active profile' as result;
