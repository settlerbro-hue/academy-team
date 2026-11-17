-- Restore the exact pre-merge course/test records and keys, without touching learning history.
begin;
do $rollback$
declare backup jsonb; item jsonb; definition text;
begin
 select details into strict backup from academy_private.audit_log where action='waiter_service_merge_before' and target='waiter-service-20261117' order by id desc limit 1;
 for item in select value from jsonb_array_elements(backup->'content') loop
  update public.academy_content set title=item->>'title',payload=item->'payload',published=(item->>'published')::boolean,updated_at=now() where id=item->>'id';
  if item->'private_keys' is not null and item->'private_keys'<>'null'::jsonb then update academy_private.test_keys set keys=item->'private_keys' where test_id=item->>'id';end if;
 end loop;
 select details->>'definition' into strict definition from academy_private.audit_log where action='waiter_service_merge_function_before' and target='academy_private.general_training_status' order by id desc limit 1;
 execute definition;
end $rollback$;
commit;
