/* Imported assessments. Progress is local to this browser, user, course and test. */
(() => {
  let opened = null;
  let timer = null;
  const originalCourse = course;
  const originalRender = render;
  const originalManager = managerPage;
  const imported = () => globalThis.COURSE_ASSESSMENTS || {};
  function tests(c) { return Array.isArray(c?.assessments) ? c.assessments : imported()[c?.id] || []; }
  function sync() {
    for (const c of db.courses || []) if (Array.isArray(imported()[c.id])) c.assessments = imported()[c.id];
  }
  function link(url) {
    try { const u = new URL(url); return u.protocol === 'https:' ? `<a href="${esc(u.href)}" target="_blank" rel="noopener noreferrer">Источник в Сервис Гуру ↗</a>` : ''; } catch { return ''; }
  }
  function match(c, item) {
    return tests(c).find(a => String(a.id) === String(item.id) || a.sourceUrl && a.sourceUrl === item.sourceUrl);
  }
  function state(u, cid, aid) {
    u.assessmentProgress ??= {};
    u.assessmentProgress[cid] ??= {};
    return u.assessmentProgress[cid][aid] ??= { attempts: [], draft: null };
  }
  function persist() { try { save(); return true; } catch { toast('Не удалось сохранить: память браузера заполнена'); return false; } }
  function selection(q, value) {
    return Array.isArray(value) ? [...new Set(value.filter(n => Number.isInteger(n) && n >= 0 && n < (q.options || []).length))].sort((a,b) => a-b) : [];
  }
  function hasKey(q) {
    return ['single','multiple'].includes(q.type) && Array.isArray(q.options) && Array.isArray(q.correct) && q.correct.length > 0 &&
      q.correct.every(n => Number.isInteger(n) && n >= 0 && n < q.options.length) && new Set(q.correct).size === q.correct.length && (q.type !== 'single' || q.correct.length === 1);
  }
  function ready(a) { return a.importComplete !== false && a.questions?.length > 0 && a.questions.every(q => q.type === 'text' || hasKey(q)); }
  function autoCorrect(q, value) {
    if (!hasKey(q)) return null;
    const given = selection(q, value), key = selection(q, q.correct);
    return given.length === key.length && given.every((v,i) => v === key[i]);
  }
  function valid(q, value) { return q.type === 'text' ? String(value || '').trim().length > 0 : selection(q, value).length > 0; }
  function current() {
    if (!opened || opened.uid !== user()?.id || opened.cid !== activeCourse()?.id) return null;
    const a = tests(activeCourse()).find(a => String(a.id) === opened.aid);
    return a ? { a, s: state(user(), opened.cid, opened.aid) } : null;
  }
  function stopTimer() { clearInterval(timer); timer = null; }
  function plural(n, forms) { const a=Math.abs(n)%100,b=a%10; return forms[a>10&&a<20?2:b===1?0:b>=2&&b<=4?1:2]; }
  function questionCount(n) { return `${n} ${plural(n,['вопрос','вопроса','вопросов'])}`; }
  function questionImages(q) {
    const images = [...new Set([...(Array.isArray(q.images) ? q.images.map(image => typeof image === 'string' ? image : image?.src) : []), q.image].filter(image => typeof image === 'string' && image))];
    return images.length ? '<div class="assessment-question-images">' + images.map((image,index) => '<img class="assessment-image" src="' + esc(image) + '" alt="Иллюстрация к вопросу' + (images.length > 1 ? ' ' + (index + 1) : '') + '" loading="lazy">').join('') + '</div>' : '';
  }
  function optionImage(q, index) {
    const image = q.optionImages?.[index];
    return typeof image === 'string' && image ? `<img class="assessment-option-image" src="${esc(image)}" alt="Изображение варианта ${index + 1}" loading="lazy">` : '';
  }
  function timeLabel(seconds) { return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2,'0')}`; }
  function remaining(a, draft) {
    return a.timeLimitSeconds > 0 ? Math.max(0, Math.ceil((draft.startedAt + a.timeLimitSeconds * 1000 - Date.now()) / 1000)) : null;
  }
  function startTimer(a, draft) {
    stopTimer();
    if (!(a.timeLimitSeconds > 0)) return;
    timer = setInterval(() => {
      if (view !== 'assessment' || manager || !current()?.s.draft) { stopTimer(); return; }
      const seconds = remaining(a, draft), clock = document.getElementById('assessment-clock');
      if (clock) clock.textContent = `Осталось ${timeLabel(seconds)}`;
      if (seconds === 0) submit(true);
    }, 1000);
  }
  function begin() {
    const x = current(); if (!x) return;
    if (!ready(x.a)) { toast('Ключи ответов ещё требуют проверки'); return; }
    if (!x.s.draft) {
      x.s.draft = { startedAt: Date.now(), index: 0, answers: {}, version: JSON.stringify(x.a.questions) };
      if (!persist()) { x.s.draft = null; return; }
    }
    draw();
  }
  function submit(expired = false) {
    const x = current(); if (!x?.s.draft) return;
    const { a, s } = x, d = s.draft;
    if (!ready(a)) { toast('Ключи ответов ещё требуют проверки'); stopTimer(); return; }
    const marked = a.questions.map(q => autoCorrect(q, d.answers[q.id]));
    const pending = marked.some(v => v === null);
    const correct = marked.filter(Boolean).length;
    const result = { id: crypto.randomUUID(), date: new Date().toISOString(), answers: structuredClone(d.answers), correct, autoTotal: marked.filter(v => v !== null).length, total: a.questions.length, status: pending ? 'pending' : correct >= (a.passCount ?? a.questions.length) ? 'passed' : 'failed', expired, version: d.version };
    s.attempts.push(result); s.draft = null;
    if (!persist()) { s.attempts.pop(); s.draft = d; return; }
    stopTimer(); draw();
  }
  function resultHtml(a, r) {
    const pending = r.status === 'pending';
    return `<div class="assessment-result" role="status"><span class="tag">${pending ? 'Ожидает проверки' : r.status === 'passed' ? 'Пройден' : 'Нужна повторная попытка'}</span><h2>${pending ? 'Ответ сохранён для проверки' : `Верно ${r.correct} из ${r.total}`}</h2>${pending ? r.autoTotal>0 ? `<p>Автоматически проверено: ${r.autoTotal} из ${r.total}. Верных ответов в этой части: ${r.correct}. Свободные ответы проверяет менеджер.</p>` : '<p>Ответ ожидает ручной проверки менеджером. Результат появится после проверки.</p>' : `<p>Для прохождения нужно ${a.passCount ?? a.questions.length} ${plural(a.passCount ?? a.questions.length,['верный ответ','верных ответа','верных ответов'])}.</p>`}${r.expired ? '<p>Время на тест истекло. Сохранены ответы, введённые до окончания времени.</p>' : ''}${r.review ? `<p class="muted">${r.status === 'passed' ? 'Принято' : 'Возвращено на доработку'} в демонстрационном кабинете ${esc(r.review.by)} · ${new Date(r.review.date).toLocaleString('ru-RU')}</p>` : ''}<p class="muted">${new Date(r.date).toLocaleString('ru-RU')}</p></div>`;
  }
  function draw() {
    stopTimer();
    const x = current();
    if (!x) { opened = null; view = 'course'; course(); return; }
    const { a, s } = x, content = $('#content');
    const prefix = `<button class="back" id="assessment-back">← К программе курса</button><div class="reading assessment"><div class="eyebrow">${esc(activeCourse().title)}</div><h1>${esc(a.title)}</h1>`;
    const changed = s.draft && s.draft.version !== JSON.stringify(a.questions);
    if (changed) { s.draft = null; persist(); }
    if (!s.draft || !ready(a)) {
      const last = s.attempts.at(-1);
      content.innerHTML = prefix + `<div class="card"><p>${questionCount(a.questions.length)}${a.timeLimitSeconds > 0 ? ` · ${timeLabel(a.timeLimitSeconds)}` : ''}</p><p>${!ready(a) ? 'Начало теста недоступно: ключи ответов ещё требуют подтверждения по источнику.' : a.questions.some(q => q.type === 'text') ? 'Свободные ответы сохраняются для ручной проверки. Отправка не означает автоматического зачёта.' : `Для прохождения нужно ${a.passCount ?? a.questions.length} ${plural(a.passCount ?? a.questions.length,['верный ответ','верных ответа','верных ответов'])}.`}</p>${a.timeLimitSeconds > 0 ? '<p class="muted">В прототипе действует общий таймер теста. Отдельные лимиты на каждый вопрос из Сервис Гуру пока не воспроизводятся.</p>' : ''}${changed ? '<p class="note">Вопросы обновились. Начните новую попытку; предыдущие результаты сохранены.</p>' : ''}<button class="btn" id="assessment-begin" ${ready(a) ? '' : 'disabled'}>${last ? 'Новая попытка' : 'Начать тест'}</button></div>${last ? `<div class="card">${resultHtml(a,last)}</div>` : ''}<details class="source-details"><summary>Источник задания</summary><p>${link(a.sourceUrl)}</p></details><p class="note">Прототип: ответы и результаты доступны только в этом браузере. Проверка менеджером демонстрационная; сервер и подтверждение наставником не подключены.</p></div>`;
      $('#assessment-begin').onclick = begin;
    } else {
      const d = s.draft;
      d.index = Math.min(Math.max(0,d.index),a.questions.length - 1);
      const q = a.questions[d.index], value = d.answers[q.id], seconds = remaining(a,d);
      if (seconds === 0) { submit(true); return; }
      const control = q.type === 'text' ? `<label class="assessment-text-label" for="assessment-text">Ваш ответ</label><textarea id="assessment-text" rows="7" maxlength="12000" placeholder="Напишите ответ своими словами">${esc(value || '')}</textarea><span class="muted">Ответ сохраняется автоматически.</span>` : `<fieldset class="answers"><legend class="muted">${q.type === 'multiple' ? 'Выберите все верные варианты' : 'Выберите один вариант'}</legend>${(q.options || []).map((option,i) => `<label class="answer"><input type="${q.type === 'multiple' ? 'checkbox' : 'radio'}" name="assessment-answer" value="${i}" ${selection(q,value).includes(i) ? 'checked' : ''}><span class="assessment-option-content">${esc(option)}${optionImage(q,i)}</span></label>`).join('')}</fieldset>`;
      content.innerHTML = prefix + `<div class="row assessment-meta"><span>Вопрос ${d.index + 1} из ${a.questions.length}</span>${seconds !== null ? `<span id="assessment-clock" role="timer" aria-live="off">Осталось ${timeLabel(seconds)}</span>` : ''}</div><div class="progress"><i style="width:${(d.index + 1)/a.questions.length*100}%"></i></div><h2 class="assessment-question" tabindex="-1">${q.type === 'text' ? 'Практическое задание' : esc(q.text)}</h2>${q.type === 'text' ? `<div class="assessment-prompt">${esc(q.text)}</div>` : ''}${questionImages(q)}<form id="assessment-form">${control}<div class="assessment-actions">${d.index ? '<button class="btn secondary" type="button" id="assessment-prev">← Назад</button>' : ''}<button class="btn" type="submit" id="assessment-next" ${valid(q,value) ? '' : 'disabled'}>${d.index === a.questions.length - 1 ? q.type === 'text' ? 'Отправить на проверку' : 'Завершить тест' : 'Далее →'}</button></div></form><p class="muted">Можно вернуться к вопросам. При выходе незавершённая попытка сохраняется${seconds !== null ? ', время продолжает идти' : ''}.</p></div>`;
      const update = () => {
        d.answers[q.id] = q.type === 'text' ? $('#assessment-text').value : [...document.querySelectorAll('[name="assessment-answer"]:checked')].map(el => Number(el.value));
        $('#assessment-next').disabled = !valid(q,d.answers[q.id]); persist();
      };
      if (q.type === 'text') $('#assessment-text').oninput = update;
      else document.querySelectorAll('[name="assessment-answer"]').forEach(el => el.onchange = update);
      if ($('#assessment-prev')) $('#assessment-prev').onclick = () => { d.index--; persist(); draw(); };
      $('#assessment-form').onsubmit = e => { e.preventDefault(); if (!valid(q,d.answers[q.id])) return; if (d.index === a.questions.length-1) submit(); else { d.index++; persist(); draw(); } };
      startTimer(a,d);
      $('#content .assessment-question').focus({preventScroll:true});
    }
    $('#assessment-back').onclick = () => { stopTimer(); go('course'); };
  }
  globalThis.openAssessment = function(id) {
    const c = activeCourse(), a = tests(c).find(a => String(a.id) === String(id));
    if (!a?.questions?.length) return;
    opened = { uid: user().id, cid: c.id, aid: String(a.id) }; view = 'assessment'; manager = false; render(); window.scrollTo(0,0);
  };
  course = function() {
    const c = activeCourse();
    if (!c?.outline || !tests(c).length) return originalCourse();
    const read = new Set(user().read || []), available = c.outline.filter(i => i.type === 'test' && ready(match(c,i)||{})).length;
    const pending = c.outline.filter(i => i.type === 'test').length - available;
    $('#content').innerHTML = `<div class="eyebrow">${c.kind === 'internship' ? 'СТАЖИРОВКА' : 'КУРС'} · ${esc(c.brand || 'АКАДЕМИЯ КОМАНДЫ')}</div><h1>${esc(c.title)}</h1><p>${esc(c.description || '')}</p><p class="muted">Изучено ${read.size} из ${c.lessons.length} материалов · ${available} ${plural(available,['проверка доступна','проверки доступны','проверок доступны'])}${pending ? ` · ${pending} ожидают переноса` : ''}</p><div class="progress"><i style="width:${Math.min(100,read.size/Math.max(1,c.lessons.length)*100)}%"></i></div>${c.kind === 'internship' ? '<p class="note">Изучение материала и тестирование сохраняются отдельно. Подтверждение смены наставником пока не подключено.</p>' : ''}<div class="card">${c.outline.map(item => {
      if (item.type === 'lesson') { const i=item.lessonIndex,l=c.lessons[i]; return l ? `<div class="lesson"><div class="number">${read.has(i)?'✓':String(i+1).padStart(2,'0')}</div><div style="flex:1;min-width:0"><h3>${esc(item.title||l.title)}</h3><span class="muted">${read.has(i)?'Изучено':'Материал'}</span></div><button class="btn secondary" data-lesson="${i}">Читать →</button></div>` : ''; }
      if (item.type !== 'test') return '';
      const a=match(c,item),r=a?state(user(),c.id,a.id).attempts.at(-1):null, d=a?state(user(),c.id,a.id).draft:null;
      return `<div class="lesson"><div class="number">✧</div><div style="flex:1;min-width:0"><h3>${esc(item.title)}</h3><span class="muted">${(a?.importComplete!==false&&a?.questions?.length) ? `${questionCount(a.questions.length)} · ${!ready(a)?'Ключи требуют проверки':r?.status==='passed'?'Пройден':r?.status==='pending'?'Ожидает проверки':r?.status==='failed'?'Нужна повторная попытка':d?'Попытка сохранена':a.questions.some(q=>q.type==='text')?'Ручная проверка':'Проверка знаний'}` : a?.sourceQuestionCount?questionCount(a.sourceQuestionCount)+' · Готовится':'Тест ожидает переноса'}</span></div><button class="btn secondary" ${(a?.importComplete!==false&&a?.questions?.length) ? `data-assessment="${esc(a.id)}"` : 'disabled aria-label="Тест пока недоступен"'}>${(a?.importComplete!==false&&a?.questions?.length) ? d?'Продолжить →':'Открыть →' : 'Скоро'}</button></div>`;
    }).join('')}</div><p class="note">Результаты тестов сохраняются отдельно для каждого сотрудника и курса в этом браузере.</p>`;
    document.querySelectorAll('[data-lesson]').forEach(b => b.onclick = () => { lessonIndex=Number(b.dataset.lesson);go('lesson'); });
    document.querySelectorAll('[data-assessment]').forEach(b => b.onclick = () => openAssessment(b.dataset.assessment));
  };
  function reviewPanel() {
    const target=$('#managerbody'); if(!target)return;
    const cid=activeCourse().id, rows=[];
    for(const u of teamUsers()) for(const a of tests(activeCourse())) for(const r of state(u,cid,a.id).attempts) if(r.status==='pending') {
      let questions; try { questions=JSON.parse(r.version); } catch { questions=null; }
      const manual=Array.isArray(questions)?questions.filter(q=>q.type==='text'):[];
      const canAccept=Array.isArray(questions)&&questions.every(q=>q.type==='text'||hasKey(q))&&manual.length>0&&manual.every(q=>valid(q,r.answers[q.id]));
      rows.push({u,a,r,manual,canAccept});
    }
    target.innerHTML=`<h2>Проверка свободных ответов</h2><p class="note">Демонстрационный кабинет: здесь видны только ответы из этого браузера. Решение не отправляется в Сервис Гуру и не подтверждает смену у наставника.</p>${rows.length?rows.map(({u,a,r,manual,canAccept},i)=>`<article class="card assessment-review"><h3>${esc(u.name)}</h3><p>${esc(a.title)} · ${new Date(r.date).toLocaleString('ru-RU')}</p>${manual.map(q=>`<h4>${esc(q.text)}</h4><p class="assessment-free-answer">${esc(r.answers[q.id]||'Ответ не дан')}</p>`).join('')}${!canAccept?'<p class="note">Принять попытку нельзя: есть незаполненные свободные ответы или неподтверждённые ключи. Вопрос без ключа не считается свободным ответом.</p>':''}<div class="assessment-actions"><button class="btn" data-review="${i}" data-decision="accept" ${canAccept?'':'disabled'}>Принять ответы · демо</button><button class="btn secondary" data-review="${i}" data-decision="revise">На доработку</button></div></article>`).join(''):'<div class="card empty">Нет ответов, ожидающих проверки</div>'}`;
    target.querySelectorAll('[data-review]').forEach(b=>b.onclick=()=>{
      const {a,r,manual,canAccept}=rows[Number(b.dataset.review)];
      if(r.status!=='pending'||b.dataset.decision==='accept'&&!canAccept)return;
      const previous = structuredClone(r);
      r.review={date:new Date().toISOString(),by:user().name,decision:b.dataset.decision};
      if(b.dataset.decision==='accept') {r.correct+=manual.length; r.status=r.correct>=(a.passCount??r.total)?'passed':'failed';} else r.status='failed';
      if(persist())managerPage();
      else { for(const key of Object.keys(r))delete r[key]; Object.assign(r,previous); }
    });
  }
  function importedTestsPanel() {
    const target=$('#managerbody'); if(!target)return;
    target.innerHTML=`<h2>Тесты курса · ${esc(activeCourse().title)}</h2><p class="note">Оригинальные задания из Сервис Гуру. Этот просмотр не меняет вопросы и ключи. Свободные ответы проверяются во вкладке «Проверка заданий».</p>${tests(activeCourse()).map(a=>`<article class="card assessment-review"><h3>${esc(a.title)}</h3><p>${questionCount(a.questions.length)}${a.timeLimitSeconds>0?` · общий таймер ${timeLabel(a.timeLimitSeconds)}`:''} · ${a.questions.some(q=>q.type==='text')?'Ручная проверка':`Порог: ${a.passCount??a.questions.length} ${plural(a.passCount??a.questions.length,['верный ответ','верных ответа','верных ответов'])}`}</p><p>${link(a.sourceUrl)}</p>${a.questions.map((q,i)=>`<details class="source-details"><summary>${i+1}. ${esc(q.text)}</summary>${questionImages(q)}${q.editorialNote?`<p class="note"><strong>Требует методической проверки.</strong> ${esc(q.editorialNote)}</p>`:''}${q.type==='text'?'<p>Свободный ответ. Автоматического ключа нет.</p>':`<p class="muted">${hasKey(q)?q.type==='multiple'?'Несколько верных вариантов':'Один верный вариант':'Ключ ответа не подтверждён — прохождение недоступно'}</p><ul>${(q.options||[]).map((o,n)=>`<li class="assessment-manager-option">${esc(o)}${hasKey(q)&&q.correct.includes(n)?' <strong>✓ Верный ответ</strong>':''}${optionImage(q,n)}</li>`).join('')}</ul>`}</details>`).join('')}</article>`).join('')}`;
  }
  managerPage=function(){
    originalManager(); if(!tests(activeCourse()).length)return;
    const tabs=$('#content .tabs'); if(!tabs)return;
    const testsTab=tabs.querySelector('[data-tab="tests"]');if(testsTab)testsTab.textContent='Тесты курса';
    const button=document.createElement('button');button.textContent='Проверка заданий';button.className=mtab==='assessment-review'?'active':'';button.onclick=()=>{mtab='assessment-review';managerPage();};tabs.append(button);
    if(mtab==='assessment-review')reviewPanel();
    else if(mtab==='tests')importedTestsPanel();
  };
  render=function(){sync();originalRender(); if(user()&&!manager&&view==='assessment')draw();else stopTimer();};
  render();
})();
