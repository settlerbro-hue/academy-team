const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{Readable}=require('node:stream'),{pipeline}=require('node:stream/promises');
async function backup({url,key,dir,request=fetch}){
 const base=new URL(url);if(base.protocol!=='https:')throw Error('HTTPS required');
 const headers={apikey:key,Authorization:`Bearer ${key}`};
 async function api(route,body){for(let attempt=0;attempt<4;attempt++){const res=await request(new URL('/storage/v1/'+route,base),{method:body?'POST':'GET',headers:{...headers,...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(120000),redirect:'error'});if(res.ok)return res;if(res.status!==429&&res.status<500)throw Error(`Storage request failed (${res.status})`);await new Promise(r=>setTimeout(r,1000*2**attempt));}throw Error('Storage request retries exhausted');}
 fs.mkdirSync(path.join(dir,'objects'),{recursive:true,mode:0o700});
 const buckets=await (await api('bucket')).json();if(!Array.isArray(buckets))throw Error('Invalid bucket response');
 const manifest={format:1,startedAt:new Date().toISOString(),buckets,objects:[]};
 async function list(bucket,prefix=''){
  const all=[];for(let offset=0;;offset+=1000){const rows=await(await api('object/list/'+encodeURIComponent(bucket),{prefix,limit:1000,offset,sortBy:{column:'name',order:'asc'}})).json();if(!Array.isArray(rows))throw Error('Invalid listing');all.push(...rows);if(rows.length<1000)break;}
  for(const item of all){const name=prefix?prefix+'/'+item.name:item.name;if(!item.id&&!item.metadata){await list(bucket,name);continue;}
   const local=crypto.createHash('sha256').update(JSON.stringify([bucket,name])).digest('hex');
   const response=await api('object/'+encodeURIComponent(bucket)+'/'+name.split('/').map(encodeURIComponent).join('/'));
   const hash=crypto.createHash('sha256');let bytes=0;const source=Readable.fromWeb(response.body);source.on('data',chunk=>{hash.update(chunk);bytes+=chunk.length;});
   await pipeline(source,fs.createWriteStream(path.join(dir,'objects',local),{flags:'wx',mode:0o600}));
   if(item.metadata?.size!=null&&Number(item.metadata.size)!==bytes)throw Error('Object changed during backup');
   manifest.objects.push({bucket,name,local,bytes,sha256:hash.digest('hex'),metadata:item.metadata});
  }
 }
 for(const bucket of buckets)await list(bucket.id);
 manifest.finishedAt=new Date().toISOString();fs.writeFileSync(path.join(dir,'manifest.json'),JSON.stringify(manifest,null,2),{mode:0o600});
 console.log(`Storage backed up: ${buckets.length} buckets, ${manifest.objects.length} objects`);return manifest;
}
module.exports={backup};
if(require.main===module){const {SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY}=process.env;if(!SUPABASE_URL||!SUPABASE_SERVICE_ROLE_KEY)throw Error('Missing Storage backup secrets');backup({url:SUPABASE_URL,key:SUPABASE_SERVICE_ROLE_KEY,dir:process.argv[2]}).catch(()=>{console.error('Storage backup failed; no complete backup will be published');process.exitCode=1;});}
