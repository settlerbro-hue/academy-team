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
