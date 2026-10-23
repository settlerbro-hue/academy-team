-- User requested replacement of the remaining old photos with PDF images.
begin;
with photos(id,image) as (values
('rvb-minsk-002','rvb-bar-20261021/rvb-minsk-002.png'),
('rvb-minsk-009','rvb-bar-20261021/rvb-minsk-009.png'),
('rvb-minsk-014','rvb-bar-20261021/rvb-minsk-014.png'),
('rvb-minsk-016','rvb-bar-20261021/rvb-minsk-016.png'),
('rvb-minsk-032','rvb-bar-20261021/rvb-minsk-032.png'),
('rvb-minsk-033','rvb-bar-20261021/rvb-minsk-033.png')
) update public.academy_content c set payload=jsonb_set(c.payload,'{image}',to_jsonb(p.image)),updated_at=now() from photos p where c.id=p.id and c.kind='menu' and c.payload->>'menuSection'='bar' and c.payload->>'image' is distinct from p.image returning c.id,c.title;
commit;
