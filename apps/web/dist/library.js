(() => {
  const storageKey = 'academy-library-favorites-v1';
  let favorites;
  try { favorites = new Set(JSON.parse(localStorage.getItem(storageKey) || '[]')); } catch { favorites = new Set(); }
  const filters = { brand: 'common', search: '', department: '', type: '', favorites: false };
  const bookIcon = '<svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4h6a3 3 0 0 1 3 3v14a4 4 0 0 0-4-2H4zM13 7a3 3 0 0 1 3-3h5v15h-5a4 4 0 0 0-3 2"/></svg>';
  const brandNames={common:'Общая','90':'90-е',rvb:'РВБ'};
  const items = () => [
    ...(globalThis.LIBRARY_ITEMS || []).filter(item => safeUrl(item.url)).map(item=>({...item,brand:item.brand||(['doc-1','doc-3','doc-4','doc-5'].includes(item.id)?'rvb':'common')})),
    ...(db.courses||[]).filter(c=>!c.demo&&(c.brand==='90-е'||c.id==='welcome-90')).map(c=>({id:'course-'+c.id,courseId:c.id,title:c.title,description:c.description,brand:'90',department:'Все',type:'course'})),
    {id:'rvb-menu',title:'Барное меню РВБ',description:'Актуальная барная карта: алкоголь по категориям, коктейли, настойки, сеты, холодные и горячие напитки. Цены, порции и отметки изучения.',brand:'rvb',department:'Бар',type:'menu'}
  ];
  function safeUrl(value) {
    try { const url = new URL(value, location.href); return ['https:', 'http:'].includes(url.protocol) ? url.href : null; } catch { return null; }
  }
  function openLibrary() { manager = false; go('library'); }
  function paintResults() {
    const query = filters.search.trim().toLocaleLowerCase('ru');
    const filtered = items().filter(item => item.brand===filters.brand && (!query || `${item.title} ${item.description || ''}`.toLocaleLowerCase('ru').includes(query)) && (!filters.department || item.department === 'Все' || item.department === filters.department) && (!filters.type || item.type === filters.type) && (!filters.favorites || favorites.has(item.id)));
    const results = document.getElementById('library-results');
    if (!results) return;
    document.getElementById('library-count').textContent = `Найдено материалов: ${filtered.length}`;
    results.innerHTML = filtered.length ? filtered.map(item => `<article class="library-card"><div class="library-card-top"><span class="library-type">${{pdf:'PDF · Документ',link:'Внешняя ссылка',course:'Курс · В приложении',menu:'Меню · Учебные карточки'}[item.type]} · ${brandNames[item.brand]}</span><button class="library-favorite ${favorites.has(item.id) ? 'selected' : ''}" data-library-favorite="${esc(item.id)}" aria-pressed="${favorites.has(item.id)}" aria-label="${favorites.has(item.id) ? 'Убрать из избранного' : 'Добавить в избранное'}: ${esc(item.title)}">${favorites.has(item.id) ? '★' : '☆'}</button></div><h2>${esc(item.title)}</h2><p>${esc(item.description || 'Материал для работы и обучения команды.')}</p><div class="library-card-bottom"><span class="library-department">${esc(item.department === 'Все' ? 'Для всей команды' : item.department)}</span>${item.type==='menu'||item.type==='course'?`<button class="btn secondary" data-library-action="${esc(item.type==='menu'?'menu':item.courseId)}">Изучать →</button>`:`<a href="${esc(safeUrl(item.url))}" target="_blank" rel="noopener noreferrer" class="library-open" aria-label="Открыть ${esc(item.title)} в новой вкладке">Открыть ↗</a>`}</div></article>`).join('') : '<div class="library-empty"><span aria-hidden="true">⌕</span><h2>Ничего не найдено</h2><p>Попробуй другое название или сбрось фильтры.</p><button class="btn secondary" id="library-reset">Сбросить фильтры</button></div>';
    results.querySelectorAll('[data-library-action]').forEach(button=>button.onclick=()=>{if(button.dataset.libraryAction==='menu'){openRvbMenu();}else{view='course';selectCourse(button.dataset.libraryAction);}});
    results.querySelectorAll('[data-library-favorite]').forEach(button => button.onclick = () => {
      const id = button.dataset.libraryFavorite;
      if (favorites.has(id)) favorites.delete(id); else favorites.add(id);
      try { localStorage.setItem(storageKey, JSON.stringify([...favorites])); } catch {}
      paintResults();
    });
    const reset = document.getElementById('library-reset');
    if (reset) reset.onclick = () => { Object.assign(filters, { search: '', department: '', type: '', favorites: false }); libraryPage(); };
  }
  function libraryPage() {
    const departments = [...new Set(items().filter(item=>item.brand===filters.brand).map(item => item.department).filter(item => item !== 'Все'))];
    $('#content').innerHTML = `<div class="library-intro"><div class="eyebrow">ВСЁ ПОД РУКОЙ</div><h1>Библиотека</h1><p>Правила, памятки и рабочие материалы команды.</p></div><div class="library-brands" role="group" aria-label="Раздел библиотеки">${['common','90','rvb'].map(id=>[id,brandNames[id]]).map(([id,name])=>`<button class="btn ${filters.brand===id?'':'secondary'}" data-library-brand="${id}" aria-pressed="${filters.brand===id}">${name}</button>`).join('')}</div><section class="library-tools" aria-label="Поиск и фильтры библиотеки"><label class="library-search" for="library-search">Найти материал<input id="library-search" type="search" placeholder="Название или ключевое слово" value="${esc(filters.search)}"></label><div class="library-filter-row"><label for="library-department">Подразделение<select id="library-department"><option value="">Вся команда</option>${departments.map(d => `<option ${filters.department === d ? 'selected' : ''}>${esc(d)}</option>`).join('')}</select></label><label for="library-type">Формат<select id="library-type"><option value="">Все форматы</option><option value="pdf" ${filters.type === 'pdf' ? 'selected' : ''}>Документы PDF</option><option value="link" ${filters.type === 'link' ? 'selected' : ''}>Ссылки</option><option value="course" ${filters.type === 'course' ? 'selected' : ''}>Курсы</option><option value="menu" ${filters.type === 'menu' ? 'selected' : ''}>Учебное меню</option></select></label></div><button id="library-favorites" class="library-favorites-toggle ${filters.favorites ? 'selected' : ''}" aria-pressed="${filters.favorites}">☆ Только избранное</button></section><p class="library-count" id="library-count" aria-live="polite"></p><div class="library-grid" id="library-results"></div><p class="library-footnote">Меню и курсы открываются в приложении, документы — в отдельной вкладке. Избранное сохраняется на этом устройстве.</p>`;
    document.querySelectorAll('[data-library-brand]').forEach(button=>button.onclick=()=>{filters.brand=button.dataset.libraryBrand;filters.department='';filters.type='';filters.search='';filters.favorites=false;libraryPage();});
    $('#library-search').oninput = e => { filters.search = e.target.value; paintResults(); };
    $('#library-department').onchange = e => { filters.department = e.target.value; paintResults(); };
    $('#library-type').onchange = e => { filters.type = e.target.value; paintResults(); };
    $('#library-favorites').onclick = () => { filters.favorites = !filters.favorites; const button = $('#library-favorites'); button.classList.toggle('selected', filters.favorites); button.setAttribute('aria-pressed', String(filters.favorites)); paintResults(); };
    paintResults();
  }
  const previousRender = render;
  render = function () {
    previousRender();
    if (!user()) return;
    document.querySelectorAll('.nav [data-go="course"],.bottomnav [data-go="course"]').forEach(button => {
      button.innerHTML = bookIcon + '<span>Библиотека</span>';
      button.setAttribute('aria-label', 'Библиотека');
      button.dataset.polished = '1';
      button.classList.toggle('active', !manager && view === 'library');
      button.removeAttribute('aria-current');
      if (!manager && view === 'library') button.setAttribute('aria-current', 'page');
      button.onclick = openLibrary;
    });
    if (!manager && view === 'library') libraryPage();
    else if (!manager && view === 'home') {
      const link = document.createElement('button');
      link.className = 'library-dashboard-link';
      link.innerHTML = bookIcon + '<span><strong>Библиотека команды</strong><small>Правила, памятки и полезные ссылки</small></span><b aria-hidden="true">→</b>';
      link.onclick = openLibrary;
      const listTitle = document.querySelector('.course-section-title');
      if (listTitle) listTitle.before(link); else $('#content').append(link);
    }
  };
  render();
})();
