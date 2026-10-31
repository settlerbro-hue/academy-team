const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{execFileSync}=require('node:child_process');
const {seal,open}=require('./crypto.cjs'),{backup}=require('./storage.cjs');
const {connection}=require('./db-connection.cjs');
const example='p@ss:/?#%+ &';
assert.equal(decodeURIComponent(new URL(connection({SUPABASE_DB_PASSWORD:example})).password),example);
assert.equal(new URL(connection({SUPABASE_DB_PASSWORD:example})).searchParams.get('sslmode'),'require');
assert.throws(()=>connection({}));
assert.equal(connection({SUPABASE_DB_URL:'postgresql://example'}),'postgresql://example');
(async()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'academy-backup-test-'));
 try{
  const {publicKey,privateKey}=crypto.generateKeyPairSync('rsa',{modulusLength:2048});
  const original=crypto.randomBytes(123457);fs.writeFileSync(path.join(dir,'plain'),original);
  await seal(path.join(dir,'plain'),path.join(dir,'sealed'),publicKey);await open(path.join(dir,'sealed'),path.join(dir,'restored'),privateKey);assert.deepEqual(fs.readFileSync(path.join(dir,'restored')),original);
  const broken=fs.readFileSync(path.join(dir,'sealed'));broken[broken.length-25]^=1;fs.writeFileSync(path.join(dir,'broken'),broken);
  await assert.rejects(open(path.join(dir,'broken'),path.join(dir,'invalid'),privateKey));assert(!fs.existsSync(path.join(dir,'invalid')));assert(!fs.existsSync(path.join(dir,'invalid.unverified')));
  const request=async(url,opts)=>{const route=new URL(url).pathname;if(route.endsWith('/bucket'))return Response.json([{id:'private'}]);if(route.includes('/object/list/')){const {prefix,offset}=JSON.parse(opts.body);return Response.json(offset?[]:prefix?[{id:'2',name:'файл.pdf',metadata:{size:3}}]:[{id:null,name:'nested',metadata:null},{id:'1',name:'../name',metadata:{size:3}}]);}return new Response(Buffer.from('abc'));};
  const manifest=await backup({url:'https://example.supabase.co',key:'test',dir:path.join(dir,'storage'),request});assert.equal(manifest.objects.length,2);assert.equal(fs.readdirSync(path.join(dir,'storage/objects')).length,2);assert(manifest.objects.every(o=>/^[a-f0-9]{64}$/.test(o.local)));
  const site=path.join(dir,'site');fs.mkdirSync(path.join(site,'out'),{recursive:true});fs.writeFileSync(path.join(site,'out/index.html'),'test');
  execFileSync(process.execPath,[path.join(__dirname,'site.cjs'),'create',site]);execFileSync(process.execPath,[path.join(__dirname,'site.cjs'),'verify',site]);fs.writeFileSync(path.join(site,'out/index.html'),'corrupted');assert.throws(()=>execFileSync(process.execPath,[path.join(__dirname,'site.cjs'),'verify',site],{stdio:'pipe'}));
  console.log('PASS: encryption roundtrip, tamper rejection, private nested Storage objects, path safety, site checksum corruption');
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
})().catch(e=>{console.error(e);process.exitCode=1;});
