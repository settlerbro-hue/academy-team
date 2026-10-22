const fs=require('node:fs'),path=require('node:path');
const root=__dirname,src=path.join(root,'secure-dist'),out=path.join(root,'out');
const walk=d=>fs.readdirSync(d,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(d,e.name)):[path.join(d,e.name)]);
const allowed=new Set(['index.html','portal.js','portal.css','material-files.js','material-files.css','pdf-viewer.js','vendor/pdf.js','vendor/pdf.worker.js','vendor/LICENSE.pdfjs','auth-config.js','assets-manifest.json','vendor/supabase.js','vendor/LICENSE.supabase','assets/brand90/logo.svg','assets/rvb/team-logo.png']);
for(const file of walk(src)){const name=path.relative(src,file).replaceAll('\\','/');if(!allowed.has(name))throw Error('Unexpected public file: '+name);}
if(fs.existsSync(out))for(const file of walk(out)){const name=path.relative(out,file).replaceAll('\\','/');if(!allowed.has(name))throw Error('Unexpected old public file: '+name);}
fs.mkdirSync(out,{recursive:true});fs.cpSync(src,out,{recursive:true});
const manifest=JSON.parse(fs.readFileSync(path.join(root,'.openai/hosting.json')));manifest.static={directory:'out'};fs.writeFileSync(path.join(root,'.openai/hosting.json'),JSON.stringify(manifest,null,2)+'\n');
console.log('Protected portal public build:',walk(out).length,'files. Training content, keys and documents excluded.');
