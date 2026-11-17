// Routing regression checks without browser dependencies or a live database.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const portal=fs.readFileSync(path.join(__dirname,'../secure-dist/portal.js'),'utf8');
const source=portal.slice(portal.indexOf('const menuBrands='),portal.indexOf('const s={'))+
 portal.slice(portal.indexOf('function testQuestionImages('),portal.indexOf('async function submitTest('));
assert(source.includes('async function restoreRoute()'),'Routing source boundary missing');
const memory=new Map(),queries=[],calls=[];
const attemptId='11111111-1111-4111-8111-111111111111';
const attempt={id:attemptId,user_id:'employee',test_id:'test-1',started_at:'2026-10-23T10:00:00Z',submitted_at:null,snapshot:{title:'Immutable test',questions:[{id:'q1',type:'single',options:['A','B']},{id:'q2',type:'multiple',text:'<Q2>',options:['A','B','C']},{id:'q3',type:'single',options:['A','B']}],timeLimitSeconds:120},answers:null};
const mistakes=[{index:1,selected:[0,1],wrong:[1],incomplete:true},{index:2,selected:[],wrong:[],incomplete:true}];
const s={session:{user:{id:'employee'}},profile:{id:'employee',role:'manager',status:'active',restaurant_id:'minsk'},content:[{id:'course-1',kind:'course',published:true,payload:{lessons:[{id:'lesson-1',title:'One'},{id:'lesson-2',title:'Two'}]}},{id:'test-1',kind:'test',course_id:'course-1',published:true,title:'Test',payload:{}},{id:'doc-1',kind:'material',published:true,payload:{}},{id:'drink-1',kind:'menu',published:true,payload:{}}],progress:[],tab:'home'};
const location={hash:'#/profile',pathname:'/',search:''};
const context={s,location,URLSearchParams,encodeURIComponent,decodeURIComponent,structuredClone,Date,Promise,setTimeout,clearTimeout,clearInterval,console,timer:null,
 departments:{'Бар':['Бармен'],'Зал':['Хостес']},priorities:{start:'Start',attestation:'Exam',additional:'Extra'},
 sessionStorage:{getItem:k=>memory.get(k)||null,setItem:(k,v)=>memory.set(k,v),removeItem:k=>memory.delete(k)},
 window:{addEventListener(){}},history:{pushState(a,b,url){location.hash=url.slice(url.indexOf('#'));calls.push('push');},replaceState(a,b,url){location.hash=url.slice(url.indexOf('#'));calls.push('replace');}},
 restaurants:{minsk:'RVB',pushkino:'Pushkino',khimki:'Khimki',mytishchi:'Mytishchi'},payload:d=>d.payload||d,kind:k=>s.content.filter(x=>x.kind===k&&x.published!==false),manager:()=>s.profile.role==='manager',canEdit:()=>true,
 canViewOral:()=>s.profile.role==='manager'||s.profile.role==='admin'||s.profile.department==='Руководитель',loadOralDashboard:async()=>{s.oralDashboard={members:[{id:'employee'}]};},loadTeam:async()=>{s.team={profiles:[{id:'employee',full_name:'Test employee'}]};},rpc:async(name,args)=>{calls.push(name);assert.notEqual(name,'academy_start_test','Refreshing must never start another attempt');return name==='academy_test_mistakes'&&args.p_attempt_id===attemptId?mistakes:[];},
 priorityBadge:()=>'',esc:x=>String(x??'').replace(/</g,'&lt;').replace(/>/g,'&gt;'),
 client:{from(table){const filters={};return {select(){return this;},eq(k,v){filters[k]=v;return this;},async maybeSingle(){queries.push({table,filters});return {data:filters.id===attempt.id&&filters.user_id===attempt.user_id?{...attempt}:null,error:null};}};}}
};
vm.createContext(context);for(const helper of ["courseAssignedPayload","courseLessonDone","courseTestPassed"])vm.runInContext(portal.split("\n").find(line=>line.startsWith("function "+helper+"(")),context);vm.runInContext(source+'\nglobalThis.router={restoreRoute,currentRoute,syncRoute,draftKey,testView,testMistakesView};',context);
const {router}=context;
async function open(hash){location.hash=hash;await router.restoreRoute();}
(async()=>{
 await open('#/profile');assert.equal(s.tab,'profile');
 await open('#/attestation/members/employee');assert.equal(s.oralMember,'employee');assert.equal(router.currentRoute(),'#/attestation/members/employee');
 s.profile.role='employee';await open('#/attestation');assert(s.routeError,'Employees cannot open examination cabinet');s.profile.role='manager';
 await open('#/courses/course-1/lessons/lesson-2');assert.equal(s.course,'course-1');assert.equal(s.lesson,1);assert.equal(router.currentRoute(),'#/courses/course-1/lessons/lesson-2');
 await open('#/courses?venue=khimki');assert.equal(s.courseVenue,'');assert.equal(router.currentRoute(),'#/courses');
 s.session.user.id='68a8567e-625e-41bc-bb37-6744d729c3d4';
 await open('#/courses/course-1/lessons/lesson-2?venue=mytishchi');assert.equal(s.courseVenue,'mytishchi');assert.equal(router.currentRoute(),'#/courses/course-1/lessons/lesson-2?venue=mytishchi');
 await open('#/tests/test-1?venue=khimki');assert.equal(s.courseVenue,'khimki');assert.equal(router.currentRoute(),'#/tests/test-1?venue=khimki');
 await open('#/courses?venue=network');assert.equal(s.courseVenue,'');assert.equal(router.currentRoute(),'#/courses');
 s.session.user.id='employee';
 await open('#/menu?category=alcohol&subcategory=Gin&q=lime');assert.equal(s.category,'alcohol');assert.equal(s.filter,'lime');
 await open('#/menu?brand=90&section=kitchen&restaurant=khimki');assert.equal(s.menuBrand,'90');assert.equal(s.menuSection,'kitchen');assert.equal(s.menuRestaurant,'khimki');assert.equal(router.currentRoute(),'#/menu?brand=90&section=kitchen');
 await open('#/library/doc-1');assert.equal(s.materialView,'doc-1');
 await open('#/menu/drink-1');assert.equal(s.menuItem,'drink-1');
 await open('#/manager/members/employee/profile');assert.equal(s.profileEdit.id,'employee');
 await open('#/manager/members/foreign/profile');assert(s.routeError);
 memory.set(router.draftKey('attempt',attemptId),JSON.stringify({q1:[1]}));
 await open('#/tests/test-1/attempts/'+attemptId);assert.equal(s.test.attempt_id,attemptId);assert.equal(s.test.startedAt,new Date(attempt.started_at).getTime());assert.equal(s.test.answers.q1[0],1);assert.equal(s.test.time_limit_seconds,120);
 const testHtml=router.testView();assert.equal((testHtml.match(/Можно выбрать несколько вариантов ответа/g)||[]).length,1);assert.match(testHtml,/aria-describedby="multiple-hint-1"/);assert(!calls.includes('academy_test_mistakes'));
 assert.equal(queries.at(-1).filters.user_id,'employee','Attempt queries must explicitly target the signed-in user');
 await open('#/tests/wrong-test/attempts/'+attemptId);assert(s.routeError);assert.equal(s.test,null);
 attempt.submitted_at='2026-10-23T10:01:00Z';attempt.score=1;attempt.total=1;attempt.passed=true;
 await open('#/tests/test-1/attempts/'+attemptId);assert.equal(s.testResult.id,attemptId);router.syncRoute();assert.equal(location.hash,'#/tests/test-1/results/'+attemptId);assert.equal(calls.at(-1),'replace','A completed attempt must normalize without trapping browser Back');
 const reviewHtml=router.testMistakesView(s.testResult);assert.match(reviewHtml,/Вопрос 2 из 3/);assert.match(reviewHtml,/&lt;Q2&gt;/);assert.match(reviewHtml,/Отмечены не все правильные варианты/);assert.match(reviewHtml,/Неверный вариант<\/strong><div>B/);assert.match(reviewHtml,/Выбрано верно<\/strong><div>A/);assert.match(reviewHtml,/Ответ пропущен/);assert.doesNotMatch(reviewHtml,/Вопрос 1 из 3|<div>C<\/div>/);
 assert.match(router.testMistakesView({...s.testResult,mistakes:[]}),/ошибок нет/);assert.match(router.testMistakesView({...s.testResult,mistakes:undefined}),/Загрузить разбор/);
 await open('#/courses/missing');assert(s.routeError);
 await open('#/tests/test-1/attempts/not-a-uuid');assert(s.routeError);
 await open('#/profile');assert.equal(s.routeError,'');assert.equal(s.tab,'profile');
 console.log('Routing checks passed: deep links, lesson/filter restoration, scoped attempts, answer draft, unchanged timer origin, results and invalid routes.');
})().catch(e=>{console.error(e);process.exitCode=1;});

