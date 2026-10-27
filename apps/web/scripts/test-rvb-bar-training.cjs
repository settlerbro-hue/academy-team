const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const base=path.resolve(__dirname,'..'),docs=JSON.parse(fs.readFileSync(path.join(base,'supabase/rvb-bar-training.json'))),source=fs.readFileSync(path.join(base,'secure-dist/portal.js'),'utf8');
const courses=docs.filter(d=>d.kind==='course'),tests=docs.filter(d=>d.kind==='test');
assert.equal(courses.length,3);assert.equal(tests.length,12);assert.equal(courses[0].payload.lessons.length,15);
const allIds=docs.map(d=>d.id);assert.equal(new Set(allIds).size,allIds.length);
for(const d of docs){assert.equal(d.restaurant_id,'minsk');assert.equal(d.department,'Бар');assert(!/"correct"|"key_snapshot"/.test(JSON.stringify(d.payload)));}
const ctx={s:{profile:{id:'me',restaurant_id:'minsk',department:'Бар',position:'Бармен'},courseAudience:'mine',content:docs,progress:[],attempts:[]},payload:d=>d.payload,kind:k=>docs.filter(d=>d.kind===k)};vm.createContext(ctx);
for(const n of ['courseForRestaurant','rvbBarPathEnabled','rvbBarPathSteps','trainingCourseStatus'])vm.runInContext(source.split('\n').find(l=>l.startsWith('function '+n+'(')),ctx);
assert(!ctx.courseForRestaurant({payload:{requiredRestaurantIds:['pushkino','khimki','mytishchi']}}));assert(ctx.courseForRestaurant({payload:{}}));assert(ctx.rvbBarPathEnabled());assert.equal(ctx.rvbBarPathSteps().length,6);
for(const position of ['Бармен','Барбэк','Старший бармен','Бар-менеджер']){ctx.s.profile.position=position;assert(ctx.rvbBarPathEnabled());}
ctx.s.profile.position='Бармен';ctx.s.profile.restaurant_id='khimki';assert(!ctx.rvbBarPathEnabled());ctx.s.profile.restaurant_id='minsk';ctx.s.courseAudience='Хостес';assert(!ctx.rvbBarPathEnabled());ctx.s.courseAudience='mine';
const d=courses.find(d=>d.id==='rvb-bar-assortment');assert(!ctx.trainingCourseStatus(d.id).done);
ctx.s.progress=d.payload.lessons.map(l=>({course_id:d.id,lesson_id:l.id}));assert(!ctx.trainingCourseStatus(d.id).done,'Lessons alone do not pass the course');
ctx.s.attempts=tests.filter(t=>t.course_id===d.id).map(t=>({test_id:t.id,passed:true}));assert(ctx.trainingCourseStatus(d.id).done);
ctx.s.attempts[0].needs_review=true;assert(!ctx.trainingCourseStatus(d.id).done,'Unreviewed answers cannot complete a step');
for(const c of courses){const seen=new Set();for(const step of c.payload.sequence){assert(!seen.has(step.type+':'+step.id));seen.add(step.type+':'+step.id);assert(step.type==='lesson'?c.payload.lessons.some(l=>l.id===step.id):tests.some(t=>t.id===step.id&&t.course_id===c.id));}assert.equal(c.payload.sequence.filter(x=>x.type==='lesson').length,c.payload.lessons.length);}
const audit=JSON.parse(fs.readFileSync(path.join(base,'supabase/sources/rvb-bar-training-audit.json')));assert.equal(audit.sourceTab,'Коктейли Осень');assert.equal(audit.questions.length,tests.reduce((n,t)=>n+t.payload.questions.length,0));
console.log('PASS: six RVB bar stages, own venue/job scope, all 15 handbook sections, 12 tests, source-backed questions, paired lessons/tests, completion requires all lessons and passed reviewed tests.');
