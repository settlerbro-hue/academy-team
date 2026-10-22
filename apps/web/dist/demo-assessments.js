// Additive demo migration. Never seeds real employees or replaces saved attempts.
function addImportedDemoResults(){
 if(db.demoImportedResultsVersion>=1)return;
 const previous=structuredClone(db),now=Date.now();
 const scenarios={
  'demo-hostess-polina':'complete','demo-admin-maria':'pending','demo-anna':'partial',
  'demo-maxim':'retake','demo-daria':'failed','demo-ilya':'none',
  'demo-alina':'old30','demo-nikita':'old90','demo-pavel':'old120','demo-sofia':'draft',
  'demo-kitchen-anton':'complete','demo-kitchen-elena':'failed','demo-art-vera':'pending',
  'demo-art-roman':'none','demo-hookah-timur':'partial','demo-hookah-artem':'old90',
  'demo-leader-olga':'complete','demo-leader-denis':'old120',
  'demo-senior-egor':'retake','demo-barback-kirill':'draft'
 };
 const at=days=>new Date(now-days*86400000).toISOString();
 function attempt(test,kind,days,uid,sequence){
  const manual=test.questions.filter(q=>q.type==='text'),answers={};
  const wanted=kind==='passed'?test.questions.length:kind==='pending'?test.questions.length-manual.length:Math.floor(test.questions.length*.5);
  let correct=0;
  test.questions.forEach((q,i)=>{
   if(q.type==='text'){
    answers[q.id]='ДЕМО · Пару размещу у окна, семью с детьми — в тихой просторной зоне, бизнес-встречу — в уединённом месте, друзей — ближе к бару. Конкретные столы уточню по схеме зала.';
    if(kind==='passed')correct++;
   }else if(i<wanted){answers[q.id]=[...q.correct];correct++;}
   else {const wrong=q.options.findIndex((_,n)=>!q.correct.includes(n));answers[q.id]=wrong>=0?[wrong]:[];}
  });
  const result={id:`demo-${uid}-${test.id}-${sequence}`,date:at(days),answers,correct,total:test.questions.length,autoTotal:test.questions.length-manual.length,status:kind,version:JSON.stringify(test.questions),demo:true};
  if(manual.length&&kind==='passed')result.review={date:at(days),by:'Демо-менеджер',decision:'accept',demo:true};
  if(manual.length&&kind==='failed')result.review={date:at(days),by:'Демо-менеджер',decision:'revise',demo:true};
  return result;
 }
 for(const u of db.users){
  const scenario=scenarios[u.id];if(!u.demo||!scenario)continue;
  for(const cid of ['hostess-standards','waiter-internship']){
   const c=db.courses.find(c=>c.id===cid),tests=globalThis.COURSE_ASSESSMENTS?.[cid];if(!c||!tests?.length)continue;
   // Existing results, including reviewed demo submissions, take precedence.
   const existing=u.assessmentProgress?.[cid];if(existing&&Object.values(existing).some(s=>s.attempts?.length||s.draft))continue;
   u.courseProgress??={};const p=u.courseProgress[cid]??={read:[],attempts:[]};
   const readCount=['complete','retake','old30','old90','old120','pending'].includes(scenario)?c.lessons.length:scenario==='partial'?Math.ceil(c.lessons.length*.6):scenario==='failed'?Math.ceil(c.lessons.length*.4):scenario==='draft'?1:0;
   for(let i=0;i<readCount;i++)if(!p.read.includes(i))p.read.push(i);
   u.assessmentProgress??={};const states=u.assessmentProgress[cid]??={};
   const days=scenario==='old30'?18:scenario==='old90'?60:scenario==='old120'?120:2;
   const passedCount=scenario==='complete'||scenario.startsWith('old')?tests.length:scenario==='retake'?Math.ceil(tests.length*.75):scenario==='partial'?Math.max(1,Math.floor(tests.length*.35)):0;
   for(const [i,t]of tests.entries()){
    const s=states[t.id]??={attempts:[],draft:null};
    if(scenario==='none')continue;
    if(scenario==='draft'){if(i===0)s.draft={startedAt:now,index:0,answers:{},version:JSON.stringify(t.questions),demo:true};continue;}
    if(scenario==='pending'&&t.questions.some(q=>q.type==='text')){s.attempts.push(attempt(t,'pending',1,u.id,0));continue;}
    if(scenario==='pending'&&cid==='waiter-internship'){
     // Internship has no free responses: a pending review is never fabricated.
     if(i<Math.ceil(tests.length*.6))s.attempts.push(attempt(t,'passed',days,u.id,0));
     continue;
    }
    if(scenario==='pending'){if(i===0)s.attempts.push(attempt(t,'passed',days,u.id,0));continue;}
    if(scenario==='failed'){if(i<2)s.attempts.push(attempt(t,'failed',days,u.id,0));continue;}
    if(i<passedCount){
     if(scenario==='retake')s.attempts.push(attempt(t,'failed',5,u.id,0));
     s.attempts.push(attempt(t,'passed',days,u.id,1));
    }else if(scenario==='retake'||scenario==='partial'&&i===passedCount){s.attempts.push(attempt(t,'failed',days,u.id,0));}
   }
  }
 }
 db.demoImportedResultsVersion=1;db.demoImportedResultsCreatedAt=new Date(now).toISOString();
 try{save();}catch{db=previous;setupCourses();toast('Не удалось сохранить деморезультаты: память браузера заполнена');}
}
addImportedDemoResults();
