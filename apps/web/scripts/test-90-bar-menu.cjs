const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),vm=require('node:vm');
const root=path.join(__dirname,'..'),cards=require('../supabase/90-bar-content-records.json'),assets=require('../supabase/90-bar-assets-manifest.json');
assert.equal(cards.length,200);assert.equal(new Set(cards.map(d=>d.id)).size,200);assert.equal(assets.length,22);
for(const d of cards){assert.equal(d.kind,'menu');assert.equal(d.restaurant_id,null);assert.equal(d.department,null);assert.equal(d.payload.brand,'90');assert.equal(d.payload.menuSection,'bar');assert.match(d.payload.price,/₽/);assert(!/поменяйте|прописать|строки|новая цена/i.test(JSON.stringify(d.payload)));}
const byRow=n=>cards.filter(d=>d.id.startsWith('90-bar-r'+String(n).padStart(3,'0')+'-'));
assert.equal(byRow(5)[0].payload.volume,'150 мл');assert.equal(byRow(5)[0].payload.price,'640 ₽');assert.equal(byRow(98)[0].payload.price,'790 ₽');
assert.equal(byRow(42).length,3);assert.equal(byRow(106).length,5);assert.equal(byRow(107).length,2);assert.equal(byRow(205)[0].payload.volume,'50 мл');assert.equal(byRow(205)[1].payload.volume,'120 мл');assert.equal(byRow(215).length,0);assert.equal(byRow(216).length,0);
assert.equal(byRow(220)[0].payload.price,'1380 ₽');assert.equal(byRow(119)[0].payload.ingredients.length,6);assert(byRow(131)[0].payload.composition.includes('адвокат'),'Use sheet recipe, not conflicting PDF recipe');
for(const a of assets){const d=cards.find(d=>d.id===a.itemId);assert.equal(d.payload.image,a.path);assert(a.bytes>1000);}
const source=fs.readFileSync(path.join(root,'secure-dist/portal.js'),'utf8'),actor={role:'manager',status:'active',restaurant_id:'pushkino',department:'Бар'};
const ctx={s:{profile:actor},menuSectionOf:d=>d.payload.menuSection};vm.createContext(ctx);vm.runInContext(source.slice(source.indexOf('function canEdit(')).split('\n')[0]+'\nglobalThis.edit=canEdit;',ctx);
for(const restaurant of ['pushkino','khimki','mytishchi']){actor.restaurant_id=restaurant;assert(ctx.edit(cards[0]));actor.department='Кухня';assert(!ctx.edit(cards[0]));actor.department='Бар';}
actor.restaurant_id='minsk';assert(!ctx.edit(cards[0]));actor.restaurant_id='pushkino';actor.role='employee';assert(!ctx.edit(cards[0]));actor.role='admin';assert(ctx.edit(cards[0]));
console.log('PASS: 200 shared 90-е bar cards, source prices / recipes, 22 PDF photos, variants, all three bar administrator scopes and denials.');
