const fs=require('node:fs'),assert=require('node:assert/strict'),path=require('node:path');
const base=path.join(__dirname,'../supabase'),cards=JSON.parse(fs.readFileSync(path.join(base,'kitchen-content-records.json'),'utf8')),images=JSON.parse(fs.readFileSync(path.join(base,'kitchen-assets-manifest.json'),'utf8'));
assert.equal(cards.length,92);assert.equal(new Set(cards.map(d=>d.id)).size,92);assert.equal(images.length,83);
const paths=new Set(images.map(i=>i.path));
for(const d of cards){assert.equal(d.restaurant_id,'minsk');assert.equal(d.department,null);assert.equal(d.payload.brand,'rvb');assert.equal(d.payload.menuSection,'kitchen');assert(paths.has(d.payload.image));assert.equal(d.payload.fact,'');assert.equal(d.payload.taste,'');assert.equal(d.payload.method,'');assert.deepEqual(d.payload.ingredients,[]);assert(d.payload.volume);assert(d.payload.price);}
assert.equal(cards.filter(d=>d.payload.category==='Пицца').length,19);
assert.equal(cards.find(d=>d.id==='rvb-kitchen-p35-1').payload.volume,'10 г','Preserve the PDF value; do not guess a correction');
assert.equal(cards.find(d=>d.id==='rvb-kitchen-p28-1').payload.description,'','Missing descriptions stay blank');
assert.equal(cards.find(d=>d.id==='rvb-kitchen-p31-3-2').payload.volume,'33 см · 550 г');
console.log('Kitchen import checks passed: 92 unique cards, 83 image links, 19 pizza portions, original values and empty missing fields.');
const vm=require('node:vm'),portal=fs.readFileSync(path.join(__dirname,'../secure-dist/portal.js'),'utf8');
const actor={role:'manager',restaurant_id:'minsk',department:'Кухня'},ctx={s:{profile:actor},menuSectionOf:d=>d.payload.menuSection};vm.createContext(ctx);
const editSource=portal.slice(portal.indexOf('function canEdit(')).split('\n')[0];vm.runInContext(editSource+'\nglobalThis.canEditCard=canEdit;',ctx);
assert(ctx.canEditCard(cards[0]));actor.department='Бар';assert(!ctx.canEditCard(cards[0]));actor.department='Кухня';actor.restaurant_id='pushkino';assert(!ctx.canEditCard(cards[0]));actor.restaurant_id='minsk';actor.role='employee';assert(!ctx.canEditCard(cards[0]));actor.role='admin';assert(ctx.canEditCard(cards[0]));
console.log('Kitchen editor visibility checks passed: owner / own kitchen manager only.');
