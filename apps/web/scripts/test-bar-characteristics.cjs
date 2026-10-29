const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert/strict');
const root=path.resolve(__dirname,'..'),data=require(root+'/supabase/bar-characteristics-20261029.json');
const fields=['countryCategory','styleDescription','productionMethod','tastingNotes','positioning','gastronomy'];
assert.equal(data.length,375);assert.equal(new Set(data.map(x=>x.id)).size,375);
const counts={};for(const r of data){counts[r.category]=(counts[r.category]||0)+1;assert(!r.id.startsWith('qa-'));assert(r.sources.length);for(const s of r.sources)assert(/^https:\/\/|^menu:(90|rvb)$/.test(s));assert(Object.keys(r.patch).every(k=>fields.includes(k)));for(const v of Object.values(r.patch))assert(typeof v==='string'&&v.trim()&&!v.includes('undefined'));}
assert.deepEqual(counts,{wine:51,alcohol:125,sets:22,tinctures:15,cocktails:96,nonalcoholic:44,hot:22});
const get=n=>data.find(r=>r.name===n).patch;
assert(get('Tanqueray London Dry').productionMethod.includes('четырёхкратную'));
assert(!JSON.stringify(get('Tanqueray London Dry')).includes('47,3'));
assert(get('Zacapa 23').productionMethod.includes('не означает'));
assert(get('Singleton 12 YO').productionMethod.includes('Glendullan'));
assert(get('Beluga Noble').countryCategory.includes('контрэтикетке'));
assert(get('Аливария Белое Золото').countryCategory.includes('лагер'));
assert(get('Jack Daniel`s Old №7').countryCategory.includes('Tennessee'));
assert(!get('Джинстер Пломбир').tastingNotes.includes('кола'));
for(const r of data.filter(r=>r.category==='tinctures'))assert(r.patch.tastingNotes.includes('Ориентир по названию'));
for(const r of data.filter(r=>r.category==='cocktails'))assert(r.patch.tastingNotes.includes('Ожидаемый профиль по составу'));
const src=fs.readFileSync(root+'/secure-dist/portal.js','utf8'),esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const ctx={esc,ingredients:()=>[]};vm.createContext(ctx);vm.runInContext(src.slice(src.indexOf('function studyText('),src.indexOf('function menuCategoryIcon(')),ctx);
const example=get('Tanqueray London Dry'),html=ctx.menuDetails(example);assert.equal((html.match(/<h4>/g)||[]).length,6);assert(html.includes('Подробнее'));assert(html.indexOf('Способ производства')<html.indexOf('Дегустационные характеристики'));
for(const k of fields){assert(ctx.menuDetails({[k]:'<img src=x onerror=alert(1)>'}).includes('&lt;img'));assert(ctx.menuDetailsEditor({[k]:'<script>x</script>'}).includes('name="'+k+'">&lt;script&gt;'));}
assert(ctx.menuDetails({method:'Сохранённая рецептура',garnish:'Исходная подача'}).includes('Сохранённая рецептура'));
console.log('PASS: 375 real bar cards; six editable escaped Details fields; product distinctions and uncertainty; legacy recipes remain supported.');
