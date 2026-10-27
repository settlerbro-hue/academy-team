const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),cp=require('node:child_process'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),prefix=path.join(os.tmpdir(),'academy-build-'),temp=fs.mkdtempSync(prefix);
try{
 fs.cpSync(path.join(root,'secure-dist'),path.join(temp,'secure-dist'),{recursive:true});fs.copyFileSync(path.join(root,'build-secure.cjs'),path.join(temp,'build-secure.cjs'));fs.mkdirSync(path.join(temp,'.openai'));fs.writeFileSync(path.join(temp,'.openai/hosting.json'),'{}');
 const build=()=>{cp.execFileSync(process.execPath,[path.join(temp,'build-secure.cjs')],{stdio:'pipe'});return fs.readFileSync(path.join(temp,'out/index.html'),'utf8');};
 const first=build();const urls=[...first.matchAll(/(?:src|href)="([^"?]+\.(?:js|css))\?v=([a-f0-9]{12})"/g)];assert(urls.length>=10);for(const [,file,hash] of urls)assert.equal(hash,crypto.createHash('sha256').update(fs.readFileSync(path.join(temp,'out',file))).digest('hex').slice(0,12));
 assert.equal(build(),first,'Unchanged builds have stable asset URLs');fs.appendFileSync(path.join(temp,'secure-dist/portal.js'),'\n// cache verification\n');const second=build();assert.notEqual(second,first);assert.equal([...second.matchAll(/(?:src|href)="([^"?]+\.(?:js|css))\?v=([a-f0-9]{12})"/g)].filter((m,i)=>m[0]!==urls[i][0]).length,1,'Only the changed asset gets a new version');
 console.log('PASS: entry assets carry content versions, unchanged builds stay stable, changed JS receives a fresh URL.');
}finally{assert(path.resolve(temp).startsWith(path.resolve(prefix))&&path.dirname(temp)===path.resolve(os.tmpdir()));fs.rmSync(temp,{recursive:true,force:true});}
