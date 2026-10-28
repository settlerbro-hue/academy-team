-- Read-only audience checks against current profiles; no account or permission changes.
begin;
do $qa$
declare p public.academy_profiles; actual boolean; expected boolean; checked integer:=0;
begin
 for p in select * from public.academy_profiles loop
  perform set_config('request.jwt.claim.sub',p.id::text,true);
  actual:=academy_private.can_read_content('bar-drinks-guide');
  expected:=coalesce(p.status='active' and (p.role='admin' or p.operations_director or p.venue_director or p.department='Бар'),false);
  if actual is distinct from expected then raise exception 'Unexpected handbook audience';end if;
  checked:=checked+1;
 end loop;
 perform set_config('request.jwt.claim.sub','',true);
 raise notice 'Audience checks passed: % profiles',checked;
end $qa$;
commit;
select to_jsonb(c) as document from public.academy_content c where id='bar-drinks-guide';
