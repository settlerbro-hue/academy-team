(() => {
  const previousCourse = course;
  const sourceLink = (url, title = 'Открыть в Сервис Гуру ↗') => {
    try {
      const safe = new URL(url);
      if (safe.protocol !== 'https:') return '';
      return `<a href="${esc(safe.href)}" target="_blank" rel="noopener noreferrer">${esc(title)}</a>`;
    } catch { return ''; }
  };

  course = function () {
    const c = activeCourse();
    if (!Array.isArray(c?.outline)) return previousCourse();
    const read = new Set(user().read || []);
    const studied = c.lessons.reduce((n, _, i) => n + Number(read.has(i)), 0);
    const tests = c.outline.filter(item => item.type === 'test').length;
    const rows = c.outline.map((item, position) => {
      if (item.type === 'lesson') {
        const index = item.lessonIndex;
        const material = c.lessons[index];
        if (!material) return '';
        return `<div class="lesson"><div class="number">${read.has(index) ? '✓' : String(index + 1).padStart(2, '0')}</div><div style="flex:1;min-width:0"><h3>${esc(item.title || material.title)}</h3><span class="muted">${read.has(index) ? 'Изучено' : c.kind === 'internship' ? 'Материал стажировки' : 'Материал'}</span></div><button class="btn secondary" data-lesson="${index}">Читать →</button></div>`;
      }
      if (item.type !== 'test') return '';
      return `<div class="lesson"><div class="number" aria-hidden="true">✧</div><div style="flex:1;min-width:0"><h3>${esc(item.title || 'Проверка знаний')}</h3><span class="muted">Тест ожидает переноса</span>${item.sourceUrl ? `<details class="source-details"><summary>Источник теста</summary><p>${sourceLink(item.sourceUrl)}</p></details>` : ''}</div><button class="btn secondary" disabled aria-label="Тест пока недоступен">Скоро</button></div>`;
    }).join('');
    $('#content').innerHTML = `<div class="eyebrow">${c.kind === 'internship' ? 'СТАЖИРОВКА' : 'КУРС'} · ${esc(c.brand || 'АКАДЕМИЯ КОМАНДЫ')}</div><h1>${esc(c.title)}</h1><p>${esc(c.description || '')}</p><p class="muted">Изучено ${studied} из ${c.lessons.length} материалов${tests ? ` · ${tests} проверок ожидают переноса` : ''}</p><div class="progress" aria-label="Прогресс изучения"><i style="width:${Math.round(studied / Math.max(1, c.lessons.length) * 100)}%"></i></div>${c.kind === 'internship' ? '<p class="note">Отметка «Изучено» сохраняет прочтение материала. Подтверждение смены наставником пока не подключено.</p>' : ''}<div class="card">${rows}</div>${tests ? '<p class="muted">Вопросы и правильные ответы ещё не перенесены. Изучение материалов доступно, результат аттестации не выставляется.</p>' : ''}${c.sourceUrl ? `<details class="source-details"><summary>Источник программы</summary><p>${sourceLink(c.sourceUrl, 'Оригинал программы в Сервис Гуру ↗')}</p></details>` : ''}`;
    document.querySelectorAll('[data-lesson]').forEach(button => {
      button.onclick = () => { lessonIndex = Number(button.dataset.lesson); go('lesson'); };
    });
  };
})();
