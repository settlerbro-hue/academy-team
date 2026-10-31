const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const src=fs.readFileSync(path.join(__dirname,'../secure-dist/portal.js'),'utf8');
let now=Date.parse('2026-10-28T12:00:00Z'),scheduled,removed=false,clearedClass=false;
class Clock extends Date{static now(){return now;}}
const badge={dataset:{newUntil:new Date(now+1000).toISOString()},remove(){removed=true;},closest(){return {classList:{remove(n){assert.equal(n,'has-new-badge');clearedClass=true;}}};}};
let selected=[];const ctx={Date:Clock,console,esc:String,globalManager:()=>true,venueManager:()=>false,s:{profile:{department:'Бар'}},$:()=>null,all:()=>removed?[]:[badge],setTimeout:(f,ms)=>{scheduled={f,ms};return 1;},clearTimeout:()=>{}};
vm.createContext(ctx);vm.runInContext(src.split('\n').find(l=>l.startsWith('const departments='))+'\nlet menuNewTimer;\n'+['menuIsNew','menuNewBadge','localDateTime','menuNewFields','bindMenuNews','libraryAccessFields','readLibraryAccess','ranking'].map(n=>src.split('\n').find(l=>l.startsWith('function '+n+'('))).join('\n'),ctx);
const active={isNewItem:true,newBadgeUntil:new Date(now+1000).toISOString()};assert(ctx.menuIsNew(active));assert(!ctx.menuIsNew({...active,isNewItem:'true'}));assert(!ctx.menuIsNew({...active,newBadgeUntil:'bad'}));assert(!ctx.menuIsNew(active,now+1000));assert(ctx.menuNewBadge(active).includes('Новинка'));assert(!ctx.menuNewBadge({}).includes('Новинка'));
ctx.bindMenuNews();assert.equal(scheduled.ms,1000);now+=1000;scheduled.f();assert(removed&&clearedClass,'An open page removes expired badges without rerendering');
assert(ctx.menuNewFields({},true).includes('checked'));assert(ctx.menuNewFields({},false).includes('disabled'));
const fd=entries=>({has:k=>entries.some(([n])=>n===k),getAll:k=>entries.filter(([n])=>n===k).map(([,v])=>v)});
const legacy={brand:'rvb',body:'Keep body',audiencePositions:['Бармен']};assert.equal(ctx.readLibraryAccess(fd([]),legacy),null);assert.deepEqual(legacy,{brand:'rvb',body:'Keep body',audiencePositions:['Бармен']});
assert(ctx.libraryAccessFields({payload:{}}).includes('id="library-access-choices" disabled'));assert(!ctx.libraryAccessFields({payload:{}}).includes('id="library-access-enabled" checked'));
const p={body:'Keep body'};assert.equal(ctx.readLibraryAccess(fd([['libraryAccessEnabled','on'],['libraryDepartments','Бар'],['libraryPositions','Барбэк']]),p),'Бар');assert.equal(p.libraryAccess.positions[0],'Барбэк');
assert.throws(()=>ctx.readLibraryAccess(fd([['libraryAccessEnabled','on']]),{}));assert.throws(()=>ctx.readLibraryAccess(fd([['libraryAccessEnabled','on'],['libraryDepartments','Бар'],['libraryPositions','Повар']]),{}));
assert.equal(ctx.readLibraryAccess(fd([['libraryAccessEnabled','on'],['libraryDepartments','Бар'],['libraryDepartments','Кухня'],['libraryPositions','Повар']]),{}),null);
const rank=ctx.ranking();assert(rank.includes('Рейтинг в разработке'));assert(rank.includes('aria-hidden="true"'));assert(!rank.includes('rank-member'));assert(!src.includes("rpc('academy_ranking')"));
console.log('PASS: badge expiry and live timer; optional library defaults, job/department validation; ranking placeholder contains no staff data or ranking requests.');

