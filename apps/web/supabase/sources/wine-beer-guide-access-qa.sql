-- Read-only audience checks; no changes to profiles or permissions.
begin;
do $qa$
declare p public.academy_profiles; guide_id text; actual boolean; expected boolean;
begin
 foreach guide_id in array array['bar-wine-guide','bar-beer-guide'] loop
  for p in select * from public.academy_profiles loop
   perform set_config('request.jwt.claim.sub',p.id::text,true);
   actual:=academy_private.can_read_content(guide_id);
   expected:=coalesce(p.status='active' and (p.role='admin' or p.operations_director or p.venue_director or p.department='Бар'),false);
   if actual is distinct from expected then raise exception 'Unexpected audience for %',guide_id;end if;
  end loop;
 end loop;
 perform set_config('request.jwt.claim.sub','',true);
 raise notice 'Wine and beer audience checks passed';
end $qa$;
commit;
select jsonb_agg(to_jsonb(c) order by id) as documents from public.academy_content c where id in ('bar-wine-guide','bar-beer-guide');
