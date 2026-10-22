// One-time, additive migration. Existing profiles and results are preserved.
function addDemoTeam(){
 if(db.demoTeamVersion>=1)return;
 const now=Date.now();
 const attempt=(score,days)=>({score,passed:score>=80,date:new Date(now-days*86400000).toISOString(),correct:score/20,total:5});
 const profiles=[
  ['anna','Анна Смирнова','Зал',3,[[80,5],[100,1]]],
  ['maxim','Максим Волков','Зал',3,[[60,12],[80,2]]],
  ['daria','Дарья Соколова','Зал',3,[[40,3],[60,1]]],
  ['ilya','Илья Морозов','Зал',1,[]],
  ['alina','Алина Коваль','Бар',3,[[100,18]]],
  ['nikita','Никита Орлов','Бар',3,[[40,6],[60,4],[80,1]]],
  ['pavel','Павел Белов','Бар',3,[[40,45],[60,40]]],
  ['sofia','София Лебедева','Бар',0,[]]
 ];
 for(const [id,name,department,read,attempts] of profiles){
  if(db.users.some(u=>u.id==='demo-'+id))continue;
  db.users.push({id:'demo-'+id,name,department,position:department==='Бар'?'Бармен':'Официант',demo:true,read:Array.from({length:read},(_,i)=>i),attempts:attempts.map(([score,days])=>attempt(score,days))});
 }
 db.demoTeamVersion=1;
 db.demoTeamCreatedAt=new Date(now).toISOString();
 save();
}
addDemoTeam();

// Assign the demo team across all four venues once; retain existing records.
if(!db.restaurantMigration){const assignments={'demo-anna':'minsk','demo-nikita':'minsk','demo-maxim':'pushkino','demo-alina':'pushkino','demo-daria':'khimki','demo-pavel':'khimki','demo-ilya':'mytishchi','demo-sofia':'mytishchi'};db.users.forEach(u=>{u.restaurantId=u.restaurantId||assignments[u.id]||'minsk'});db.restaurantMigration=1;save();}

function addExpandedDemoTeam(){
 if(db.demoTeamVersion>=2)return;
 const now=Date.now();
 const profiles=[
  ['kitchen-anton','Антон Громов','Кухня','Сотрудник кухни','minsk',3,[[60,9],[100,2]]],
  ['kitchen-elena','Елена Новикова','Кухня','Сотрудник кухни','pushkino',3,[[40,38],[60,32]]],
  ['art-vera','Вера Миронова','Арт','Сотрудник арт','minsk',3,[[80,16]]],
  ['art-roman','Роман Зайцев','Арт','Сотрудник арт','khimki',1,[]],
  ['hookah-timur','Тимур Сафонов','Кальян','Сотрудник кальянного подразделения','pushkino',3,[[40,5],[60,1]]],
  ['hookah-artem','Артём Фомин','Кальян','Сотрудник кальянного подразделения','mytishchi',3,[[80,65]]],
  ['leader-olga','Ольга Власова','Руководитель','Руководитель','khimki',3,[[100,3]]],
  ['leader-denis','Денис Крылов','Руководитель','Руководитель','mytishchi',3,[[60,110],[80,100]]],
  ['senior-egor','Егор Титов','Бар','Старший бармен','minsk',3,[[80,6],[100,1]]],
  ['barback-kirill','Кирилл Мельников','Бар','Барбэк','pushkino',2,[]],
  ['admin-maria','Мария Алексеева','Зал','Администратор','khimki',3,[[60,20],[80,10]]],
  ['hostess-polina','Полина Белова','Зал','Хостес','mytishchi',3,[[40,4],[60,2],[80,1]]]
 ];
 for(const [id,name,department,position,restaurantId,read,attempts] of profiles){
  if(db.users.some(u=>u.id==='demo-'+id))continue;
  db.users.push({id:'demo-'+id,name,department,position,restaurantId,demo:true,read:Array.from({length:read},(_,i)=>i),attempts:attempts.map(([score,days])=>({score,passed:score>=80,date:new Date(now-days*86400000).toISOString(),correct:score/20,total:5}))});
 }
 db.demoTeamVersion=2;
 save();
}
addExpandedDemoTeam();
