/* Local PDF.js renderer: one page at a time to keep mobile memory bounded. */
window.academyRenderPDF=async function(container,src,title){
 container.className='attachment-pdf-viewer';
 const status=document.createElement('p');status.setAttribute('role','status');status.textContent='Открываем PDF…';container.append(status);
 let task,observer;
 try{
  const pdfjs=await import('./vendor/pdf.js');pdfjs.GlobalWorkerOptions.workerSrc=new URL('./vendor/pdf.worker.js',location.href).href;
  if(!container.isConnected)return;
  task=pdfjs.getDocument({url:src,isEvalSupported:false,enableXfa:false});
  observer=new MutationObserver(()=>{if(!container.isConnected){observer.disconnect();task.destroy();}});observer.observe(document.getElementById('app'),{childList:true,subtree:true});
  const pdf=await task.promise;if(!container.isConnected)return;
  const toolbar=document.createElement('div');toolbar.className='pdf-toolbar';
  const prev=document.createElement('button'),next=document.createElement('button'),count=document.createElement('span');
  prev.type=next.type='button';prev.className=next.className='ghost';prev.textContent='← Назад';next.textContent='Далее →';count.setAttribute('aria-live','polite');toolbar.append(prev,count,next);
  const zoomBar=document.createElement('div');zoomBar.className='pdf-zoom';const smaller=document.createElement('button'),larger=document.createElement('button'),zoomCount=document.createElement('span');smaller.type=larger.type='button';smaller.className=larger.className='ghost';smaller.textContent='−';larger.textContent='+';smaller.setAttribute('aria-label','Уменьшить PDF');larger.setAttribute('aria-label','Увеличить PDF');zoomCount.setAttribute('aria-live','polite');zoomBar.append(smaller,zoomCount,larger);
  const pageScroll=document.createElement('div');pageScroll.className='pdf-page-scroll';pageScroll.tabIndex=0;pageScroll.setAttribute('role','region');pageScroll.setAttribute('aria-label','Страница PDF, прокрутка увеличенного документа');const canvas=document.createElement('canvas');canvas.setAttribute('role','img');canvas.style.width='100%';canvas.style.maxWidth='none';canvas.style.height='auto';pageScroll.append(canvas);container.append(toolbar,zoomBar,pageScroll);
  let pageNumber=1,busy=false,zoom=1;
  async function render(){if(busy)return;busy=true;prev.disabled=next.disabled=smaller.disabled=larger.disabled=true;status.textContent='Загружаем страницу…';
   try{const page=await pdf.getPage(pageNumber);if(!container.isConnected)return;const base=page.getViewport({scale:1});const width=Math.max(240,pageScroll.clientWidth||360);const scale=Math.min(3,Math.sqrt(8000000/(base.width*base.height)),(width/base.width)*zoom*Math.min(devicePixelRatio||1,2));const viewport=page.getViewport({scale});canvas.style.width=(zoom*100)+'%';canvas.width=Math.ceil(viewport.width);canvas.height=Math.ceil(viewport.height);canvas.setAttribute('aria-label',title+', страница '+pageNumber);await page.render({canvasContext:canvas.getContext('2d'),viewport}).promise;status.textContent='';count.textContent=pageNumber+' / '+pdf.numPages;zoomCount.textContent=Math.round(zoom*100)+'%';
   }catch(e){if(container.isConnected)status.textContent='Страница не открылась. Попробуйте обновить просмотр или открыть PDF отдельно.';}
   finally{busy=false;prev.disabled=pageNumber<=1;next.disabled=pageNumber>=pdf.numPages;smaller.disabled=zoom<=1;larger.disabled=zoom>=3;}
  }
  prev.onclick=()=>{if(!busy&&pageNumber>1){pageNumber--;pageScroll.scrollTo(0,0);render();}};next.onclick=()=>{if(!busy&&pageNumber<pdf.numPages){pageNumber++;pageScroll.scrollTo(0,0);render();}};smaller.onclick=()=>{if(!busy&&zoom>1){zoom-=.5;render();}};larger.onclick=()=>{if(!busy&&zoom<3){zoom+=.5;render();}};await render();
 }catch(e){if(container.isConnected)status.textContent='Не удалось открыть PDF. Откройте файл отдельно или обновите просмотр.';observer?.disconnect();task?.destroy();}
};
