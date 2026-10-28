const fs=require('fs'),vm=require('vm'),assert=require('assert/strict'),path=require('path');
const root=path.resolve(__dirname,'..'),src=fs.readFileSync(root+'/secure-dist/portal.js','utf8');
const esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const ctx={esc,ingredients:()=>[]};vm.createContext(ctx);
vm.runInContext(src.slice(src.indexOf('function studyText('),src.indexOf('function menuCategoryIcon(')),ctx);
const wines=JSON.parse(fs.readFileSync(root+'/supabase/wine-information-20261028.json','utf8'));
assert.equal(wines.length,51);assert.equal(new Set(wines.map(w=>w.id)).size,51);
for(const w of wines){const item=ctx.studyItem({category:'wine',description:w.description}),html=ctx.menuDescription(item);assert.equal(item.description,w.description,'Uncertainty and line breaks survive study cleanup: '+w.id);assert.equal((html.match(/<strong>/g)||[]).length,8,w.id);assert.equal(w.description.split('\n').length,8);assert(!w.description.includes('undefined'));}
assert(!ctx.menuDescription({category:'wine',description:'Вино: <img src=x onerror=alert(1)>\nСахар: <script>x</script>'}).includes('<script>'));
assert(ctx.menuDescription({category:'cocktails',description:'Вино: <b>text</b>'}).includes('&lt;b&gt;'));
assert.equal(wines.filter(w=>w.id.startsWith('90-')).length,30);assert.equal(wines.filter(w=>w.id.startsWith('rvb-')).length,21);
console.log('PASS: 51 wines / 8 fields each; uncertain facts preserved; safe text rendering; other drinks unchanged.');
