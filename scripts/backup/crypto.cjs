const fs=require('node:fs'),crypto=require('node:crypto'),{pipeline}=require('node:stream/promises');
const MAGIC=Buffer.from('ASKBACKUP1\n');
async function seal(input,output,publicKey){
 const key=crypto.randomBytes(32),iv=crypto.randomBytes(12);
 const wrapped=crypto.publicEncrypt({key:publicKey,oaepHash:'sha256',padding:crypto.constants.RSA_PKCS1_OAEP_PADDING},key);
 const header=Buffer.from(JSON.stringify({algorithm:'RSA-OAEP-SHA256/AES-256-GCM',iv:iv.toString('base64'),key:wrapped.toString('base64')}));
 const len=Buffer.alloc(4);len.writeUInt32BE(header.length);
 const cipher=crypto.createCipheriv('aes-256-gcm',key,iv);cipher.setAAD(Buffer.concat([MAGIC,len,header]));
 fs.writeFileSync(output,Buffer.concat([MAGIC,len,header]),{mode:0o600});
 await pipeline(fs.createReadStream(input),cipher,fs.createWriteStream(output,{flags:'a',mode:0o600}));
 fs.appendFileSync(output,cipher.getAuthTag());key.fill(0);
}
async function open(input,output,privateKey){
 const handle=fs.openSync(input,'r'),prefix=Buffer.alloc(MAGIC.length+4);fs.readSync(handle,prefix,0,prefix.length,0);
 if(!prefix.subarray(0,MAGIC.length).equals(MAGIC))throw Error('Invalid backup format');
 const length=prefix.readUInt32BE(MAGIC.length);if(length>8192)throw Error('Invalid header');
 const header=Buffer.alloc(length);fs.readSync(handle,header,0,length,prefix.length);const meta=JSON.parse(header),size=fs.fstatSync(handle).size;
 const tag=Buffer.alloc(16);fs.readSync(handle,tag,0,16,size-16);fs.closeSync(handle);
 const key=crypto.privateDecrypt({key:privateKey,oaepHash:'sha256',padding:crypto.constants.RSA_PKCS1_OAEP_PADDING},Buffer.from(meta.key,'base64'));
 const decipher=crypto.createDecipheriv('aes-256-gcm',key,Buffer.from(meta.iv,'base64'));decipher.setAAD(Buffer.concat([prefix,header]));decipher.setAuthTag(tag);
 const temp=output+'.unverified';
 try{await pipeline(fs.createReadStream(input,{start:prefix.length+length,end:size-17}),decipher,fs.createWriteStream(temp,{flags:'wx',mode:0o600}));fs.renameSync(temp,output);}catch(e){fs.rmSync(temp,{force:true});throw e;}finally{key.fill(0);}
}
module.exports={seal,open};
if(require.main===module)(async()=>{const [mode,input,output,keyfile]=process.argv.slice(2);if(mode==='seal')await seal(input,output,fs.readFileSync(keyfile));else if(mode==='open')await open(input,output,fs.readFileSync(keyfile));else throw Error('Use seal/open INPUT OUTPUT KEYFILE');})().catch(()=>{console.error('Backup encryption/decryption failed');process.exitCode=1;});
