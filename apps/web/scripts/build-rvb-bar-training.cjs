const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),read=p=>JSON.parse(fs.readFileSync(path.join(root,p),'utf8'));
const menu=read('supabase/sources/rvb-bar-live-20261027.json');
const sheet=read('supabase/sources/rvb-ttk-autumn-20261027.json');
const handbook=read('supabase/rvb-bar-handbook.json');
const esc=s=>String(s??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const positions=['Бармен','Барбэк','Старший бармен','Бар-менеджер'];
const documents=[],keys={},audit={sourceTab:'Коктейли Осень',recipes:[],questions:[],excludedRecipes:[]};
function block(type,fields){return {id:'b-'+(++block.n),type,...fields};}block.n=0;
const hero=(title,label)=>block('hero',{title,label,tone:'yellow'});
const text=html=>block('text',{html});
function course(id,title,priority,lessons,step){const d={id,kind:'course',title,course_id:null,published:true,restaurant_id:'minsk',department:'Бар',payload:{id,title,brand:'rvb',description:{3:'Рабочая смена, касса, станция, поставки и хранение. 15 занятий по пособию бара РВБ.',4:'Ассортимент своего бара: категории, вкус, состав и подача. Отдельные проверки по разделам.',5:'Рецептуры и приготовление по вкладке «Коктейли Осень» актуальных ТТК РВБ.'}[step],priority,audiencePositions:positions,audienceLevels:['trainee','certified'],trainingPath:{id:'rvb-bar',step},lessons,sequence:lessons.map(l=>({type:'lesson',id:l.id})),testIds:[]}};documents.push(d);return d;}
function test(course,lesson,id,title,questions,answers){if(!questions.length)return;const d={id,kind:'test',title,course_id:course.id,published:true,restaurant_id:'minsk',department:'Бар',payload:{id,title,priority:'attestation',questions,passCount:Math.ceil(questions.length*.8),timeLimitSeconds:0}};documents.push(d);keys[id]=answers;course.payload.testIds.push(id);const i=course.payload.sequence.findIndex(s=>s.type==='lesson'&&s.id===lesson.id);course.payload.sequence.splice(i+1,0,{type:'test',id});}
function question(list,answers,id,prompt,correct,others,source){const options=[...new Set([correct,...others].filter(Boolean))].slice(0,4);if(options.length<3)return false;const offset=list.length%options.length;for(let i=0;i<offset;i++)options.push(options.shift());const q={id,text:prompt,type:'single',options};list.push(q);answers[id]=[options.indexOf(correct)];audit.questions.push({id,source,answer:correct});return true;}
// The source handbook is kept verbatim; each section becomes an editable lesson.
const sections=[...handbook.payload.body.matchAll(/<details(?: open)?><summary>([\s\S]*?)<\/summary><div>([\s\S]*?)<\/div><\/details>/g)];
assert.equal(sections.length,15);
const titles=['Приход на работу','Открытие смены','Работа в течение смены','Закрытие смены','Еженедельный чек-лист','Ежемесячный чек-лист','Работа с кассой','Открытие станции','Закрытие станции','Пополнение бара','Раскладка ковров','Расстановка посуды','Приём поставок','Заготовочная смена','Хранение и маркировка'];
course('rvb-bar-foundations','Пособие бармена и барбэка РВБ — обучение','start',sections.map((s,i)=>({id:'rvb-bar-handbook-'+(i+1),title:titles[i],priority:'start',blocks:[hero(titles[i],'Пособие бара РВБ · '+(i+1)+' / 15'),text(s[2])]})),3);
// Parse main recipes only. Premix batch calculations and side-by-side service columns
// are not substituted for the one-portion recipe in F/H/I.
const recipes=[];let current=null;
for(let i=0;i<sheet.values.length;i++){const r=sheet.values[i];if(r[3]){const name=String(r[3]).trim();current=/[а-яa-z]/i.test(name)&&!/(п\s*\/\s*ф|Башня)/i.test(name)?{name,row:i+1,ingredients:[],details:{}}:null;if(current)recipes.push(current);}
 if(!current)continue;
 if(r[5]&&r[7]!=null&&/^(мл|г|гр|шт)$/i.test(String(r[8]||''))&&!/выход/i.test(String(r[5])))current.ingredients.push({name:String(r[5]).trim(),amount:String(r[7]).trim(),unit:String(r[8]),row:i+1,ambiguous:r[6]!=null&&String(r[6])!==String(r[7])});
 if(r[13]&&r[14])current.details[String(r[13]).trim()]=String(r[14]).trim();
}
const complete=recipes.filter(r=>r.ingredients.length&&r.details['Метод']&&r.details['Посуда']);
audit.excludedRecipes=recipes.filter(r=>!complete.includes(r)).map(r=>({name:r.name,row:r.row,reason:'Неполная основная рецептура'}));
audit.recipes=complete;
const labels={alcohol:'Крепкий алкоголь и аперитивы',beer:'Пиво',wine:'Вино и игристое',cocktails:'Коктейли',tinctures:'Настойки',sets:'Сеты',nonalcoholic:'Безалкогольные напитки',hot:'Горячие напитки'};
const grouped=Object.fromEntries(Object.keys(labels).map(k=>[k,menu.filter(d=>(d.payload.category==='alcohol'&&/пив/i.test(d.payload.subcategory||'')?'beer':d.payload.category)===k)]));
const lessons=Object.entries(grouped).filter(([,items])=>items.length).map(([k,items])=>({id:'rvb-assortment-'+k,title:labels[k],priority:'attestation',blocks:[hero(labels[k],'Ассортимент РВБ'),block('callout',{title:'Что нужно знать',text:'Узнай позиции раздела, их вкус, состав, объём и подачу. Потренируй рекомендацию гостю. Точные дозировки коктейлей изучаются отдельно в курсе ТТК.',tone:'sky'}),block('list',{items:items.map(d=>d.title+(d.payload.volume?' · '+d.payload.volume:'')+(d.payload.description?' — '+d.payload.description:''))}),block('link',{text:'Открыть карточки меню РВБ',url:'https://askacademy.ru/#/menu?brand=rvb&section=bar'})]}));
const assortment=course('rvb-bar-assortment','Ассортимент бара РВБ','attestation',lessons,4);
for(const lesson of lessons){const cat=lesson.id.replace('rvb-assortment-',''),items=grouped[cat],questions=[],answers={};let n=0;
 if(cat==='cocktails'){
  for(const r of complete.slice(0,10)){const composition=r.ingredients.map(i=>i.name).join(', ');question(questions,answers,'rvb-menu-'+cat+'-'+(++n),'Какой состав соответствует коктейлю «'+r.name+'» по ТТК РВБ?',composition,complete.filter(x=>x!==r).map(x=>x.ingredients.map(i=>i.name).join(', ')),{tab:'Коктейли Осень',row:r.row});}
 }else{
  for(const d of items){const p=d.payload;let ok=false;
   if(p.description&&items.filter(x=>x.payload.description===p.description).length===1)ok=question(questions,answers,'rvb-menu-'+cat+'-'+(n+1),'Какой напиток описан в меню РВБ так: «'+p.description+'»?',d.title,items.filter(x=>x.id!==d.id).map(x=>x.title),{menu:d.id,field:'description'});
   else if(p.subcategory){const options=[...new Set(menu.filter(x=>x.payload.category===p.category).map(x=>x.payload.subcategory))];ok=question(questions,answers,'rvb-menu-'+cat+'-'+(n+1),'К какой категории относится «'+d.title+'» в меню РВБ?',p.subcategory,options.filter(x=>x!==p.subcategory),{menu:d.id,field:'subcategory'});}
   else if(p.volume){ok=question(questions,answers,'rvb-menu-'+cat+'-'+(n+1),'Какой объём указан в меню РВБ для «'+d.title+'»?',p.volume,[...new Set(menu.filter(x=>x.payload.category===cat).map(x=>x.payload.volume))].filter(x=>x!==p.volume),{menu:d.id,field:'volume'});}
   if(ok)n++;if(n===10)break;
  }
 }
 test(assortment,lesson,'rvb-assortment-test-'+cat,'РВБ · '+labels[cat],questions,answers);
}
// A lesson per recipe, with four focused tests after recipe groups.
const ttkLessons=complete.map((r,i)=>({id:'rvb-ttk-recipe-'+r.row,title:r.name,priority:'attestation',blocks:[hero(r.name,'ТТК РВБ · Коктейли Осень'),block('table',{title:'На одну порцию',headers:['Ингредиент','Количество'],rows:r.ingredients.map(x=>[x.name,x.amount+' '+x.unit])}),block('table',{title:'Приготовление и подача',headers:['Параметр','Значение'],rows:Object.entries(r.details)}),block('link',{text:'Открыть актуальную ТТК',url:'https://docs.google.com/spreadsheets/d/1zX2OGQBAKu92D2fHKtZ4KGL3MIbXw7uvUwsOO46K1oo/edit?gid=844076848#gid=844076848'})]}));
const ttk=course('rvb-bar-techcards-course','ТТК бара РВБ — коктейли осень','attestation',ttkLessons,5);
for(let group=0;group<4;group++){const start=Math.floor(complete.length*group/4),end=Math.floor(complete.length*(group+1)/4),batch=complete.slice(start,end),questions=[],answers={};let n=0;
 for(const r of batch){const ing=r.ingredients.find(x=>!x.ambiguous&&/^\d+(?:[.,]\d+)?$/.test(x.amount));if(ing){const amount=Number(ing.amount.replace(',','.'));const correct=ing.amount+' '+ing.unit;const others=[amount+10,Math.max(1,amount-10),amount+20].map(v=>v+' '+ing.unit);question(questions,answers,'rvb-ttk-'+group+'-'+(++n),'Сколько ингредиента «'+ing.name+'» нужно на одну порцию «'+r.name+'»?',correct,others,{tab:'Коктейли Осень',row:ing.row,columns:'F/H/I'});}
  const method=r.details['Метод'];question(questions,answers,'rvb-ttk-'+group+'-'+(++n),'Каким методом готовят «'+r.name+'» по ТТК РВБ?',method,[...new Set(complete.map(x=>x.details['Метод']))].filter(x=>x!==method),{tab:'Коктейли Осень',row:r.row,field:'Метод'});
 }
 test(ttk,ttkLessons[end-1],'rvb-ttk-test-'+(group+1),'РВБ · ТТК коктейлей · Часть '+(group+1),questions,answers);
}
documents.push({id:'rvb-bar-techcards',kind:'material',title:'Технологические карты бара РВБ',course_id:null,published:true,restaurant_id:'minsk',department:'Бар',payload:{id:'rvb-bar-techcards',title:'Технологические карты бара РВБ',brand:'rvb',type:'link',url:'https://docs.google.com/spreadsheets/d/1zX2OGQBAKu92D2fHKtZ4KGL3MIbXw7uvUwsOO46K1oo/edit?gid=844076848#gid=844076848',description:'Актуальные ТТК РВБ. Для коктейлей — вкладка «Коктейли Осень».'}});
// Preserve the reviewed content revision when rebuilding sources. Do not resurrect
// the retired recipe or its questions, and keep the surviving question IDs stable.
const revisionPath=path.join(root,'supabase/rvb-bar-content-revision.json');
if(fs.existsSync(revisionPath)){
 const reviewed=JSON.parse(fs.readFileSync(revisionPath,'utf8'));
 for(const id of ['rvb-bar-foundations','rvb-bar-assortment','rvb-bar-techcards-course']){
  const fresh=documents.find(d=>d.id===id),revision=reviewed.find(d=>d.id===id);
  if(fresh&&revision){fresh.payload.lessons=structuredClone(revision.payload.lessons);fresh.payload.sequence=structuredClone(revision.payload.sequence);}
 }
 for(const d of documents.filter(d=>d.kind==='test')){const retired=d.payload.questions.filter(q=>/Налево от Лифт/i.test(q.text));for(const q of retired)delete keys[d.id][q.id];d.payload.questions=d.payload.questions.filter(q=>!retired.includes(q));d.payload.passCount=Math.ceil(d.payload.questions.length*.8);}
 const currentQuestions=new Set(documents.filter(d=>d.kind==='test').flatMap(d=>d.payload.questions.map(q=>q.id)));
 audit.questions=audit.questions.filter(q=>currentQuestions.has(q.id));audit.recipes=audit.recipes.filter(r=>r.row!==41);
 audit.excludedRecipes.push({name:'Налево от Лифта',row:41,reason:'Убрано из обучения по решению руководителя'});
}
// Preserve the reviewed full-assortment questions and retired beer test.
require('./apply-rvb-assortment-test-revision.cjs')(documents,keys);
const reviewedQuestionAuditPath=path.join(root,'supabase/sources/rvb-assortment-tests-audit-20261029.json');
if(fs.existsSync(reviewedQuestionAuditPath)){
 const reviewedAudit=JSON.parse(fs.readFileSync(reviewedQuestionAuditPath,'utf8')),byQuestion=new Map([...audit.questions.map(q=>[q.id,q]),...reviewedAudit.questions.map(q=>[q.questionId,{id:q.questionId,source:q.source,answer:q.answer}])]);
 audit.questions=documents.filter(d=>d.kind==='test').flatMap(d=>d.payload.questions.map(q=>{assert(byQuestion.has(q.id));return byQuestion.get(q.id);}));
}

// Fail closed on answer-key mistakes; keys are never written into public course payloads.
for(const d of documents.filter(d=>d.kind==='test')){assert(d.payload.questions.length);assert(d.payload.passCount>=1);for(const q of d.payload.questions){assert.equal(new Set(q.options).size,q.options.length);assert.equal(keys[d.id][q.id].length,1);assert(q.options[keys[d.id][q.id][0]]);}}
fs.writeFileSync(path.join(root,'supabase/rvb-bar-training.json'),JSON.stringify(documents,null,2)+'\n');
fs.writeFileSync(path.join(root,'supabase/sources/rvb-bar-training-audit.json'),JSON.stringify(audit,null,2)+'\n');
const sql=['-- RVB bar learning content; no permissions or existing progress are changed.','begin;',"update public.academy_content set title='Добро пожаловать в команду — 90-е и Руки Вверх Бар', payload=payload||jsonb_build_object('title','Добро пожаловать в команду — 90-е и Руки Вверх Бар','shortTitle','Добро пожаловать в команду','coverLabel','Знакомство с командой') where id='welcome-90' and kind='course';","update public.academy_content set title='Правила сотрудника',payload=payload||jsonb_build_object('title','Правила сотрудника','shortTitle','Правила сотрудника','coverLabel','Правила команды') where id='guru-43403' and kind='course';"];
for(const d of documents){sql.push('insert into public.academy_content(id,kind,title,course_id,payload,published,restaurant_id,department) select id,kind,title,course_id,payload,published,restaurant_id,department from jsonb_populate_record(null::public.academy_content,$doc$'+JSON.stringify(d)+'$doc$::jsonb) on conflict(id) do nothing;');if(keys[d.id])sql.push('insert into academy_private.test_keys(test_id,keys) values(\''+d.id+'\',$keys$'+JSON.stringify(keys[d.id])+'$keys$::jsonb) on conflict(test_id) do nothing;');}
sql.push('commit;',"select kind,count(*) from public.academy_content where id like 'rvb-bar-%' or id like 'rvb-assortment-test-%' or id like 'rvb-ttk-test-%' group by kind;");
fs.writeFileSync(path.join(root,'supabase/seed-rvb-bar-training.sql'),sql.join('\n')+'\n');
console.log(JSON.stringify({courses:documents.filter(d=>d.kind==='course').map(d=>({id:d.id,lessons:d.payload.lessons.length,tests:d.payload.testIds.length})),tests:Object.keys(keys).length,questions:audit.questions.length,recipes:complete.length,excluded:audit.excludedRecipes}));
