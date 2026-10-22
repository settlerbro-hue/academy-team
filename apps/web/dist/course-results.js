// Read-only calculations shared by ranking and manager progress.
function courseResults(employee, course, period='all', now=Date.now()) {
 const p=employee.courseProgress?.[course.id] || (activeCourse()?.id===course.id?employee:{read:[],attempts:[]});
 const read=[...new Set(p.read||[])].filter(i=>Number.isInteger(i)&&i>=0&&i<course.lessons.length).length;
 const tests=globalThis.COURSE_ASSESSMENTS?.[course.id]||course.assessments||[];
 const cutoff=period==='all'?-Infinity:now-Number(period)*86400000;
 const inPeriod=a=>{const date=Date.parse(a.review?.date||a.date);return date>=cutoff&&date<=now;};
 const score=a=>a.total>0&&Number.isFinite(a.correct)?Math.max(0,Math.min(1,a.correct/a.total)):null;
 if(!tests.length){
  const attempts=(p.attempts||[]).filter(inPeriod),final=attempts.filter(a=>Number.isFinite(a.score));
  const passed=final.some(a=>a.passed),total=course.questions?.length?1:0;
  return {imported:false,read,lessons:course.lessons.length,lessonProgress:Math.round(read/Math.max(1,course.lessons.length)*100),progress:Math.round((read+Number(passed))/(Math.max(1,course.lessons.length+total))*100),score:final.length?Math.max(...final.map(a=>a.score)):null,attempts,passedTests:Number(passed),testTotal:total,pending:0,drafts:0,status:passed?'passed':final.length?'failed':'none',complete:read===course.lessons.length&&(!total||passed),details:[],last:final.slice().sort((a,b)=>Date.parse(b.date)-Date.parse(a.date))[0]||null};
 }
 const details=tests.map(t=>{
  const saved=employee.assessmentProgress?.[course.id]?.[t.id];
  const attempts=(saved?.attempts||[]).filter(inPeriod);
  const finals=attempts.filter(a=>['passed','failed'].includes(a.status)&&score(a)!==null);
  const latest=attempts.slice().sort((a,b)=>Date.parse(b.review?.date||b.date)-Date.parse(a.review?.date||a.date))[0];
  const best=finals.reduce((best,a)=>!best||score(a)>score(best)?a:best,null);
  return {id:t.id,title:t.title,total:t.questions.length,attempts,best,bestScore:best?Math.round(score(best)*100):null,passed:finals.some(a=>a.status==='passed'),pending:latest?.status==='pending',draft:!!saved?.draft,latest};
 });
 const attempts=details.flatMap(t=>t.attempts.map(a=>({...a,assessmentId:t.id,title:t.title}))),finals=attempts.filter(a=>['passed','failed'].includes(a.status)&&score(a)!==null);
 const passedTests=details.filter(t=>t.passed).length,pending=details.filter(t=>t.pending).length,drafts=details.filter(t=>t.draft).length;
 const weighted=details.reduce((n,t)=>n+(t.best?score(t.best)*t.total:0),0),weight=details.reduce((n,t)=>n+t.total,0);
 return {imported:true,read,lessons:course.lessons.length,lessonProgress:Math.round(read/Math.max(1,course.lessons.length)*100),progress:Math.round((read+passedTests)/Math.max(1,course.lessons.length+tests.length)*100),score:finals.length?Math.round(weighted/Math.max(1,weight)*100):null,attempts,passedTests,testTotal:tests.length,pending,drafts,status:passedTests===tests.length?'passed':pending?'pending':passedTests||drafts?'progress':finals.length?'failed':'none',complete:read===course.lessons.length&&passedTests===tests.length,details,last:attempts.slice().sort((a,b)=>Date.parse(b.review?.date||b.date)-Date.parse(a.review?.date||a.date))[0]||null};
}
function resultStatus(status){return {passed:'Все тесты пройдены',pending:'Ожидает проверки',progress:'В процессе',failed:'Нужна пересдача',none:'Без попыток'}[status]||'В процессе';}
