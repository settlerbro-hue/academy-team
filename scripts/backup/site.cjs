const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(process.argv[3]||'.'),mode=process.argv[2];
function walk(dir,prefix=''){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>{if(e.isSymbolicLink())throw Error('Symlinks are not allowed');if(e.isDirectory())return walk(path.join(dir,e.name),prefix+e.name+'/');if(!e.isFile())throw Error('Unexpected file type');return [prefix+e.name];}).sort();}
function inventory(){return walk(path.join(root,'out')).map(name=>({name,bytes:fs.statSync(path.join(root,'out',name)).size,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'out',name))).digest('hex')}));}
if(mode==='create'){
 const files=inventory();if(!files.some(f=>f.name==='index.html'))throw Error('Missing index.html');
 fs.writeFileSync(path.join(root,'site-manifest.json'),JSON.stringify({format:1,createdAt:new Date().toISOString(),commit:process.env.GITHUB_SHA||'local',runId:process.env.GITHUB_RUN_ID||null,files},null,2));
 console.log(`Site snapshot: ${files.length} files`);
}else if(mode==='verify'){
 const manifest=JSON.parse(fs.readFileSync(path.join(root,'site-manifest.json'),'utf8'));
 if(manifest.format!==1||JSON.stringify(inventory())!==JSON.stringify(manifest.files))throw Error('Site checksum/file inventory mismatch');
 console.log(`Verified ${manifest.files.length} files, commit ${manifest.commit}`);
}else throw Error('Use create or verify');
