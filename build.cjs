const fs=require('node:fs'),path=require('node:path'),{execFileSync}=require('node:child_process');
const root=__dirname;
execFileSync(process.execPath,[path.join(root,'apps/web/build-secure.cjs')],{stdio:'inherit'});
const src=path.join(root,'apps/web/out'),out=path.join(root,'out');
const walk=d=>fs.readdirSync(d,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(d,e.name)):[path.relative(d,path.join(d,e.name))]);
function files(d,prefix=''){return fs.readdirSync(d,{withFileTypes:true}).flatMap(e=>e.isDirectory()?files(path.join(d,e.name),prefix+e.name+'/'):[prefix+e.name]);}
const allowed=new Set(files(src));
if(fs.existsSync(out))for(const name of files(out))if(!allowed.has(name))throw Error('Unexpected public file: '+name);
fs.cpSync(src,out,{recursive:true});
console.log('Cloud workspace build: out/');
