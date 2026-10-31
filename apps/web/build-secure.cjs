const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=__dirname,src=path.join(root,'secure-dist'),out=path.join(root,'out');
const walk=d=>fs.readdirSync(d,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(d,e.name)):[path.join(d,e.name)]);
const allowed=new Set(["assets/fonts/geologica-cyrillic-ext.woff2","assets/fonts/geologica-cyrillic.woff2","assets/fonts/geologica-greek.woff2","assets/fonts/geologica-vietnamese.woff2","assets/fonts/geologica-latin-ext.woff2","assets/fonts/geologica-latin.woff2","assets/fonts/OFL-Geologica.txt",'favicon.ico','ask-icon-32.png','ask-icon-180.png','course-editor.js','course-editor.css','notifications.js','notifications.css','index.html','daily-facts.js','portal.js','portal.css','approved-design.css','design-adapter.css','material-files.js','material-files.css','pdf-viewer.js','vendor/pdf.js','vendor/pdf.worker.js','vendor/LICENSE.pdfjs','auth-config.js','assets-manifest.json','vendor/supabase.js','vendor/LICENSE.supabase','assets/brand90/logo.svg','assets/rvb/team-logo.png']);
for(const file of walk(src)){const name=path.relative(src,file).replaceAll('\\','/');if(!allowed.has(name))throw Error('Unexpected public file: '+name);}
if(fs.existsSync(out))for(const file of walk(out)){const name=path.relative(out,file).replaceAll('\\','/');if(!allowed.has(name))throw Error('Unexpected old public file: '+name);}
fs.mkdirSync(out,{recursive:true});fs.cpSync(src,out,{recursive:true});
// A content version prevents old browser assets from surviving a site update.
const html=fs.readFileSync(path.join(out,'index.html'),'utf8').replace(/\b(src|href)="([^"?#]+\.(?:js|css))"/g,(match,attr,name)=>{
 const file=path.resolve(out,name);if(!file.startsWith(out+path.sep)||!fs.existsSync(file))throw Error('Invalid entry asset: '+name);
 const version=crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex').slice(0,12);
 return attr+'="'+name+'?v='+version+'"';
});
fs.writeFileSync(path.join(out,'index.html'),html);
const manifest=JSON.parse(fs.readFileSync(path.join(root,'.openai/hosting.json')));manifest.static={directory:'out'};fs.writeFileSync(path.join(root,'.openai/hosting.json'),JSON.stringify(manifest,null,2)+'\n');
console.log('Protected portal public build:',walk(out).length,'files. Training content, keys and documents excluded.');
