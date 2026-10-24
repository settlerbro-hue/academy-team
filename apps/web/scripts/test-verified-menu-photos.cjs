const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('node:assert/strict');
const app=path.resolve(__dirname,'..'),root=path.resolve(app,'../..');
const audit=require('../supabase/verified-menu-photos-20261024.json'),content=require('../supabase/content-records.json'),manifest=require('../secure-dist/assets-manifest.json');
let count=0;
for(const photo of audit){
 assert(photo.sourcePage&&photo.sourceImage,'Each photo needs a traceable product source');
 assert(!/classic-|espresso|lemonade|winewhite|winered/.test(photo.image),'No illustrative category photos');
 const bytes=fs.readFileSync(path.join(root,'documents/menu',photo.image));
 assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),photo.sha256);
 const m=manifest.find(x=>x.paths.includes(photo.image));assert(m);assert.equal(m.sha256,photo.sha256);assert.equal(m.bytes,bytes.length);
 for(const id of photo.ids){assert.equal(content.find(x=>x.id===id).payload.image,photo.image);count++;}
}
assert.equal(audit.length,77);assert.equal(count,79);
console.log('PASS: 79 cards use 77 verified product photos; hashes, private upload manifest and exact card IDs agree. No illustrative serving photos.');
