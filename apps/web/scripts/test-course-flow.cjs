const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');const portal=fs.readFileSync('secure-dist/portal.js','utf8'),source=portal.slice(portal.indexOf('function courseSteps('),portal.indexOf('function lessonView('));const seq=JSON.parse(fs.readFileSync('supabase/course-sequences.json')),base=JSON.parse(fs.readFileSync('supabase/content-records.json'));const content=seq.map(row=>{let d=structuredClone(base.find(d=>d.id===row.id));d.payload.lessons=d.payload.lessons.filter(l=>row.sequence.some(x=>x.type==='lesson'&&x.id===String(l.id)));d.payload.sequence=row.sequence;return d;});content.push(...seq.flatMap(row=>row.sequence.filter(x=>x.type==='test').map(x=>({id:x.id,kind:'test',course_id:row.id,title:x.id,payload:{}}))));const s={content,progress:[],attempts:[]},context={s,payload:d=>d.payload,kind:k=>content.filter(d=>d.kind===k),render(){},window:{scrollTo(){}},String};vm.createContext(context);for(const helper of ["courseAssignedPayload","courseLessonDone","courseTestPassed"])vm.runInContext(portal.split("\n").find(line=>line.startsWith("function "+helper+"(")),context);vm.runInContext(portal.slice(portal.indexOf('function barLearningResources('),portal.indexOf('function barPreparationTest(')),context);vm.runInContext(source+';this.api={courseSteps,nextCourseStep,resumeCourseStep,openCourseStep};',context);let transitions=0;for(const row of seq){s.progress=[];s.attempts=[];for(let i=0;i<row.sequence.length;i++){let expected=row.sequence[i],step=context.api.resumeCourseStep(row.id);assert.equal(step.type,expected.type);assert.equal(step.id,expected.id);context.api.openCourseStep(row.id,step);assert.equal(s.course,row.id);assert.equal(s.test,null,'Navigation must not create/start an attempt');if(step.type==='test'){assert.equal(s.testIntro,step.id);s.attempts.push({test_id:step.id,passed:true});}else{assert.equal(s.lesson,step.index);assert.equal(s.testIntro,null);s.progress.push({course_id:row.id,lesson_id:step.id});}const next=context.api.nextCourseStep(row.id,step.id);assert.equal(next?.id,row.sequence[i+1]?.id);if(next){context.api.openCourseStep(row.id,next);if(next.type==='test')assert.equal(s.testIntro,next.id);else assert.equal(s.lesson,next.index);}transitions++;}}const nav=portal.slice(portal.indexOf('function courseStepNav('),portal.indexOf('function nextCourseStep('));assert(!nav.includes('priorityBadge('));assert(!nav.includes('priorityControl('));assert(nav.includes('data-test-intro'));console.log('Course flow passed: '+seq.length+' courses, '+transitions+' steps, correct resume after each lesson/test, no automatic attempt, no priority badge in navigation.');

// A mobile outline is collapsed before the lesson is shown; desktop stays open.
let outline={open:true},changes=[];const media={matches:true,addEventListener(type,fn){assert.equal(type,'change');changes.push(fn);}};context.$=()=>outline;context.window.matchMedia=()=>media;context.esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
vm.runInContext('bindLessonOutline();bindLessonOutline();',context);assert.equal(outline.open,false);assert.equal(changes.length,1,'Re-render must not add resize listeners');
media.matches=false;changes[0]();assert.equal(outline.open,true);outline={open:true};media.matches=true;changes[0]();assert.equal(outline.open,false,'Resize uses the current outline, not a detached element');
const safeOutline=context.courseOutline(content[0],[],{title:'<img src=x onerror=alert(1)>'});assert(safeOutline.includes('&lt;img'));assert(safeOutline.includes('lesson-outline-current'));assert(safeOutline.includes(' open>'));
console.log('PASS: mobile outline defaults closed, desktop and resize stay usable, listener is shared, and current lesson text is escaped.');

// Library preparation is separate from the course sequence and test attempts.
const libraryGuides=['bar-wine-guide','bar-beer-guide','bar-drinks-guide'].map(id=>({id,kind:'material',published:true,title:id,payload:{}}));
content.push(...libraryGuides);
const barCourse={id:'rvb-bar-assortment',kind:'course',payload:{lessons:[{id:'base',title:'Ассортимент'}]}};
const barTests=[{id:'bar-test-one',title:'Алкоголь',course_id:barCourse.id,kind:'test',payload:{}},{id:'bar-test-two',title:'Вино',course_id:barCourse.id,kind:'test',payload:{}}];
const steps=context.courseSteps(barCourse,barTests),beforeProgress=JSON.stringify(s.progress),beforeAttempts=JSON.stringify(s.attempts);
const preparedNav=context.courseStepNav(barCourse,barTests);
assert.equal((preparedNav.match(/База для обучения: бар/g)||[]).length,1);
assert(preparedNav.indexOf('База для обучения: бар')<preparedNav.indexOf('data-test-intro="bar-test-one"'));
for(const guide of libraryGuides)assert(preparedNav.includes('href="#/library/'+guide.id+'"'));
assert.equal(steps.length,3);assert(steps.every(step=>['lesson','test'].includes(step.type)));
assert.equal(JSON.stringify(s.progress),beforeProgress);assert.equal(JSON.stringify(s.attempts),beforeAttempts);
assert(!context.courseStepNav(barCourse,[]).includes('База для обучения'));
assert(!context.barPreparationTest({course_id:'kitchen-course',title:'Меню кухни'}));
assert(context.barPreparationTest({course_id:'waiter-internship',title:'Тест по 7-й смене (меню бара)'}));
libraryGuides[1].published=false;assert(!context.barPreparationResources().includes('bar-beer-guide'));
libraryGuides.forEach(d=>d.published=false);assert.equal(context.barPreparationResources(),'');
libraryGuides.forEach(d=>d.published=true);
assert(portal.includes("barPreparationTest(d)?barPreparationResources():''"));
const intro=portal.slice(portal.indexOf('function testIntroView('),portal.indexOf('function testIntroView(')+1500);assert(intro.indexOf('barPreparationResources()')<intro.indexOf('Начать тест'));
console.log('PASS: three published library guides before bar tests, once per outline, no lessons/progress/attempts added, unrelated tests unchanged.');

// Completing lessons follows the course order until the last lesson.
const courseId='completion-example';
const lessonId='first';
content.push(
 {id:courseId,kind:'course',payload:{lessons:[{id:lessonId},{id:'last'}],sequence:[{id:lessonId,type:'lesson'},{id:'between',type:'test'},{id:'last',type:'lesson'},{id:'final-test',type:'test'}]}},
 ...['between','final-test'].map(id=>({id,kind:'test',course_id:courseId,title:id,payload:{}}))
);
const rpcCalls=[];
Object.assign(s,{session:{user:{id:'employee'}},course:courseId,lesson:0,tab:'courses',progress:[],testIntro:null});
context.rpc=async(name,args)=>{
 rpcCalls.push([name,args.p_course_id,args.p_lesson_id]);
 assert.equal(s.course,courseId,'Keep the lesson open until the mark is saved');
};
assert(portal.includes("$('#complete-lesson')?.addEventListener('click',()=>act(completeLesson))"));
(async()=>{
 await context.completeLesson();
 assert.deepEqual(rpcCalls,[['academy_complete_lesson',courseId,lessonId]]);
 assert.equal(s.progress[0].lesson_id,lessonId);
 assert.equal(s.course,courseId);assert.equal(s.testIntro,'between');
 assert.equal(s.test,null);
 s.testIntro=null;
 await context.completeLesson();
 assert.equal(s.testIntro,'between');
 assert.equal(rpcCalls.length,1,'A completed lesson does not need to be saved again');
 s.lesson=1;s.testIntro=null;
 await context.completeLesson();
 assert.equal(s.course,null);assert.equal(s.tab,'courses');
 assert.equal(s.progress[1].lesson_id,'last');
 s.course=courseId;s.progress=[];context.rpc=async()=>{throw Error('save failed');};
 await assert.rejects(context.completeLesson(),/save failed/);
 assert.equal(s.course,courseId);assert.equal(s.progress.length,0);
 console.log('PASS: lesson completion opens the next step, the last lesson returns to Learning, and failed saves keep the lesson open.');
})().catch(error=>{console.error(error);process.exitCode=1;});
