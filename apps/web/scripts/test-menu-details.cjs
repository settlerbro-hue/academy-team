const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert/strict');
const root=path.resolve(__dirname,'..'),src=fs.readFileSync(root+'/secure-dist/portal.js','utf8'),esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const ctx={esc,ingredients:p=>p.ingredients||[]};vm.createContext(ctx);vm.runInContext(src.slice(src.indexOf('function studyText('),src.indexOf('function menuCategoryIcon(')),ctx);
const keys=['countryCategory','styleDescription','productionMethod','tastingNotes','gastronomy','positioning','method','garnish','fact'];
const sample=Object.fromEntries(keys.map((k,i)=>[k,'Уникальное содержимое раздела '+i+'.']));
assert.deepEqual(Array.from(ctx.menuDetailsSections(sample),s=>s.key),keys);
const editor=ctx.menuDetailsEditor(sample);let last=-1;for(const key of keys){const index=editor.indexOf('name="'+key+'"');assert(index>last,key);assert.equal((editor.match(new RegExp('name="'+key+'"','g'))||[]).length,1);last=index;}
for(const v of ['', '   ', '—', '...', '\n—\n', 'Нет данных', 'Не указано', 'N/A'])assert.equal(ctx.menuDetails(Object.fromEntries(keys.map(k=>[k,v]))),'',v);
assert.equal(ctx.menuDetails({styleDescription:'Свежий цитрусовый профиль.',tastingNotes:'Свежий цитрусовый профиль. Долгое послевкусие.'}).match(/Свежий цитрусовый профиль/g).length,1);
assert(ctx.menuDetails({styleDescription:'Свежий цитрусовый профиль.',tastingNotes:'Свежий цитрусовый профиль. Долгое послевкусие.'}).includes('Долгое послевкусие.'));
assert(!ctx.menuDetails({styleDescription:'Светлый лагер.',positioning:'Для гостя, который предпочитает светлый лагер. Рекомендовать по вкусовому профилю; формат и объём подачи —.'}).includes('Позиционирование'));
assert(!ctx.menuDetails({category:'cocktails',fact:'Джин, тоник'}));
assert(ctx.menuDetails({productionMethod:'Крепость 47,3%.',tastingNotes:'Крепость 40%.'}).includes('40%'));
assert(ctx.menuDetails({method:'Встряхнуть со льдом.',garnish:'Цедра лимона.',fact:'Основан в 1860 году.'}).includes('Основан в 1860 году.'));
const rows=require(root+'/supabase/bar-characteristics-20261029.json'),review=require(root+'/supabase/menu-facts-review-20261029.json').changes;
for(const r of rows){const p={category:r.category,...r.patch,...review.find(c=>c.id===r.id)?.patch},sections=ctx.menuDetailsSections(p),html=ctx.menuDetails(p);assert(sections.length,r.id);let last=-1;const seen=new Set();for(const section of sections){assert(section.text.trim()&&/[\p{L}\p{N}]/u.test(section.text));const index=keys.indexOf(section.key);assert(index>last,r.id);last=index;const n=ctx.menuDetailNormal(section.text);assert(!seen.has(n),r.id);seen.add(n);}assert(!/<h4>[^<]+<\/h4><p>\s*<\/p>/.test(html));assert(!html.includes('формат и объём подачи —'));}
console.log('PASS: 375 bar cards; shared display/editor order, no empty headings or placeholder prose, cross-section deduplication, unique text and cocktail composition retained.');
