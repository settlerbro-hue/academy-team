-- Fill only absent bar photos. Existing manager uploads and other fields are preserved.
begin;
with photos(id,image) as (values
('rvb-minsk-001','rvb-bar-20261021/rvb-minsk-001.png'),
('rvb-minsk-004','rvb-bar-20261021/rvb-minsk-004.png'),
('rvb-minsk-003','rvb-bar-20261021/rvb-minsk-003.png'),
('rvb-minsk-010','rvb-bar-20261021/rvb-minsk-010.png'),
('rvb-minsk-008','rvb-bar-20261021/rvb-minsk-008.png'),
('rvb-minsk-007','rvb-bar-20261021/rvb-minsk-007.png'),
('rvb-minsk-013','rvb-bar-20261021/rvb-minsk-013.png'),
('rvb-minsk-005','rvb-bar-20261021/rvb-minsk-005.png'),
('rvb-minsk-011','rvb-bar-20261021/rvb-minsk-011.png'),
('rvb-minsk-015','rvb-bar-20261021/rvb-minsk-015.png'),
('rvb-minsk-012','rvb-bar-20261021/rvb-minsk-012.png'),
('rvb-minsk-006','rvb-bar-20261021/rvb-minsk-006.png'),
('rvb-autumn26-228-1','rvb-bar-20261021/rvb-autumn26-228-1.png')
) update public.academy_content c set payload=jsonb_set(c.payload,'{image}',to_jsonb(p.image)),updated_at=now()
from photos p where c.id=p.id and c.kind='menu' and c.payload->>'menuSection'='bar'
and nullif(trim(coalesce(c.payload->>'image','')),'') is null
and nullif(trim(coalesce(c.payload->>'photo','')),'') is null
returning c.id,c.title;
commit;
