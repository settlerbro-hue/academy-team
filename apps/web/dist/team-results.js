(() => {
 const previousManager=managerPage;
 function summaryText(m){return `${m.passedTests}/${m.testTotal} пройдено${m.pending?` · ${m.pending} на проверке`:''}${m.drafts?` · ${m.drafts} черновик(ов)`:''}`;}
 function teamProgress(){
  const c=activeCourse(),rows=teamUsers().map(u=>({u,m:courseResults(u,c)}));
  $('#managerbody').innerHTML=`<div class="card"><div class="row"><h2>Прогресс команды</h2><button class="btn secondary" id="export">↓ CSV</button></div><p class="muted">Прогресс курса: изученные материалы и пройденные проверки. Баллы курса — сумма лучших подтверждённых результатов, взвешенная по числу вопросов. Пересдачи не удваивают баллы.</p><div class="tablewrap"><table><thead><tr><th>Сотрудник</th><th>Материалы</th><th>Проверки</th><th>Баллы курса</th><th>Прогресс курса</th><th>Статус</th></tr></thead><tbody>${rows.map(({u,m})=>`<tr><td>${esc(u.name)}<div class="muted">${esc(u.position)} · ${esc(restaurantName(u.restaurantId))}</div></td><td>${m.read}/${m.lessons}</td><td>${summaryText(m)}</td><td>${m.score===null?'—':m.score+'%'}</td><td>${m.progress}%</td><td>${m.complete?'Курс завершён':resultStatus(m.status)}</td></tr>`).join('')}</tbody></table></div></div><h2 style="margin-top:24px">Результаты по сотрудникам</h2>${rows.map(({u,m})=>`<details class="card source-details"><summary>${esc(u.name)} · ${m.progress}% курса · ${summaryText(m)}</summary>${m.details.map(t=>`<div class="lesson"><div style="min-width:0;flex:1"><h3>${esc(t.title)}</h3><p>${t.passed?'Пройден':t.pending?'Ожидает проверки':t.latest?'Нужна пересдача':t.draft?'Черновик':'Без попыток'} · Лучший результат: ${t.bestScore===null?'—':t.bestScore+'%'} · Попыток: ${t.attempts.length}${t.pending&&t.passed?' · новая попытка на проверке':''}</p></div></div>`).join('')}</details>`).join('')}`;
  $('#export').onclick=()=>{
   const cell=v=>'"'+String(v).replace(/^[=+@-]/,"'").replaceAll('"','""')+'"';
   const csv='\uFEFF'+[['Сотрудник','Заведение','Должность','Курс','Материалы изучены','Материалы всего','Проверки пройдены','Проверки всего','Ожидают проверки','Попытки','Баллы курса %','Прогресс курса %','Статус'],...rows.map(({u,m})=>[u.name,restaurantName(u.restaurantId),u.position,c.title,m.read,m.lessons,m.passedTests,m.testTotal,m.pending,m.attempts.length,m.score??'',m.progress,m.complete?'Курс завершён':resultStatus(m.status)])].map(r=>r.map(cell).join(';')).join('\r\n');
   const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'})),a=document.createElement('a');a.href=url;a.download='course-progress.csv';a.click();URL.revokeObjectURL(url);
  };
 }
 managerPage=function(){
  previousManager();const c=activeCourse();if(!(globalThis.COURSE_ASSESSMENTS?.[c.id]||c.assessments)?.length)return;
  const metrics=teamUsers().map(u=>courseResults(u,c));
  const stats=$('#content .stats');if(stats)stats.innerHTML=`<div class="card"><div class="stat">${metrics.length}</div><span class="muted">Сотрудников</span></div><div class="card"><div class="stat">${metrics.filter(m=>m.complete).length}</div><span class="muted">Завершили курс</span></div><div class="card"><div class="stat">${metrics.reduce((n,m)=>n+m.pending,0)}</div><span class="muted">Ответов на проверке</span></div>`;
  if(mtab==='team')teamProgress();
 };
 render();
})();
