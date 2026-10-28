const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const src=fs.readFileSync(path.join(__dirname,'../secure-dist/portal.js'),'utf8');
const ctx={esc:x=>String(x).replaceAll("<","&lt;"),s:{profile:{id:'owner'}},globalManager:()=>true,venueManager:()=>false,venueRestaurants:()=>({minsk:'РВБ'}),options:(o,v)=>Object.keys(o).join('|'),document:{createElement:()=>({className:'',hidden:true,textContent:''})}};vm.createContext(ctx);
for(const line of src.split('\n').filter(l=>/^const (restaurants|workRestaurants|departments)=|^function (bindWorkScope|workFields|companyCaptionField|displayPosition)\(/.test(l)))vm.runInContext(line,ctx);
vm.runInContext('globalThis.physical=restaurants;globalThis.work=workRestaurants;',ctx);assert.equal(Object.keys(ctx.physical).length,4);assert.equal(ctx.work.network,'МХП & РВБ');
assert(ctx.workFields({id:'target'}).includes('network'));ctx.globalManager=()=>false;assert(!ctx.workFields({id:'target'}).includes('network'));assert(ctx.workFields({id:'owner'}).includes('network'));
const input=value=>({value,innerHTML:'',addEventListener(event,fn){this[event]=fn;},closest(){return {after(){}};}}),r=input('network'),d=input('Бар'),p=input('Бармен'),hint={};
ctx.bindWorkScope({elements:{r,d,p},querySelector:()=>hint},'r','d','p');assert.equal(p.value,'Управляющая компания');assert.equal(d.innerHTML,'Руководитель');assert.equal(hint.hidden,false);
r.value='minsk';r.change();assert(d.innerHTML.includes('Бар'));assert.equal(hint.hidden,true);
assert(!src.match(/function venueAccessButton[^\n]+!workRestaurants/));
console.log('PASS: four physical venues remain separate; network affiliation option, scope-aware editor visibility and leadership-only selection.');

assert.equal(ctx.displayPosition({restaurant_id:'network',position:'Управляющая компания',position_caption:'Руководитель обучения'}),'Руководитель обучения');assert.equal(ctx.displayPosition({restaurant_id:'minsk',position:'Бармен',position_caption:'Владелец'}),'Бармен');assert(ctx.companyCaptionField({restaurant_id:'network',position_caption:'<script>'}).includes('&lt;script>'));
