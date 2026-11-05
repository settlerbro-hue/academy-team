const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('secure-dist/portal.js','utf8');
const course={id:'management',kind:'course',published:true,payload:{lessons:[{id:'lesson'}],completionTestIds:['core']}},core={id:'core',kind:'test',published:true,course_id:course.id},practice={id:'practice',kind:'test',published:true,course_id:course.id};
const s={content:[course,core,practice],progress:[{course_id:course.id,lesson_id:'lesson'}],attempts:[{test_id:'core',passed:true,needs_review:false}]};
const ctx={s,payload:d=>d.payload,kind:k=>s.content.filter(d=>d.kind===k),courseForRestaurant:()=>true};vm.createContext(ctx);vm.runInContext(source.split('\n').find(l=>l.startsWith('function trainingCourseStatus(')),ctx);
assert(ctx.trainingCourseStatus(course.id).done,'Optional practice cannot revoke completed core training');
assert(ctx.trainingCourseStatus(course.id).detail.includes('Тесты 1/1'));
s.attempts[0].needs_review=true;assert(!ctx.trainingCourseStatus(course.id).done,'A core answer awaiting review remains incomplete');
s.attempts[0].needs_review=false;s.progress=[];assert(!ctx.trainingCourseStatus(course.id).done,'Core lessons are still required');
s.progress=[{course_id:course.id,lesson_id:'lesson'}];delete course.payload.completionTestIds;assert(!ctx.trainingCourseStatus(course.id).done,'Unconfigured courses still require all linked tests');
s.attempts.push({test_id:'practice',passed:true});assert(ctx.trainingCourseStatus(course.id).done);
console.log('PASS: optional practice preserves completed core training; reviewed answers, lessons and legacy test requirements remain authoritative.');

