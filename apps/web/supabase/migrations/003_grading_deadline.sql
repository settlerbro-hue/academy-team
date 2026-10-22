begin;
create or replace function public.academy_submit_test(p_attempt_id uuid,p_answers jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.academy_attempts; k jsonb; q jsonb; expected jsonb; supplied jsonb; points integer:=0; n integer:=0; review boolean:=false; ok boolean; deadline integer; timed_out boolean;
begin
 if not academy_private.is_active() then raise exception 'Forbidden'; end if;
 select * into a from public.academy_attempts where id=p_attempt_id and user_id=auth.uid() for update;
 if a.id is null then raise exception 'Attempt unavailable'; end if;
 if a.submitted_at is not null then return jsonb_build_object('score',a.score,'total',a.total,'passed',a.passed,'needs_review',a.needs_review,'timed_out',coalesce((a.snapshot->>'timeLimitSeconds')::integer,0)>0 and a.submitted_at>a.started_at+make_interval(secs=>coalesce((a.snapshot->>'timeLimitSeconds')::integer,0)+10)); end if;
 if jsonb_typeof(p_answers)<>'object' or octet_length(p_answers::text)>100000 then raise exception 'Invalid answers'; end if;
 select keys into k from academy_private.attempt_keys where attempt_id=a.id;
 for q in select value from jsonb_array_elements(a.snapshot->'questions') loop
 n:=n+1; expected:=k->(q->>'id'); supplied:=p_answers->(q->>'id');
 if q->>'type'='text' or expected is null then review:=true;
 elsif jsonb_typeof(supplied)='array' then
 select coalesce(jsonb_agg(value order by value), '[]'::jsonb) into supplied from (select distinct value from jsonb_array_elements(supplied)) s;
 select coalesce(jsonb_agg(value order by value), '[]'::jsonb) into expected from (select distinct value from jsonb_array_elements(expected)) e;
 if supplied=expected then points:=points+1; end if;
 end if;
 end loop;
 deadline:=coalesce((a.snapshot->>'timeLimitSeconds')::integer,0);
 ok:=not review and points>=coalesce((a.snapshot->>'passCount')::integer,n);
 timed_out:=deadline>0 and now()>a.started_at+make_interval(secs=>deadline+10); if timed_out then ok:=false; end if;
 update public.academy_attempts set submitted_at=now(),score=points,total=n,passed=ok,needs_review=review,answers=p_answers where id=a.id;
 return jsonb_build_object('score',points,'total',n,'passed',ok,'needs_review',review,'timed_out',timed_out);
end $$;


revoke all on function public.academy_submit_test(uuid,jsonb) from public,anon;
grant execute on function public.academy_submit_test(uuid,jsonb) to authenticated;
commit;

