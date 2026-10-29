const fs=require('fs'),path=require('path'),assert=require('assert/strict');
// The reviewed question set is an overlay on legacy imports, so rebuilding an
// unrelated course cannot restore the old first-ten-items tests or beer gate.
module.exports=function applyRevision(documents,privateKeys){
 const root=path.resolve(__dirname,'..'),file=root+'/supabase/rvb-assortment-tests-revision-20261029.json';if(!fs.existsSync(file))return [];
 const revisions=JSON.parse(fs.readFileSync(file,'utf8')),audit=JSON.parse(fs.readFileSync(root+'/supabase/sources/rvb-assortment-tests-audit-20261029.json','utf8')),answers=new Map(audit.questions.map(q=>[q.questionId,q.answer])),changed=[];
 for(const revision of revisions){const index=documents.findIndex(d=>d.id===revision.id);if(index<0)continue;documents[index]=structuredClone(revision);changed.push(revision.id);
  if(revision.kind==='test'&&revision.published){privateKeys[revision.id]=Object.fromEntries(revision.payload.questions.map(q=>{const answer=answers.get(q.id),i=q.options.indexOf(answer);assert(i>=0,'Missing reviewed answer: '+q.id);return [q.id,[i]];}));}
 }
 return changed;
};
