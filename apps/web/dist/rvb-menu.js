(() => {
 const categories=globalThis.RVB_MENU_CATEGORIES||{cocktails:'Коктейли',tinctures:'Настойки',sets:'Сеты',nonalcoholic:'Б/а напитки'};
 const statuses={new:'Не учил',repeat:'Повторить',learned:'Выучил'};
 const filter={category:'cocktails',subcategory:'',search:'',status:''};
 let mode='progress',selectedEmployee='',selectedItem='',creating=false,employeeSearch='',department='',position='';
 const originalRender=render,originalManager=managerPage;
 function isGenericFact(value){return /^В карте подаётся |^В актуальной карте|^Этот вкус входит в домашнюю линейку/.test(value||'')||/\d+\s*р\./.test(value||'');}
 globalThis.rvbMenuItems=function(){
  const original=globalThis.RVB_MENU_ITEMS||[],overrides=db.rvbMenuOverrides||{};
  const ids=new Set(original.map(i=>i.id));
  return [...original.map(i=>({...i,...overrides[i.id],id:i.id})),...Object.entries(overrides).filter(([id])=>!ids.has(id)).map(([id,i])=>({...i,id}))].filter(i=>categories[i.category]).map(i=>({...i,fact:isGenericFact(i.fact)?'':i.fact}));
 };

 // Convert historical full-card overrides into field overrides, so unchanged PDF prices
 // cannot hide the new source. Explicit manager changes and all learning IDs survive.
 if(!db.rvbMenuCurrentMigration&&globalThis.RVB_MENU_PREVIOUS){
  const before=structuredClone(db.rvbMenuOverrides||{});
  for(const [id,value]of Object.entries(db.rvbMenuOverrides||{})){
   const old=globalThis.RVB_MENU_PREVIOUS.find(i=>i.id===id);if(!old)continue;
   const delta={};for(const [key,v]of Object.entries(value))if(['editedAt','editedBy'].includes(key)||JSON.stringify(v)!==JSON.stringify(old[key]))delta[key]=v;
   db.rvbMenuOverrides[id]=delta;
  }
  db.rvbMenuCurrentMigration=1;
  try{save();}catch{db.rvbMenuOverrides=before;delete db.rvbMenuCurrentMigration;}
 }
 // A saved editor form used to include unchanged image fields. Let new photos fill
 // those defaults, while keeping photos that a manager actually changed.
 if(!db.rvbMenuPhotosMigration&&globalThis.RVB_MENU_PHOTO_PREVIOUS){
  const before=structuredClone(db.rvbMenuOverrides||{});
  for(const [id,value]of Object.entries(db.rvbMenuOverrides||{})){
   if(Object.hasOwn(globalThis.RVB_MENU_PHOTO_PREVIOUS,id)&&value.image===globalThis.RVB_MENU_PHOTO_PREVIOUS[id])delete value.image;
  }
  db.rvbMenuPhotosMigration=1;try{save();}catch{db.rvbMenuOverrides=before;delete db.rvbMenuPhotosMigration;}
 }

 // Release unchanged old descriptions without overwriting deliberate manager edits.
 if(!db.rvbMenuCharacterMigration&&globalThis.RVB_MENU_CHARACTER_PREVIOUS){
  const before=structuredClone(db.rvbMenuOverrides||{});
  for(const [id,value]of Object.entries(db.rvbMenuOverrides||{})){
   const old=globalThis.RVB_MENU_CHARACTER_PREVIOUS[id];if(!old)continue;
   for(const key of ['description','taste'])if(value[key]===old[key])delete value[key];
  }
  db.rvbMenuCharacterMigration=1;try{save();}catch{db.rvbMenuOverrides=before;delete db.rvbMenuCharacterMigration;}
 }
 // Replace only unchanged placeholder text, retaining manager-written descriptions.
 if(!db.rvbMenuDescriptionsCompleted){
  const before=structuredClone(db.rvbMenuOverrides||{});
  for(const value of Object.values(db.rvbMenuOverrides||{}))if(value.description==='Характеристика пока отсутствует в загруженном пособии. Менеджер может добавить её.'){delete value.description;if(value.taste==='')delete value.taste;}
  db.rvbMenuDescriptionsCompleted=1;try{save();}catch{db.rvbMenuOverrides=before;delete db.rvbMenuDescriptionsCompleted;}
 }
 // Fill new wine photos and confirmed names only where manager fields were unchanged.
 if(!db.rvbMenuWinePhotosMigration&&globalThis.RVB_MENU_WINE_PHOTO_PREVIOUS){
  const before=structuredClone(db.rvbMenuOverrides||{});
  for(const [id,value]of Object.entries(db.rvbMenuOverrides||{})){
   const old=globalThis.RVB_MENU_WINE_PHOTO_PREVIOUS[id];if(!old)continue;
   for(const key of ['image','name','sourceNote'])if(value[key]===old[key])delete value[key];
  }
  db.rvbMenuWinePhotosMigration=1;try{save();}catch{db.rvbMenuOverrides=before;delete db.rvbMenuWinePhotosMigration;}
 }
 function safeLink(url){if(!url)return '';try{const u=new URL(url,location.href);return ['https:','http:'].includes(u.protocol)?u.href:'';}catch{return '';}}
 function safeImage(url){return /^assets\/[a-zA-Z0-9_./-]+$/.test(url)?url:safeLink(url);}
 function openPhoto(item){
  const url=safeLink(item.image);if(!url)return;
  const dialog=document.createElement('dialog');dialog.className='menu-photo-dialog';
  const source=safeLink(item.imageSource);
  dialog.innerHTML='<button class="menu-photo-close" type="button" aria-label="Закрыть фото">×</button><h2>'+esc(item.name)+'</h2><img src="'+esc(url)+'" alt="'+esc(item.name)+'">'+(item.imageKind==='illustration'?'<p>Иллюстрация</p>':'');
  document.body.append(dialog);dialog.querySelector('button').onclick=()=>dialog.close();dialog.onclick=e=>{if(e.target===dialog)dialog.close();};dialog.addEventListener('close',()=>dialog.remove(),{once:true});dialog.showModal();
 }
 function editPosition(id){selectedItem=id||'';creating=false;mode='editor';manager=true;mtab='rvb-menu';go('home');}
 function subcategories(items,category){return [...new Set(items.filter(i=>!category||i.category===category).map(i=>i.subcategory).filter(Boolean))];}
 function categoryArt(item){
  const beer=item.subcategory?.includes('Пиво'),coffee=item.category==='hot';
  const color=beer?'#cb913c':item.category==='nonalcoholic'?'#84ab92':item.category==='cocktails'?'#dc8979':'#ad6a2d';
  return '<svg class="menu-category-art" viewBox="0 0 180 210" role="img" aria-label="Иллюстрация категории"><ellipse cx="90" cy="192" rx="67" ry="9" fill="#e9dfd1"/>'+(coffee?'<path d="M35 85h85v60q0 30-42 30t-43-30z" fill="#f5dfbf" stroke="#886647" stroke-width="3"/><path d="M122 95h15q23 25-15 40" fill="none" stroke="#886647" stroke-width="7"/><ellipse cx="78" cy="85" rx="42" ry="10" fill="#6a4228"/><path d="M70 65q-15-15 0-30m25 30q-15-15 0-30" fill="none" stroke="#cfbda5" stroke-width="3"/>':beer?'<path d="M48 53h74l-8 126H56z" fill="'+color+'" stroke="#ae7836" stroke-width="2"/><path d="M51 75h67l-7 99H59z" fill="#eab957"/><path d="M126 78h19v65h-22" fill="none" stroke="#cbb9a2" stroke-width="8"/><path d="M45 48q0-25 20-18 13-30 31-8 23-11 30 17v23H45z" fill="#fffdf9" stroke="#e6ddd0" stroke-width="2"/>':'<path d="M70 23h33v50q0 12 17 22 9 8 9 23v61q0 10-12 10H56q-12 0-12-10v-61q0-15 9-23 17-10 17-22z" fill="'+color+'" stroke="#825d39" stroke-width="2"/><rect x="67" y="13" width="39" height="24" rx="4" fill="#34302a"/><rect x="49" y="109" width="75" height="48" rx="4" fill="#f8ead3"/><path d="M74 133h24" stroke="#ac7b44" stroke-width="3"/><path d="M134 128h33l-4 35q-2 10-13 10t-13-10z" fill="#e7c18b" stroke="#c6ac88" stroke-width="2"/><path d="M150 173v15m-11 1h23" stroke="#c6ac88" stroke-width="2"/>')+'</svg>';
 }
 function status(u,id){const value=u.menuLearning?.[id]?.status;return statuses[value]?value:'new';}
 globalThis.rvbMenuLearningSummary=function(u,items=rvbMenuItems()){
  const counts={new:0,repeat:0,learned:0,total:items.length};items.forEach(i=>counts[status(u,i.id)]++);
  counts.percent=Math.round(counts.learned/Math.max(1,counts.total)*100);return counts;
 };
 function persist(action,rollback){try{save();return true;}catch{rollback();toast('Не удалось сохранить: память браузера заполнена');return false;}}
 function mark(u,id,value){
  if(!statuses[value]||!rvbMenuItems().some(i=>i.id===id))return;
  const had=!!u.menuLearning,old=u.menuLearning?.[id];u.menuLearning??={};
  u.menuLearning[id]={status:value,updatedAt:new Date().toISOString(),by:user().name,byId:user().id,changedByManager:!!manager};
  if(persist(null,()=>{if(old)u.menuLearning[id]=old;else delete u.menuLearning[id];if(!had)delete u.menuLearning;}))toast('Отметка сохранена');
 }
 function markers(u,item){return `<div class="menu-markers" role="group" aria-label="Статус изучения: ${esc(item.name)}">${Object.entries(statuses).map(([id,label])=>`<button type="button" class="menu-marker ${status(u,item.id)===id?'selected':''}" aria-pressed="${status(u,item.id)===id}" data-menu-mark="${esc(item.id)}" data-status="${id}">${label}</button>`).join('')}</div>`;}
 function bindMarkers(target,u,after){target.querySelectorAll('[data-menu-mark]').forEach(b=>b.onclick=()=>{mark(u,b.dataset.menuMark,b.dataset.status);after();});}
 function ingredients(item){return Array.isArray(item.ingredients)?item.ingredients:[];}
 function composition(item){return `<ul class="menu-ingredients">${ingredients(item).map(i=>`<li><span>${esc(i.name)}</span>${i.amount?`<strong>${esc(i.amount)}</strong>`:''}</li>`).join('')}</ul>`;}
 function image(item){return item.image?`<img class="menu-item-photo" src="${esc(item.image)}" alt="${esc(item.name)}" loading="lazy">`:`<div class="menu-item-placeholder" aria-hidden="true">${esc(item.name?.slice(0,1)||'✦')}</div>`;}
 function unusedPdfViewer(){return `<details class="menu-source"><summary>Оригинальное барное пособие · PDF</summary><p class="muted">Исходный файл · 18,6 МБ. Редактирование карточек в приложении не изменяет PDF.</p><iframe title="Барное пособие РВБ Минск" src="assets/rvb-menu/bar-manual.pdf" loading="lazy"></iframe><a class="btn secondary" href="assets/rvb-menu/bar-manual.pdf" target="_blank" rel="noopener">Открыть PDF отдельно ↗</a></details>`;}
 function filtered(items){const query=filter.search.trim().toLocaleLowerCase('ru');return items.filter(i=>(!filter.category||i.category===filter.category)&&(!filter.subcategory||i.subcategory===filter.subcategory)&&(!query||(i.name+' '+(i.description||'')+' '+(i.taste||'')+' '+ingredients(i).map(x=>x.name).join(' ')).toLocaleLowerCase('ru').includes(query))&&(!filter.status||status(user(),i.id)===filter.status));}


 function studyText(value){
  let text=(value||'').trim();
  if(/^Что запомнить:|^Характеристика пока отсутствует|^Написание в карте|^Название в таблице/.test(text))return '';
  text=text.replace(/Ориентир по (?:сорту|стилю) — /g,'').replace(/;[^.!?]*(?:уточн|сверя|зависит)[^.!?]*/gi,'');
  return text.split(/(?<=[.!?])\s+/).filter(line=>!/(?:порция|цена|\d+\s*р\.|в таблице|в нашей карте|в актуальн|в карте |в меню |барной карты|уточн|свер[ья]|сверить|подтвержд|поставк|производител[ья] и|без дозировок|позици[яию])/i.test(line)).filter((line,index,all)=>all.indexOf(line)===index).join(' ').trim();
 }
 function studyItem(item){
  const result={...item};for(const key of ['description','fact','features','method','garnish'])result[key]=studyText(item[key]);
  const normalized=value=>(value||'').toLocaleLowerCase('ru').replace(/[^а-яёa-z0-9]/g,'');
  const ingredientText=normalized(ingredients(item).map(i=>i.name).join(' '));
  const desc=normalized(result.description.replace(/^[^.!?]+\. /,''));
  if(ingredientText&&desc===ingredientText)result.description='';
  if(result.fact&&(normalized(result.fact)===normalized(result.description)||normalized(result.fact)===ingredientText))result.fact='';
  if(normalized(result.description)===normalized(item.taste))result.taste='';
  if(normalized(result.features)===normalized(result.description)||normalized(result.features)===ingredientText)result.features='';
  return result;
 }
 function factPanel(item,source){
  const cocktail=item.category==='cocktails',title=cocktail?'Состав':'Интересный факт';
  if(!cocktail&&!item.fact?.trim())return ''; 
  const body=cocktail?(ingredients(item).length?composition(item):'<p>Состав добавит менеджер.</p>'):'<p>'+esc(item.fact||'')+'</p>';
  return '<div class="menu-fact"><div class="menu-fact-heading"><h3>'+title+'</h3><button type="button" class="menu-edit-inline" data-menu-edit="'+esc(item.id)+'" data-menu-field="'+(cocktail?'ingredients':'fact')+'" aria-label="Редактировать '+title.toLowerCase()+': '+esc(item.name)+'">✎ Изменить</button></div>'+body+'</div>';
 }
 function menuCard(item,u){
  item=studyItem(item);
  const photo=safeLink(item.image),source=safeLink(item.factSource);
  return `<article class="menu-item menu-study-card"><div class="menu-study-head"><div class="menu-study-main"><span class="menu-study-kind">${esc((item.category==='wine'?item.subcategory+' · '+item.wineService:item.subcategory)||categories[item.category])}</span><h2>${esc(item.name)}</h2><div class="menu-price-volume"><div><strong>${esc(item.price||'Уточнить')}</strong><small>Цена за порцию</small></div><div><strong>${esc(item.volume||'Уточнить')}</strong><small>Объём порции</small></div></div></div><div class="menu-study-visual ${['alcohol','wine'].includes(item.category)?'is-bottle':''}">${photo?'<button type="button" class="menu-photo-open" data-menu-photo="'+esc(item.id)+'" aria-label="Увеличить изображение: '+esc(item.name)+'"><img data-menu-photo-image="'+esc(item.id)+'" src="'+esc(photo)+'" alt="'+esc(item.name)+'" loading="lazy" decoding="async"><span aria-hidden="true">⌕</span></button>':categoryArt(item)}${item.imageKind==='illustration'||!photo?'<small>Иллюстрация</small>':''}</div></div><div class="menu-item-body">${item.description?'<h3>О напитке</h3><p class="menu-description">'+esc(item.description)+'</p>':''}${item.taste?'<div class="menu-taste-chips">'+item.taste.split(/[·,]/).filter(Boolean).map(t=>'<span>'+esc(t.trim())+'</span>').join('')+'</div>':''}${factPanel(item,source)}${(item.category!=='cocktails'&&ingredients(item).length)||item.method||item.garnish||item.features?'<details class="menu-recipe"><summary>Подача и приготовление</summary>'+(item.category==='cocktails'?'':composition(item))+(item.features?'<h3>Что запомнить</h3><p>'+esc(item.features)+'</p>':'')+(item.method?'<h3>Как готовить</h3><p>'+esc(item.method)+'</p>':'')+(item.garnish?'<h3>Подача и украшение</h3><p>'+esc(item.garnish)+'</p>':'')+'</details>':''}<h3 class="menu-mark-title">Моя отметка</h3>${markers(u,item)}<button type="button" class="menu-edit-inline" data-menu-edit="${esc(item.id)}">✎ Редактировать позицию · менеджер</button></div></article>`;
 }
 function learner(){
  const items=rvbMenuItems(),counts=rvbMenuLearningSummary(user(),items);
  const subs=subcategories(items,filter.category);
  if(!subs.includes(filter.subcategory))filter.subcategory='';
  $('#content').innerHTML=`<div class="menu-page-top"><button class="back" id="menu-library-back">← В библиотеку</button><button class="menu-edit-inline" id="menu-manage">Управление меню</button></div><div class="eyebrow">АКАДЕМИЯ КОМАНДЫ</div><h1>Меню РВБ</h1><p class="muted">Изучай напитки, запоминай детали и отмечай свой прогресс.</p><div class="menu-learning-summary"><strong>${counts.percent}%<small>выучено</small></strong><div><span>${counts.learned} из ${counts.total} позиций</span><div class="progress"><i style="width:${counts.percent}%"></i></div><small>${counts.new} не учил · ${counts.repeat} повторить</small></div></div><div class="menu-category-tabs menu-main-tabs" role="group" aria-label="Раздел меню"><button class="${!filter.category?'active':''}" data-menu-category="" aria-pressed="${!filter.category}">Все<span>${items.length}</span></button>${Object.entries(categories).map(([id,title])=>'<button class="'+(filter.category===id?'active':'')+'" data-menu-category="'+id+'" aria-pressed="'+(filter.category===id)+'">'+title+'<span>'+items.filter(i=>i.category===id).length+'</span></button>').join('')}</div>${filter.category&&subs.length?'<div class="menu-category-tabs menu-sub-tabs" role="group" aria-label="Категории напитков"><button data-menu-subcategory="" class="'+(!filter.subcategory?'active':'')+'" aria-pressed="'+(!filter.subcategory)+'">Все категории</button>'+subs.map(sub=>'<button data-menu-subcategory="'+esc(sub)+'" class="'+(filter.subcategory===sub?'active':'')+'" aria-pressed="'+(filter.subcategory===sub)+'">'+esc(sub)+'</button>').join('')+'</div>':''}<div class="menu-search-row"><label for="menu-search">Найти позицию<input type="search" id="menu-search" placeholder="Название или ингредиент" value="${esc(filter.search)}"></label><label for="menu-status">Мои отметки<select id="menu-status"><option value="">Все позиции</option>${Object.entries(statuses).map(([id,label])=>'<option value="'+id+'" '+(filter.status===id?'selected':'')+'>'+label+'</option>').join('')}</select></label></div><p class="muted menu-result-count" id="menu-count"></p><div class="menu-grid" id="menu-cards"></div>`;
  $('#menu-library-back').onclick=()=>go('library');$('#menu-manage').onclick=()=>editPosition();
  document.querySelectorAll('[data-menu-category]').forEach(b=>b.onclick=()=>{filter.category=b.dataset.menuCategory;filter.subcategory='';learner();});
  document.querySelectorAll('[data-menu-subcategory]').forEach(b=>b.onclick=()=>{filter.subcategory=b.dataset.menuSubcategory;learner();});
  $('#menu-search').oninput=e=>{filter.search=e.target.value;paint();};$('#menu-status').onchange=e=>{filter.status=e.target.value;paint();};paint();
 }
 function paint(){const list=filtered(rvbMenuItems()),target=$('#menu-cards');if(!target)return;$('#menu-count').textContent='Найдено: '+list.length;target.innerHTML=list.length?list.map(i=>menuCard(i,user())).join(''):'<div class="card empty">Позиций с такими условиями пока нет. Измени поиск или отметку изучения.</div>';bindMarkers(target,user(),learner);target.querySelectorAll('[data-menu-photo]').forEach(b=>b.onclick=()=>openPhoto(rvbMenuItems().find(i=>i.id===b.dataset.menuPhoto)));target.querySelectorAll('[data-menu-photo-image]').forEach(img=>img.onerror=()=>{img.closest('.menu-study-visual').innerHTML=categoryArt(rvbMenuItems().find(i=>i.id===img.dataset.menuPhotoImage))+'<small>Фото недоступно</small>';});target.querySelectorAll('[data-menu-edit]').forEach(b=>b.onclick=()=>{editPosition(b.dataset.menuEdit);if(b.dataset.menuField){const field=$('#menu-edit-'+b.dataset.menuField);field?.scrollIntoView?.({block:'center'});field?.focus?.();}});}
 globalThis.openRvbMenu=function(category){if(categories[category])filter.category=category;filter.subcategory='';manager=false;go('rvb-menu');};
 function managerShell(){
  const members=teamUsers(),allItems=rvbMenuItems(),stats=$('#content .stats');
  if(stats){const learned=members.reduce((n,u)=>n+rvbMenuLearningSummary(u,allItems).learned,0),percent=Math.round(learned/Math.max(1,members.length*allItems.length)*100);stats.innerHTML=`<div class="card"><div class="stat">${members.length}</div><span class="muted">Сотрудников</span></div><div class="card"><div class="stat">${allItems.length}</div><span class="muted">Позиций меню</span></div><div class="card"><div class="stat">${percent}%</div><span class="muted">Выучено командой</span></div>`;}
  $('#managerbody').innerHTML=`<div class="menu-manager-heading"><h2>Меню РВБ</h2><p class="muted">Единые карточки меню и личные отметки команды. Фильтр заведения выше задаёт список сотрудников.</p></div><div class="menu-inner-tabs"><button class="${mode==='progress'?'active':''}" id="menu-progress-tab">Прогресс команды</button><button class="${mode==='editor'?'active':''}" id="menu-editor-tab">Редактор меню</button></div><div id="menu-manager-panel"></div><p class="note">Демонстрационный кабинет: изменения и отметки доступны только в этом браузере. Права менеджера и синхронизация с Telegram пока не подключены.</p>`;
  $('#menu-progress-tab').onclick=()=>{mode='progress';managerShell();};$('#menu-editor-tab').onclick=()=>{mode='editor';managerShell();};if(mode==='editor')editor();else progress();
 }
 function progress(){
  const target=$('#menu-manager-panel'),items=rvbMenuItems(),all=teamUsers();
  const departments=[...new Set(all.map(u=>u.department))];if(department&&!departments.includes(department)){department='';position='';}
  const positions=[...new Set(all.filter(u=>!department||u.department===department).map(u=>u.position))];if(position&&!positions.includes(position))position='';
  const rows=all.filter(u=>(!department||u.department===department)&&(!position||u.position===position)&&u.name.toLocaleLowerCase('ru').includes(employeeSearch.trim().toLocaleLowerCase('ru')));
  if(!rows.some(u=>u.id===selectedEmployee))selectedEmployee=rows[0]?.id||'';
  const selected=rows.find(u=>u.id===selectedEmployee);
  target.innerHTML=`<div class="menu-team-filters"><label for="menu-employee-search">Поиск сотрудника<input id="menu-employee-search" type="search" value="${esc(employeeSearch)}" placeholder="Имя или фамилия"></label><label for="menu-employee-department">Подразделение<select id="menu-employee-department"><option value="">Все подразделения</option>${departments.map(d=>`<option ${d===department?'selected':''}>${esc(d)}</option>`).join('')}</select></label><label for="menu-employee-position">Должность<select id="menu-employee-position"><option value="">Все должности</option>${positions.map(p=>`<option ${p===position?'selected':''}>${esc(p)}</option>`).join('')}</select></label></div><div class="menu-team-summary">${rows.map(u=>{const n=rvbMenuLearningSummary(u,items);return `<button class="menu-employee-card ${u.id===selectedEmployee?'active':''}" data-menu-employee="${esc(u.id)}" aria-pressed="${u.id===selectedEmployee}"><span><strong>${esc(u.name)}</strong>${u.demo?'<em>Демо</em>':''}<small>${esc(u.position)} · ${esc(restaurantName(u.restaurantId))}</small></span><b>${n.percent}%</b><span class="menu-mini-counts"><i>${n.new} не учил</i><i>${n.repeat} повторить</i><i>${n.learned} выучил</i></span></button>`;}).join('')||'<p class="empty">Нет сотрудников по выбранным фильтрам.</p>'}</div>${selected?`<div class="menu-employee-detail"><h3>Отметки: ${esc(selected.name)}</h3><p class="muted">Меняй отметку у каждой позиции. Изменение сразу попадёт в статистику сотрудника.</p><label for="menu-manager-category">Раздел меню<select id="menu-manager-category"><option value="">Все разделы</option>${Object.entries(categories).map(([id,title])=>`<option value="${id}" ${filter.category===id?'selected':''}>${title}</option>`).join('')}</select></label><div id="menu-person-items">${items.filter(i=>!filter.category||i.category===filter.category).map(i=>`<article class="menu-person-item"><div><span class="muted">${esc(categories[i.category])}</span><h4>${esc(i.name)}</h4>${selected.menuLearning?.[i.id]?.updatedAt?`<small class="muted">${selected.menuLearning[i.id].changedByManager?'Изменил менеджер: ':'Отметил: '}${esc(selected.menuLearning[i.id].by||selected.name)} · ${new Date(selected.menuLearning[i.id].updatedAt).toLocaleString('ru-RU')}</small>`:''}</div>${markers(selected,i)}</article>`).join('')}</div></div>`:''}`;
  $('#menu-employee-search').oninput=e=>{employeeSearch=e.target.value;const start=e.target.selectionStart;progress();const input=$('#menu-employee-search');input.focus();input.setSelectionRange(start,start);};
  $('#menu-employee-department').onchange=e=>{department=e.target.value;position='';progress();};$('#menu-employee-position').onchange=e=>{position=e.target.value;progress();};
  target.querySelectorAll('[data-menu-employee]').forEach(b=>b.onclick=()=>{selectedEmployee=b.dataset.menuEmployee;progress();});
  if(selected){$('#menu-manager-category').onchange=e=>{filter.category=e.target.value;progress();};bindMarkers(target,selected,managerShell);}
 }
 function editor(){
  const items=rvbMenuItems();if(!creating&&!items.some(i=>i.id===selectedItem))selectedItem=items[0]?.id||'';
  const item=(!creating&&items.find(i=>i.id===selectedItem))||{id:'',name:'',category:'cocktails',ingredients:[]};
  const target=$('#menu-manager-panel');
  target.innerHTML=`<div class="card menu-editor"><div class="row"><h3>Редактор карточек</h3><button class="btn secondary" id="menu-new-item">+ Позиция</button></div><label for="menu-editor-select">Позиция<select id="menu-editor-select"><option value="" ${creating?'selected':''}>Новая позиция</option>${items.map(i=>`<option value="${esc(i.id)}" ${!creating&&i.id===selectedItem?'selected':''}>${esc(categories[i.category]+' · '+i.name)}</option>`).join('')}</select></label><form id="menu-edit-form"><label for="menu-edit-name">Название<input id="menu-edit-name" required maxlength="180" value="${esc(item.name||'')}"></label><label for="menu-edit-category">Раздел<select id="menu-edit-category">${Object.entries(categories).map(([id,title])=>`<option value="${id}" ${item.category===id?'selected':''}>${title}</option>`).join('')}</select></label><label for="menu-edit-subcategory">Категория внутри раздела<input id="menu-edit-subcategory" maxlength="100" value="${esc(item.subcategory||'')}" list="menu-subcategories"></label><datalist id="menu-subcategories">${subcategories(items,'').map(t=>'<option value="'+esc(t)+'">').join('')}</datalist><label for="menu-edit-image">Ссылка на фото<input type="text" id="menu-edit-image" value="${esc(item.image||'')}" placeholder="https://…"></label><label for="menu-edit-image-caption">Подпись к изображению<input id="menu-edit-image-caption" maxlength="240" value="${esc(item.imageCaption||'')}"></label><label for="menu-edit-fact">Интересный факт<textarea id="menu-edit-fact" rows="4" maxlength="3000">${esc(item.fact||'')}</textarea></label><label for="menu-edit-volume">Выход / объём<input id="menu-edit-volume" maxlength="160" value="${esc(item.volume||'')}"></label><label for="menu-edit-glass">Посуда<input id="menu-edit-glass" maxlength="160" value="${esc(item.glass||'')}"></label><label for="menu-edit-ingredients">Состав · одна строка на ингредиент<textarea id="menu-edit-ingredients" rows="7" placeholder="Название | количество">${esc(ingredients(item).map(i=>i.name+(i.amount?' | '+i.amount:'')).join('\n'))}</textarea><small>Количество отделяй знаком |. Если количество неизвестно — оставь только название.</small></label><label for="menu-edit-method">Приготовление<textarea id="menu-edit-method" rows="5" maxlength="6000">${esc(item.method||'')}</textarea></label><label for="menu-edit-garnish">Подача и украшение<textarea id="menu-edit-garnish" rows="3" maxlength="3000">${esc(item.garnish||'')}</textarea></label><label for="menu-edit-taste">Вкус<input id="menu-edit-taste" maxlength="500" value="${esc(item.taste||'')}"></label><label for="menu-edit-features">Что запомнить<textarea id="menu-edit-features" rows="3" maxlength="3000">${esc(item.features||'')}</textarea></label><label for="menu-edit-price">Цена из меню<input id="menu-edit-price" maxlength="100" value="${esc(item.price||'')}"></label><label for="menu-edit-description">О напитке · характеристика<textarea id="menu-edit-description" rows="3" maxlength="3000">${esc(item.description||'')}</textarea></label><button class="btn" type="submit">Сохранить карточку</button><p class="muted">Личные отметки сотрудников сохранятся. Карточка изменится для всей команды в этом браузере.</p></form></div>`;
  $('#menu-editor-select').onchange=e=>{selectedItem=e.target.value;creating=!selectedItem;editor();};$('#menu-new-item').onclick=newEditor;
  $('#menu-edit-form').onsubmit=e=>{e.preventDefault();const name=$('#menu-edit-name').value.trim();if(!name)return;
   const id=(!creating&&selectedItem)||'rvb-custom-'+crypto.randomUUID(),old=db.rvbMenuOverrides?.[id];db.rvbMenuOverrides??={};
   const value={...(item.id?item:{}),name,category:$('#menu-edit-category').value,subcategory:$('#menu-edit-subcategory').value.trim(),image:safeImage($('#menu-edit-image').value.trim()),imageCaption:$('#menu-edit-image-caption').value.trim(),imageSource:item.imageSource||'',imageKind:$('#menu-edit-image').value.trim()===item.image?item.imageKind:'photo',fact:$('#menu-edit-fact').value.trim(),factSource:item.factSource||'',factSourceLabel:item.factSourceLabel||'',sourceNote:item.sourceNote||'',volume:$('#menu-edit-volume').value.trim(),glass:$('#menu-edit-glass').value.trim(),ingredients:$('#menu-edit-ingredients').value.split('\n').map(line=>{const [name,...rest]=line.split('|');return {name:name.trim(),amount:rest.join('|').trim()};}).filter(i=>i.name),method:$('#menu-edit-method').value.trim(),garnish:$('#menu-edit-garnish').value.trim(),description:$('#menu-edit-description').value.trim(),taste:$('#menu-edit-taste').value.trim(),features:$('#menu-edit-features').value.trim(),price:$('#menu-edit-price').value.trim(),editedAt:new Date().toISOString(),editedBy:user().name};
   db.rvbMenuOverrides[id]=value;if(persist(null,()=>{if(old)db.rvbMenuOverrides[id]=old;else delete db.rvbMenuOverrides[id];})){selectedItem=id;creating=false;toast('Карточка меню сохранена');managerShell();}
  };
 }
 function newEditor(){creating=true;selectedItem='';editor();}
 managerPage=function(){
  originalManager();const tabs=$('#content .tabs');if(!tabs)return;
  const b=document.createElement('button');b.textContent='Меню РВБ';b.className=mtab==='rvb-menu'?'active':'';b.onclick=()=>{mtab='rvb-menu';managerPage();};tabs.prepend(b);
  if(mtab==='rvb-menu')managerShell();
 };
 render=function(){
  originalRender();
  if(!user()||manager)return;
  if(view==='rvb-menu')learner();
  if(view==='home'){
   const counts=rvbMenuLearningSummary(user()),card=document.createElement('section');
   card.className='card menu-home-entry';
   card.innerHTML=`<div class="eyebrow">РУКИ ВВЕРХ БАР</div><h2>Меню РВБ</h2><p>Вино, алкоголь, коктейли, настойки, сеты и б/а напитки</p><p class="muted">Выучено ${counts.learned} из ${counts.total} · Повторить ${counts.repeat}</p><button class="btn" id="home-rvb-menu">Изучать меню РВБ →</button>`;
   const intro=$('#content .dashboard-intro');if(intro)intro.after(card);else $('#content').prepend(card);
   $('#home-rvb-menu').onclick=()=>{filter.search='';filter.status='';filter.category='';filter.subcategory='';openRvbMenu();window.scrollTo(0,0);};
  }
 };
 render();
})();



