/* Scoped private material attachments. All authorization is enforced by Postgres/Storage RLS. */
'use strict';
window.createAcademyMaterialFiles=function({client,rpc,esc,getProfile}){
 const bucket='academy-materials',limit=50*1024*1024;
 const mimeByExtension={pdf:'application/pdf',jpg:'image/jpeg',jpeg:'image/jpeg',png:'image/png',webp:'image/webp',gif:'image/gif',mp4:'video/mp4',webm:'video/webm'};
 const allowed=new Set(Object.values(mimeByExtension)),lists=new Map(),signed=new Map();
 const state={busy:false,materialId:null,done:0,total:0,message:'',error:false};
 const size=n=>n<1024*1024?Math.ceil(n/1024)+' КБ':(n/(1024*1024)).toFixed(1)+' МБ';
 const kind=f=>f.mime_type==='application/pdf'?'PDF':f.mime_type.startsWith('video/')?'Видео':'Фото';
 const editorHTML=d=>`<section class="material-attachments card" style="margin-top:20px"><h2>PDF, фото и видео</h2><p class="muted">До 10 файлов, каждый до 50 МБ. PDF, JPG, PNG, WebP, GIF, MP4 и WebM.</p><label class="field">Добавить файлы<input id="material-files-input" type="file" multiple accept="application/pdf,image/jpeg,image/png,image/webp,image/gif,video/mp4,video/webm" ${state.busy?'disabled':''}></label><p class="muted">${d.isNew?'Укажите название: перед загрузкой материал автоматически сохранится черновиком.':'Доступ к файлам совпадает с доступом к этому материалу.'}</p><div id="material-upload-status" role="status" aria-live="polite"></div><div id="material-file-list"></div><div id="material-file-preview"></div></section>`;
 function updateStatus(root){const el=root.querySelector('#material-upload-status');if(el){el.className=state.error?'message error':'muted';el.textContent=state.message;if(state.busy){const bar=document.createElement('progress');bar.max=state.total;bar.value=state.done;bar.setAttribute('aria-label','Загружено файлов');el.append(bar);}}const input=root.querySelector('#material-files-input');if(input)input.disabled=state.busy;root.querySelectorAll('#material-editor input,#material-editor textarea,#material-editor select,#material-editor button,#advanced-editor').forEach(el=>el.disabled=state.busy);}
 async function list(id){const {data,error}=await client.from('academy_material_files').select('id,material_id,storage_path,filename,mime_type,byte_size,status,created_at').eq('material_id',id).order('created_at');if(error)throw error;lists.set(id,data||[]);return data||[];}
 async function url(f,force=false){const cached=signed.get(f.id);if(!force&&cached&&cached.expires>Date.now())return cached.url;const {data,error}=await client.storage.from(bucket).createSignedUrl(f.storage_path,900);if(error)throw error;signed.set(f.id,{url:data.signedUrl,expires:Date.now()+840000});return data.signedUrl;}
 function errorText(e){const m=e?.message||'';if(/maximum 10/i.test(m))return 'В материале уже 10 файлов. Уберите ненужные вложения.';if(/size|payload|exceeded/i.test(m))return 'Размер файла превышает допустимый предел.';if(/forbidden|row.level|permission|jwt/i.test(m))return 'Нет доступа к файлам этого материала. Обновите страницу или обратитесь к владельцу.';return m||'Не удалось загрузить файл. Проверьте соединение и попробуйте ещё раз.';}
 async function preview(container,files,force=false){
  if(!container)return;container.replaceChildren();
  for(const f of files){const card=document.createElement('section');card.className='attachment-view';card.innerHTML=`<div class="row between"><h3>${esc(f.filename)}</h3><span class="pill">${kind(f)} · ${size(f.byte_size)}</span></div><p class="muted" role="status">Открываем файл…</p>`;container.append(card);
   try{const src=await url(f,force);if(!card.isConnected)continue;card.querySelector('[role="status"]').remove();
    if(f.mime_type==='application/pdf'){const viewer=document.createElement('div');card.append(viewer);window.academyRenderPDF(viewer,src,f.filename);}
    else if(f.mime_type.startsWith('image/')){const img=document.createElement('img');img.className='attachment-image';img.src=src;img.alt=f.filename;img.loading='lazy';img.decoding='async';card.append(img);}
    else{const video=document.createElement('video');video.className='attachment-video';video.controls=true;video.playsInline=true;video.preload='metadata';video.src=src;video.setAttribute('aria-label',f.filename);video.addEventListener('error',()=>{const note=document.createElement('p');note.className='muted';note.textContent='Не удаётся воспроизвести видео. Откройте файл отдельно или обновите просмотр.';card.append(note);},{once:true});card.append(video);}
    const link=document.createElement('a');link.href=src;link.target='_blank';link.rel='noopener noreferrer';link.className='ghost attachment-open';link.textContent=f.mime_type==='application/pdf'?'Открыть PDF отдельно ↗':'Открыть файл отдельно ↗';card.append(link);
   }catch(e){card.querySelector('[role="status"]').textContent=errorText(e);}
  }
 }
 function renderList(root,id){const box=root.querySelector('#material-file-list');if(!box)return;const files=lists.get(id)||[];box.innerHTML=files.length?files.map(f=>`<article class="attachment-row"><div><strong>${esc(f.filename)}</strong><small>${kind(f)} · ${size(f.byte_size)} · ${f.status==='ready'?'Готов':f.status==='archived'?'Убран из материала':'Загрузка не завершена'}</small></div><div class="row">${f.status==='ready'?`<button type="button" class="ghost" data-attachment-preview="${f.id}">Посмотреть</button>`:''}${f.status==='pending'?`<button type="button" class="ghost" data-attachment-finish="${f.id}">Проверить загрузку</button>`:''}<button type="button" class="ghost" data-attachment-archive="${f.id}" data-archived="${f.status==='archived'?'false':'true'}">${f.status==='archived'?'Вернуть':'Убрать'}</button></div></article>`).join(''):'<p class="muted">Вложений пока нет.</p>';
  box.querySelectorAll('[data-attachment-preview]').forEach(b=>b.onclick=()=>preview(root.querySelector('#material-file-preview'),files.filter(f=>f.id===b.dataset.attachmentPreview)));
  box.querySelectorAll('[data-attachment-archive]').forEach(b=>b.onclick=()=>editAction(root,id,()=>rpc('academy_archive_material_file',{p_file_id:b.dataset.attachmentArchive,p_archived:b.dataset.archived==='true'})));
  box.querySelectorAll('[data-attachment-finish]').forEach(b=>b.onclick=()=>editAction(root,id,()=>rpc('academy_finish_material_file',{p_file_id:b.dataset.attachmentFinish})));
 }
 async function editAction(root,id,fn){if(state.busy)return;try{await fn();await list(id);renderList(root,id);root.querySelector('#material-file-preview')?.replaceChildren();}catch(e){Object.assign(state,{message:errorText(e),error:true});updateStatus(root);}}
 async function refreshEditor(root,id){try{await list(id);renderList(root,id);}catch(e){const box=root.querySelector('#material-file-list');if(box)box.textContent=errorText(e);}updateStatus(root);}
 function bindEditor(root,d,ensureSaved){updateStatus(root);if(!d.isNew)refreshEditor(root,d.id);const input=root.querySelector('#material-files-input');if(!input)return;
  input.onchange=async e=>{if(state.busy)return;const selected=[...e.target.files];if(!selected.length)return;
   try{const files=selected.map(file=>{const ext=file.name.split('.').pop().toLowerCase(),mime=file.type||mimeByExtension[ext];if(!allowed.has(mime)||!mimeByExtension[ext])throw Error('Формат «'+file.name+'» не поддерживается. Выберите PDF, фото или видео MP4/WebM.');if(!file.size||file.size>limit)throw Error('Файл «'+file.name+'» должен быть не пустым и не больше 50 МБ.');return {file,mime};});
    if((lists.get(d.id)||[]).filter(f=>f.status!=='archived').length+files.length>10)throw Error('В одном материале может быть до 10 файлов.');
    const saved=ensureSaved();Object.assign(state,{busy:true,done:0,total:files.length,message:'Подготавливаем загрузку…',error:false});updateStatus(root);const material=await saved;state.materialId=material.id;
    for(const {file,mime} of files){state.message='Загружаем файл '+(state.done+1)+' из '+state.total+': '+file.name;updateStatus(root);
     const reserved=await rpc('academy_reserve_material_file',{p_material_id:material.id,p_filename:file.name,p_mime_type:mime,p_byte_size:file.size});
     const {error}=await client.storage.from(bucket).upload(reserved.storage_path,file,{contentType:mime,upsert:false,cacheControl:'3600'});if(error)throw error;
     await rpc('academy_finish_material_file',{p_file_id:reserved.id});state.done++;await list(material.id);renderList(root,material.id);updateStatus(root);
    }
    state.message='Загружено файлов: '+state.done+'. Сохраните материал, чтобы применить настройку публикации.';
   }catch(e){state.error=true;state.message=errorText(e);}finally{state.busy=false;updateStatus(root);input.value='';if(state.materialId)refreshEditor(root,state.materialId);}
  };
 }
 const readerHTML=()=>'<section class="material-reader-files"><div id="material-reader-status" role="status">Загружаем вложения…</div><div id="material-reader-files"></div><button type="button" id="material-reader-refresh" class="ghost" hidden>Обновить просмотр</button></section>';
 async function mountReader(root,id,force=false){const status=root.querySelector('#material-reader-status'),box=root.querySelector('#material-reader-files'),refresh=root.querySelector('#material-reader-refresh');if(!box)return;try{const files=(await list(id)).filter(f=>f.status==='ready');if(!box.isConnected)return;if(status)status.textContent='';if(refresh){refresh.hidden=!files.length;refresh.onclick=()=>mountReader(root,id,true);}await preview(box,files,force);}catch(e){if(status)status.textContent=errorText(e);}}
 return {editorHTML,bindEditor,readerHTML,mountReader,clear(){lists.clear();signed.clear();state.message='';},isBusy:()=>state.busy};
};
