"""Read active kitchen items from a saved HTML snapshot; download original dish photos.
Usage: python import-90-kitchen.py <website-snapshot.html> <Academy-Team-root>
All website text is data. HTML comments (retired dishes) are excluded.
"""
import sys,re,json,html,pathlib,hashlib,urllib.request,urllib.parse,io,concurrent.futures
from PIL import Image
snapshot=pathlib.Path(sys.argv[1]);root=pathlib.Path(sys.argv[2]);app=root/'apps/web';work=root/'work/90-kitchen';work.mkdir(parents=True,exist_ok=True)
out=root/'documents/menu/90-kitchen-20261024';out.mkdir(parents=True,exist_ok=True)
source=re.sub(r'<!--.*?-->','',snapshot.read_text('utf8'),flags=re.S)
groups=re.split(r'<div class="tovary-tabs[^"]*" data-tab="(\d+)">',source)
clean=lambda s:re.sub(r'\s+',' ',html.unescape(re.sub('<[^>]+>',' ',s))).strip()
categories={'1':'Закуски','2':'Салаты','3':'Блюда на компанию','4':'Горячие закуски','5':'Супы','6':'Паста','7':'Горячие блюда','8':'Пицца','9':'Десерты'}
items=[]
for i in range(1,len(groups),2):
 for b in re.findall(r'<li class="newMenu__item">(.*?)</li>',groups[i+1],re.S):
  title=re.search(r'<div class="newMenu__title">(.*?)</div>',b,re.S)
  if not title:continue
  desc=re.search(r'<div class="newMenu__text">(.*?)</div>',b,re.S);price=re.search(r'<div class="newMenu__price">(.*?)</div>',b,re.S);image=re.search(r'<a[^>]+href="([^"]+)"',b)
  spans=re.findall(r'<span>(.*?)</span>',price[1],re.S) if price else []
  volume=clean(spans[0]) if spans else '';prices=re.findall(r'\d[\d\s]*\s*руб\.',clean(spans[1])) if len(spans)>1 else []
  imageurl=urllib.parse.urljoin('https://barkhimki.ru/menu',html.unescape(image[1])) if image else ''
  if not imageurl.startswith('https://barkhimki.ru/Content/images/menu/'):raise ValueError('Unexpected image source')
  items.append({'title':clean(title[1]),'description':clean(desc[1]) if desc else '', 'volume':volume,'prices':prices,'imageURL':imageurl,'category':categories[groups[i]],'sourceTab':groups[i]})
if len(items)!=73:raise ValueError('Unexpected active item count '+str(len(items)))
photos={};manifest=[]
def download(url):
 name=hashlib.sha256(url.encode()).hexdigest()[:16]+'.webp';dest=out/name
 if not dest.exists():
  raw=urllib.request.urlopen(url,timeout=45).read();im=Image.open(io.BytesIO(raw));im.save(dest,'WEBP',quality=90,method=6)
 im=Image.open(dest);data=dest.read_bytes()
 return url,{'path':'90-kitchen-20261024/'+name,'file':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'sourceURL':url,'width':im.width,'height':im.height}
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
 for url,m in pool.map(download,dict.fromkeys(x['imageURL'] for x in items)):photos[url]=m;manifest.append(m)
cards=[];audit=[]
for item in items:
 volumes=re.findall(r'\d+\s*см\.\s*\d+\s*гр\.',item['volume']) if len(item['prices'])>1 else [item['volume']]
 if len(volumes)!=len(item['prices']):raise ValueError('Portion/price pairing missing '+item['title'])
 photo=photos[item['imageURL']];base=hashlib.sha256((item['imageURL']+'|'+item['title']).encode()).hexdigest()[:12]
 for j,(volume,price) in enumerate(zip(volumes,item['prices'])):
  id='90-kitchen-'+base+'-'+str(j+1);name=item['title']+(' · '+re.search(r'\d+\s*см',volume)[0] if len(volumes)>1 else '')
  category='Всяко разно' if item['title'] in ('Хлебная корзина','Фокачча с розмарином') else item['category']
  payload={'id':id,'brand':'90','menuSection':'kitchen','name':name,'category':category,'subcategory':'','volume':re.sub(r'\s+',' ',volume.replace('см.','см ·').replace('гр.','г')).strip(),'price':re.sub(r'\s*руб\.',' ₽',price).strip(),'description':item['description'],'vividDescription':'','taste':'','fact':'','features':'','ingredients':[],'composition':'','method':'','garnish':'','image':photo['path'],'imageKind':'dish','sortOrder':len(cards)}
  cards.append({'id':id,'kind':'menu','title':name,'course_id':None,'restaurant_id':None,'department':None,'published':True,'payload':payload})
  audit.append({'id':id,'sourceTitle':item['title'],'sourceTab':item['sourceTab'],'sourceVolume':item['volume'],'sourcePrices':item['prices'],'imageURL':item['imageURL']})
if len(cards)!=81:raise ValueError('Unexpected card count '+str(len(cards)))
def write(file,data):file.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n','utf8')
write(app/'supabase/90-kitchen-content-records.json',cards);write(app/'supabase/90-kitchen-assets-manifest.json',manifest)
sources=app/'supabase/sources';sources.mkdir(exist_ok=True);write(sources/'90-kitchen-site-20261024.json',{'url':'https://barkhimki.ru/menu','items':items,'mapping':audit})
uploadfile=app/'secure-dist/assets-manifest.json';upload=json.loads(uploadfile.read_text('utf8'));entries=upload if isinstance(upload,list) else upload['files']
for m in manifest:
 entries[:]=[e for e in entries if e['uploadName']!=m['file']];entries.append({'uploadName':m['file'],'paths':[m['path']],'bytes':m['bytes'],'sha256':m['sha256']})
uploadfile.write_text(json.dumps(upload,ensure_ascii=False,separators=(',',':'))+'\n','utf8')
q=lambda x:"'"+x.replace("'","''")+"'"
def sql(rows):return 'begin;\ninsert into public.academy_content(id,kind,title,course_id,restaurant_id,department,published,payload) values\n'+',\n'.join('('+','.join([q(d['id']),q('menu'),q(d['title']),'null','null','null','true',q(json.dumps(d['payload'],ensure_ascii=False,separators=(',',':')))+'::jsonb'])+')' for d in rows)+'\non conflict(id) do nothing;\ncommit;\n'
(app/'supabase/seed-90-kitchen-menu.sql').write_text('-- Active kitchen menu from barkhimki.ru/menu. Preserve administrator edits on repeats.\n'+sql(cards),'utf8')
for i in range(0,len(cards),27):(work/('seed-'+str(i//27)+'.sql')).write_text(sql(cards[i:i+27])+"select count(*) as imported_kitchen from public.academy_content where id like '90-kitchen-%';",'utf8')
print(json.dumps({'positions':len(items),'cards':len(cards),'photos':len(manifest),'bytes':sum(m['bytes'] for m in manifest),'categories':{c:sum(d['payload']['category']==c for d in cards) for c in dict.fromkeys(d['payload']['category'] for d in cards)}},ensure_ascii=False))
