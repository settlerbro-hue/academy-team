/* Account UI and Supabase Auth adapter. Demo progress is deliberately separate. */
(() => {
  const config = window.ACADEMY_AUTH_CONFIG || {};
  const configured = /^https:\/\/[a-z0-9.-]+$/i.test(config.supabaseUrl || '') && !!config.publishableKey;
  const client = configured && window.supabase ? window.supabase.createClient(config.supabaseUrl, config.publishableKey, {
    auth: { flowType: 'pkce', detectSessionInUrl: true, persistSession: true, autoRefreshToken: true, storageKey: 'academy-auth-session' }
  }) : null;
  const state = { mode: 'register', step: 1, account: {}, team: {}, session: null, busy: false, recovery: false, message: '' };
  const originalRegistration = registration;
  const originalRender = render;
  const googleIcon = '<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><path fill="#4285F4" d="M21.6 12.2c0-.7-.1-1.4-.2-2.2H12v4.3h5.4a4.6 4.6 0 0 1-2 3v2.8h3.3c1.9-1.8 2.9-4.5 2.9-7.9Z"/><path fill="#34A853" d="M12 22c2.7 0 5-.9 6.7-2.5l-3.3-2.7c-.9.6-2 .9-3.4.9-2.6 0-4.8-1.8-5.6-4.2H3v2.8A10 10 0 0 0 12 22Z"/><path fill="#FBBC05" d="M6.4 13.5a6 6 0 0 1 0-3V7.7H3a10 10 0 0 0 0 8.6l3.4-2.8Z"/><path fill="#EA4335" d="M12 6.3c1.5 0 2.8.5 3.8 1.5L18.6 5A9.5 9.5 0 0 0 12 2a10 10 0 0 0-9 5.7l3.4 2.8A6 6 0 0 1 12 6.3Z"/></svg>';
  const callback = () => location.origin + location.pathname + '?auth=callback';
  const hasAuthRoute = () => location.hash !== '#demo' && (['#register','#login','#recover'].includes(location.hash) || new URLSearchParams(location.search).get('auth') === 'callback');
  const normalizeEmail = value => value.trim().toLowerCase();
  function notify(message, error = false) {
    const box = document.getElementById('auth-message');
    if (box) { box.textContent = message; box.hidden = false; box.classList.toggle('is-error', error); box.setAttribute('role', error ? 'alert' : 'status'); }
  }
  function requireConnection() {
    if (client) return true;
    notify('Вход ещё подключается. Пока можно посмотреть демонстрацию академии — аккаунт для неё не нужен.', true);
    return false;
  }
  function friendlyError(error) {
    if (/invalid.login|invalid.credentials/i.test(error?.code + ' ' + error?.message)) return 'Не удалось войти. Проверьте email и пароль.';
    if (/rate|too.many|over.*limit/i.test(error?.code + ' ' + error?.message)) return 'Слишком много попыток. Попробуйте немного позже.';
    if (/email.not.confirmed/i.test(error?.code + ' ' + error?.message)) return 'Подтвердите email по ссылке в письме, затем войдите.';
    return 'Не удалось выполнить запрос. Попробуйте ещё раз позже.';
  }
  async function perform(action) {
    if (state.busy) return;
    state.busy = true;
    const buttons = [...document.querySelectorAll('.auth-screen button')];
    buttons.forEach(b => { b.disabled = true; });
    document.querySelector('.auth-card')?.setAttribute('aria-busy','true');
    try { await action(); } catch (error) { notify(friendlyError(error), true); }
    finally { state.busy = false; buttons.filter(b => b.isConnected).forEach(b => { b.disabled = false; }); document.querySelector('.auth-card')?.removeAttribute('aria-busy'); }
  }
  function teamFields() {
    const d = state.team.department || 'Зал';
    return `<div class="field"><label for="auth-name">Имя и фамилия</label><input id="auth-name" name="full_name" autocomplete="name" required minlength="3" maxlength="80" placeholder="Анна Иванова" value="${esc(state.team.full_name || state.account.name || '')}"></div><div class="field"><label for="auth-restaurant">Заведение</label><select id="auth-restaurant" name="restaurant_id" required><option value="" disabled ${!state.team.restaurant_id?'selected':''}>Выберите заведение</option>${RESTAURANTS.map(r=>`<option value="${r.id}" ${r.id===state.team.restaurant_id?'selected':''}>${esc(r.name)}</option>`).join('')}</select></div><div class="auth-field-pair"><div class="field"><label for="auth-department">Подразделение</label><select id="auth-department" name="department">${Object.keys(DEPARTMENTS).map(v=>`<option ${v===d?'selected':''}>${esc(v)}</option>`).join('')}</select></div><div class="field"><label for="auth-position">Должность</label><select id="auth-position" name="position">${DEPARTMENTS[d].map(v=>`<option ${v===state.team.position?'selected':''}>${esc(v)}</option>`).join('')}</select></div></div><p class="auth-team-note">После регистрации менеджер подтвердит, что вы в команде. Должность не даёт доступ к кабинету менеджера автоматически.</p>`;
  }
  function passwordField(id, label, autocomplete = 'new-password') {
    return `<div class="field"><label for="${id}">${label}</label><div class="auth-password"><input id="${id}" name="${id}" type="password" autocomplete="${autocomplete}" required ${autocomplete==='new-password'?'minlength="8"':''} maxlength="128" placeholder="${autocomplete==='new-password'?'Не менее 8 символов':'Ваш пароль'}"><button type="button" data-password="${id}" aria-label="Показать пароль" aria-pressed="false">Показать</button></div></div>`;
  }
  function content() {
    if (state.recovery) return `<h2>Новый пароль</h2><p class="auth-subtitle">Придумайте пароль для следующего входа.</p><form id="auth-reset">${passwordField('auth-new-password','Новый пароль')}<button class="auth-primary" type="submit">Сохранить пароль →</button></form>`;
    if (state.session) {
      const meta = state.session.user.user_metadata || {};
      if (meta.academy_enrollment_requested) return `<div class="auth-success-mark" aria-hidden="true">✓</div><h2>Заявка отправлена</h2><p class="auth-subtitle">${esc(meta.full_name || 'Вы')} — почти в команде.</p><div class="auth-summary"><strong>${esc(restaurantName(meta.restaurant_id))}</strong><span>${esc(meta.department)} · ${esc(meta.position)}</span></div><p>Профиль сохранён. Доступ к обучению появится после подтверждения менеджером и подключения общего кабинета.</p><button type="button" class="auth-secondary" id="auth-signout">Выйти из аккаунта</button>`;
      state.team.full_name ||= meta.full_name || meta.name || '';
      return `<span class="auth-step-label">АККАУНТ ПОДТВЕРЖДЁН</span><h2>Знакомимся с командой</h2><p class="auth-subtitle">Осталось выбрать, где и кем вы работаете.</p><form id="auth-team">${teamFields()}<button class="auth-primary" type="submit">Отправить заявку →</button></form><button type="button" class="auth-text-link" id="auth-signout">Выйти из аккаунта</button>`;
    }
    if (state.mode === 'recover') return `<a class="auth-back" href="#login">← Вернуться ко входу</a><h2>Забыли пароль?</h2><p class="auth-subtitle">Укажите email — отправим ссылку для восстановления.</p><form id="auth-recover"><div class="field"><label for="auth-email">Email</label><input id="auth-email" name="email" type="email" autocomplete="email" required maxlength="254" placeholder="you@example.com"></div><button class="auth-primary" type="submit">Отправить ссылку →</button></form>`;
    const signup = state.mode === 'register';
    return `<nav class="auth-tabs" aria-label="Вход или регистрация"><a href="#register" ${signup?'aria-current="page"':''}>Регистрация</a><a href="#login" ${!signup?'aria-current="page"':''}>Вход</a></nav>${signup?`<div class="auth-steps" aria-label="Шаг ${state.step} из 2"><span class="${state.step===1?'is-current':'is-done'}">01 <b>Аккаунт</b></span><i></i><span class="${state.step===2?'is-current':''}">02 <b>Команда</b></span></div>`:''}<h2>${signup?state.step===1?'Вступить в команду':'Где ты создаёшь атмосферу?':'С возвращением!'}</h2><p class="auth-subtitle">${signup?state.step===1?'Все знания для уверенной смены — в одном месте.':'Выбери заведение, подразделение и должность.':'Войди, чтобы продолжить обучение.'}</p>${!signup || state.step===1?`<button type="button" class="auth-google" id="auth-google">${googleIcon}<span>${signup?'Продолжить с Google':'Войти через Google'}</span></button><div class="auth-divider"><span>или через email</span></div><form id="auth-account"><div class="field"><label for="auth-email">Email</label><input id="auth-email" name="email" type="email" autocomplete="${signup?'email':'username'}" required maxlength="254" placeholder="you@example.com" value="${esc(state.account.email || '')}"></div>${passwordField('auth-password','Пароль',signup?'new-password':'current-password')}${signup?passwordField('auth-confirm','Повторите пароль'): '<a href="#recover" class="auth-forgot">Не помню пароль</a>'}<button class="auth-primary" type="submit">${signup?'Далее: о себе':'Войти'} <span aria-hidden="true">→</span></button></form>`:`<form id="auth-team">${teamFields()}<button class="auth-primary" type="submit">Создать аккаунт →</button><button class="auth-text-link" type="button" id="auth-step-back">← Назад к аккаунту</button></form>`}`;
  }
  function renderPage() {
    $('#app').innerHTML = `<main class="auth-screen"><div class="auth-layout"><aside class="auth-story">${brand()}<div class="auth-story-content"><span class="auth-kicker">ОДНА АКАДЕМИЯ · ДВА БРЕНДА</span><h1>Свои<br>в команде<span class="auth-star" aria-hidden="true">✳</span></h1><p>Знай меню. Чувствуй гостей.<br>Создавай атмосферу.</p><div class="auth-benefits"><span>Обучение в своём ритме</span><span>Меню всегда под рукой</span><span>Твой прогресс и достижения</span></div></div><div class="auth-story-bottom">90-е & Руки Вверх Бар <span>АКАДЕМИЯ КОМАНДЫ</span></div></aside><section class="auth-form-area" aria-label="Аккаунт сотрудника"><div class="auth-mobile-brand">${brand()}</div><div class="auth-card">${content()}<div id="auth-message" class="auth-message" role="status" tabindex="-1" hidden></div>${!client?'<p class="auth-connection-note"><span aria-hidden="true">●</span> Регистрация и вход скоро откроются</p>':''}</div><footer class="auth-footer"><span>Хочешь сначала посмотреть?</span><a href="#demo">Открыть демонстрацию <span aria-hidden="true">↗</span></a></footer></section></div></main>`;
    bind();
    if (state.message) { notify(state.message); state.message=''; }
  }
  function validatePassword(form) {
    const p = form.querySelector('#auth-password'), confirm = form.querySelector('#auth-confirm');
    if (confirm) { confirm.setCustomValidity(p.value === confirm.value ? '' : 'Пароли не совпадают'); confirm.oninput=()=>confirm.setCustomValidity(''); p.oninput=()=>confirm.setCustomValidity(''); }
    return form.reportValidity();
  }
  function bind() {
    document.querySelectorAll('[data-password]').forEach(b => b.onclick=()=>{
      const field=document.getElementById(b.dataset.password), show=field.type==='password';
      field.type=show?'text':'password'; b.textContent=show?'Скрыть':'Показать'; b.setAttribute('aria-pressed',String(show)); b.setAttribute('aria-label',show?'Скрыть пароль':'Показать пароль');
    });
    const dep=$('#auth-department');
    if(dep)dep.onchange=()=>{ $('#auth-position').innerHTML=DEPARTMENTS[dep.value].map(v=>`<option>${esc(v)}</option>`).join(''); };
    const back=$('#auth-step-back');if(back)back.onclick=()=>{readTeam();state.step=1;renderPage();};
    const google=$('#auth-google');if(google)google.onclick=()=>perform(async()=>{
      if(!requireConnection())return;
      const { error }=await client.auth.signInWithOAuth({provider:'google',options:{redirectTo:callback(),queryParams:{prompt:'select_account'}}});if(error)throw error;
    });
    const account=$('#auth-account');if(account)account.onsubmit=e=>{
      e.preventDefault();if(!validatePassword(account))return;
      state.account.email=normalizeEmail($('#auth-email').value);
      if(state.mode==='register'){state.account.password=$('#auth-password').value;state.step=2;renderPage();$('#auth-name')?.focus();return;}
      const password=$('#auth-password').value;
      perform(async()=>{if(!requireConnection())return;const {data,error}=await client.auth.signInWithPassword({email:state.account.email,password});if(error)throw error;state.session=data.session;state.account={};renderPage();});
    };
    const team=$('#auth-team');if(team)team.onsubmit=e=>{e.preventDefault();if(!team.reportValidity())return;readTeam();perform(async()=>{
      if(!requireConnection())return;
      const metadata={...state.team,academy_enrollment_requested:true};
      if(state.session){const {data,error}=await client.auth.updateUser({data:metadata});if(error)throw error;state.session.user=data.user;renderPage();return;}
      const password=state.account.password;state.account.password='';
      const {data,error}=await client.auth.signUp({email:state.account.email,password,options:{emailRedirectTo:callback(),data:metadata}});
      if(error){state.step=1;renderPage();throw error;}
      if(data.session){state.session=data.session;state.account={};renderPage();}
      else {state.mode='login';state.step=1;state.message='Проверьте почту. Если регистрация доступна для этого адреса, придёт письмо с дальнейшими шагами.';history.replaceState(null,'',location.pathname+'#login');renderPage();}
    });};
    const recover=$('#auth-recover');if(recover)recover.onsubmit=e=>{e.preventDefault();perform(async()=>{if(!requireConnection())return;const {error}=await client.auth.resetPasswordForEmail(normalizeEmail($('#auth-email').value),{redirectTo:callback()});if(error)throw error;notify('Если аккаунт с таким email существует, на него придёт ссылка для восстановления.');});};
    const reset=$('#auth-reset');if(reset)reset.onsubmit=e=>{e.preventDefault();perform(async()=>{if(!requireConnection())return;const {error}=await client.auth.updateUser({password:$('#auth-new-password').value});if(error)throw error;state.recovery=false;state.message='Пароль сохранён.';renderPage();});};
    const logout=$('#auth-signout');if(logout)logout.onclick=()=>perform(async()=>{const {error}=await client.auth.signOut();if(error)throw error;state.session=null;state.recovery=false;state.account={};state.team={};state.mode='login';history.replaceState(null,'',location.pathname+'#login');renderPage();});
  }
  function readTeam(){for(const name of ['full_name','restaurant_id','department','position']){const f=document.querySelector(`[name="${name}"]`);if(f)state.team[name]=f.value.trim();}}
  registration=function(){if(location.hash==='#demo')originalRegistration();else renderPage();};
  render=function(){
    if(hasAuthRoute()||(!user()&&location.hash!=='#demo')){renderPage();return;}
    originalRender();
    if(user()&&view==='profile'&&!manager){const content=$('#content');if(content&&!$('#open-auth')){const a=document.createElement('a');a.id='open-auth';a.className='filelink';a.href='#register';a.textContent='Регистрация и вход в аккаунт →';content.append(a);}}
  };
  window.addEventListener('hashchange',()=>{state.mode=location.hash==='#login'?'login':location.hash==='#recover'?'recover':'register';state.step=1;state.account.password='';render();window.scrollTo(0,0);});
  state.mode=location.hash==='#login'?'login':location.hash==='#recover'?'recover':'register';
  render();
  if(client){
    client.auth.onAuthStateChange((event,session)=>{state.session=session;if(event==='PASSWORD_RECOVERY')state.recovery=true;if(hasAuthRoute())renderPage();});
    client.auth.getSession().then(({data,error})=>{if(error){if(hasAuthRoute())notify(friendlyError(error),true);return;}state.session=data.session;if(hasAuthRoute())renderPage();}).catch(()=>{if(hasAuthRoute())notify('Не удалось проверить вход. Попробуйте обновить страницу.',true);});
  }
  window.AcademyAuth={configured:!!client};
})();