ctx.libraryMatchesText=p=>!ctx.s.filter||JSON.stringify(p).toLowerCase().includes(ctx.s.filter.toLowerCase());ctx.librarySearchStatus=()=>'';
vm.runInContext(['libraryDepartments','libraryDepartmentBadges','libraryMatchesDepartment','library','bindLibraryDepartment'].map(n=>src.split('\n').find(l=>l.startsWith('function '+n+'('))).join('\n'),ctx);
assert.deepEqual(Array.from(ctx.libraryDepartments({department:'Бар',payload:{department:'Все'}})),['Бар']);
assert.deepEqual(Array.from(ctx.libraryDepartments({department:null,payload:{department:'Все'}})),['Все подразделения']);
assert.deepEqual(Array.from(ctx.libraryDepartments({payload:{libraryAccess:{enabled:true,departments:['Зал','Бар','Зал']}}})),['Зал','Бар']);
assert.deepEqual(Array.from(ctx.libraryDepartments({department:'Кухня',payload:{libraryAccess:{enabled:false,departments:['Бар']}}})),['Кухня']);
assert.deepEqual(Array.from(ctx.libraryDepartments({payload:{libraryAccess:{enabled:true,departments:[]}}})),['Не указано']);
ctx.esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
assert(!ctx.libraryDepartmentBadges({department:'<script>alert(1)</script>'}).includes('<script>'));
const docs=[{id:'bar',kind:'material',published:true,department:'Бар',title:'Вино',payload:{}},{id:'all',kind:'material',published:true,department:null,title:'Для команды',payload:{}}];ctx.kind=()=>docs;ctx.payload=d=>({...d,...d.payload});ctx.s.brand='';ctx.s.filter='';const libraryHTML=ctx.library();assert.equal((libraryHTML.match(/aria-label="Подразделения"/g)||[]).length,2);assert(libraryHTML.includes('Все подразделения'));assert(libraryHTML.includes('>Бар</span>'));assert(src.includes("libraryDepartmentBadges(d)+'<article class=\"card lesson-body\">"));
console.log('PASS: department badges in library cards and reader; shared and multiple departments, active access settings, legacy metadata and escaped labels.');

const filterDocs=[{id:'wine',kind:'material',published:true,title:'Вино',department:'Бар',payload:{brand:'rvb'}},{id:'service',kind:'material',published:true,title:'Сервис',department:'Зал',payload:{brand:'rvb'}},{id:'food',kind:'material',published:true,title:'Кухня',department:'Кухня',payload:{brand:'90'}},{id:'shared',kind:'material',published:true,title:'Общие правила',payload:{brand:'common'}},{id:'both',kind:'material',published:true,title:'Бар и зал',payload:{brand:'rvb',libraryAccess:{enabled:true,departments:['Бар','Зал']}}}];
ctx.kind=()=>filterDocs;ctx.s.libraryDepartment='Бар';ctx.s.brand='';ctx.s.filter='';let filtered=ctx.library();assert(filtered.includes('data-material="wine"')&&filtered.includes('data-material="both"'));for(const id of ['shared','service','food'])assert(!filtered.includes('data-material="'+id+'"'));
ctx.s.libraryDepartment='common';filtered=ctx.library();assert(filtered.includes('data-material="shared"'));assert(!filtered.includes('data-material="wine"'));
ctx.s.libraryDepartment='Кухня';ctx.s.brand='rvb';assert(!ctx.library().includes('data-material="food"'));ctx.s.brand='90';assert(ctx.library().includes('data-material="food"'));
ctx.s.libraryDepartment='Бар';ctx.s.brand='rvb';ctx.s.filter='вино';filtered=ctx.library();assert(filtered.includes('data-material="wine"'));assert(!filtered.includes('data-material="both"'));assert(filtered.includes('value="Бар" selected'));
ctx.s.libraryDepartment='';ctx.s.brand='';ctx.s.filter='';assert.equal((ctx.library().match(/data-material=/g)||[]).length,filterDocs.length);
let change,renderCount=0,focused=false;const selection={value:'Зал',addEventListener(event,fn){assert.equal(event,'change');change=fn;},focus(){focused=true;}};ctx.$=selector=>selector==='#library-department'?selection:selector==='#search'?{value:'сервис'}:null;ctx.clearTimeout=()=>{};ctx.render=()=>renderCount++;vm.runInContext('let searchDebounce;',ctx);ctx.bindLibraryDepartment();change();assert.equal(ctx.s.libraryDepartment,'Зал');assert.equal(ctx.s.filter,'сервис');assert.equal(renderCount,1);assert(focused);
console.log('PASS: department filter combines with brand/search; shared and multi-department materials handled; selection and in-progress search preserved.');
