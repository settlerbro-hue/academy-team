-- RVB currently has one restaurant. Canonical scope restores existing administrator editing.
begin;
update public.academy_content set restaurant_id='minsk',updated_at=now() where kind='menu' and payload->>'brand'='rvb' and restaurant_id is null;
commit;
