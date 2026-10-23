-- Run after 007. Every mutation rolls back. Uses the explicitly approved test manager.
begin;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
set local role authenticated;
do $$
declare p public.academy_profiles; old_priority text;
begin
 select * into p from public.academy_profiles where id=auth.uid();
 perform public.academy_update_profile(p.id,p.full_name,date '1990-01-01','unspecified',date '2026-01-01',null);
 if not exists(select 1 from public.academy_profiles where id=p.id and birth_date=date '1990-01-01' and gender='unspecified') then raise exception 'Own profile update failed'; end if;
 begin
  perform public.academy_update_profile('68a8567e-625e-41bc-bb37-6744d729c3d4','Forbidden test',null,null,null,null);
  raise exception 'Cross-scope profile write was allowed';
 exception when raise_exception then if sqlerrm<>'Forbidden' then raise; end if; end;
 begin
  perform public.academy_update_profile(p.id,p.full_name,current_date+1,null,null,null);
  raise exception 'Future birth date was allowed';
 exception when raise_exception then if sqlerrm<>'Проверьте дату рождения.' then raise; end if; end;
 begin
  perform public.academy_set_priority('welcome-90','additional',null);
  raise exception 'Shared course write was allowed';
 exception when raise_exception then if sqlerrm<>'Forbidden' then raise; end if; end;
 perform public.academy_set_priority('e3b22b37-9494-459b-880f-af736d774e1c','additional',null);
 if not exists(select 1 from public.academy_content where id='e3b22b37-9494-459b-880f-af736d774e1c' and payload->>'priority'='additional') then raise exception 'Scoped priority update failed'; end if;
end $$;
rollback;
begin;
select set_config('request.jwt.claim.sub','68a8567e-625e-41bc-bb37-6744d729c3d4',true);
set local role authenticated;
do $$ begin
 perform public.academy_set_priority('welcome-90','additional',null);
 perform public.academy_set_priority('welcome-90','attestation','122072');
 if not exists(select 1 from public.academy_content c, jsonb_array_elements(c.payload->'lessons') l where c.id='welcome-90' and c.payload->>'priority'='additional' and l->>'id'='122072' and l->>'priority'='attestation') then raise exception 'Individual course/lesson priority update failed'; end if;
end $$;
rollback;
select 'PASS: own profile, scoped priority; cross-scope writes and invalid dates blocked; all changes rolled back' as result;
