const fs=require('fs'),vm=require('vm'),assert=require('assert/strict'),path=require('path');
const root=path.resolve(__dirname,'..'),src=fs.readFileSync(root+'/secure-dist/portal.js','utf8'),d=require('../supabase/bar-drinks-guide.json');
assert.equal(d.id,'bar-drinks-guide');assert.equal(d.kind,'material');assert.equal(d.department,'Бар');assert.equal(d.restaurant_id,null);assert.equal(d.payload.brand,'common');assert.equal(d.payload.format,'handbook');assert.equal(d.payload.sectionCount,11);
assert.equal((d.payload.body.match(/<details/g)||[]).length,11);assert.equal((d.payload.body.match(/<summary>/g)||[]).length,11);assert(!/<script|<iframe|onerror=|javascript:/i.test(d.payload.body));
assert(d.payload.body.includes('Источники:'));assert(d.payload.body.includes('37,5%'));assert(d.payload.body.includes('35–55%'));assert(d.payload.body.includes('XO — десять'));assert(d.payload.body.includes('19 января 2025'));
const ctx={docs:[],kind:()=>ctx.docs};vm.createContext(ctx);vm.runInContext(src.slice(src.indexOf('function barKnowledgeEntry('),src.indexOf('function menu(){')),ctx);
assert.equal(ctx.barKnowledgeEntry('bar'),'','No entry if server does not deliver the material');ctx.docs=[{id:d.id,published:false}];assert.equal(ctx.barKnowledgeEntry('bar'),'','Do not expose drafts');ctx.docs=[d];assert.equal(ctx.barKnowledgeEntry('kitchen'),'');assert(ctx.barKnowledgeEntry('bar').includes('href="#/library/bar-drinks-guide"'));
assert(src.includes('${barKnowledgeEntry(scope.section)}'));assert(!fs.readFileSync(root+'/build-secure.cjs','utf8').includes('bar-drinks-guide.json'),'Content is private, not a public build asset');
console.log('PASS: 11 protected bar sections, common brand scope, no draft/unauthorized/kitchen entry, existing deep link, safe content.');
