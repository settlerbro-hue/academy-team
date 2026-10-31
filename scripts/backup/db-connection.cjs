const fs=require('node:fs');
function connection(env){
 if(env.SUPABASE_DB_URL)return env.SUPABASE_DB_URL;
 if(!env.SUPABASE_DB_PASSWORD)throw Error('Configure SUPABASE_DB_PASSWORD in Actions secrets');
 return 'postgresql://postgres.ivlinbwuudxyjaikwaoo:'+encodeURIComponent(env.SUPABASE_DB_PASSWORD)+'@aws-0-eu-west-1.pooler.supabase.com:5432/postgres?sslmode=require';
}
module.exports={connection};
if(require.main===module){
 try{const value=connection(process.env);if(/[\r\n]/.test(value)||!process.env.GITHUB_ENV)throw Error('Invalid runner environment');console.log('::add-mask::'+value);fs.appendFileSync(process.env.GITHUB_ENV,'SUPABASE_DB_URL='+value+'\n');}
 catch{console.error('Configure SUPABASE_DB_PASSWORD (or SUPABASE_DB_URL) in Actions secrets');process.exitCode=1;}
}
