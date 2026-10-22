// Add demo menu marks once, preserving every saved personal or manager mark.
function addDemoMenuLearning(){
 if(db.demoMenuLearningVersion>=1||!globalThis.RVB_MENU_ITEMS?.length)return;
 const scenarios={
  'demo-anna':[32,18],'demo-maxim':[22,25],'demo-daria':[12,30],'demo-ilya':[0,0],
  'demo-alina':[62,0],'demo-nikita':[45,12],'demo-pavel':[15,35],'demo-sofia':[0,0],
  'demo-kitchen-anton':[20,14],'demo-kitchen-elena':[8,18],
  'demo-art-vera':[38,16],'demo-art-roman':[5,12],
  'demo-hookah-timur':[28,20],'demo-hookah-artem':[10,32],
  'demo-leader-olga':[55,7],'demo-leader-denis':[40,15],
  'demo-senior-egor':[50,8],'demo-barback-kirill':[8,24],
  'demo-admin-maria':[48,10],'demo-hostess-polina':[36,20]
 };
 const previous=structuredClone(db),items=globalThis.RVB_MENU_ITEMS;
 const date=new Date().toISOString();
 for(const [offset,[id,[learned,repeat]]]of Object.entries(scenarios).entries()){
  const u=db.users.find(u=>u.id===id&&u.demo===true);if(!u)continue;
  u.menuLearning??={};
  items.forEach((item,i)=>{
   if(Object.prototype.hasOwnProperty.call(u.menuLearning,item.id))return;
   // Spread each level across all categories instead of filling the first section.
   const rank=(i*17+offset*7)%items.length;
   u.menuLearning[item.id]={status:rank<learned?'learned':rank<learned+repeat?'repeat':'new',updatedAt:date,by:'Демо-данные',byId:'demo-seed',changedByManager:false,demo:true};
  });
 }
 db.demoMenuLearningVersion=1;
 try{save();}catch(error){Object.assign(db,previous);delete db.demoMenuLearningVersion;console.warn('Не удалось сохранить демо-отметки меню',error);}
}
addDemoMenuLearning();
