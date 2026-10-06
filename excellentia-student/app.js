const S={questions:[],modules:[],lessons:null,manifest:null,release:null,session:null,timer:null};
const $=s=>document.querySelector(s), all=s=>[...document.querySelectorAll(s)];
const IS_PREVIEW=location.hostname==='html-preview.github.io';
const RAW_BASE='https://raw.githubusercontent.com/Terminator364/BuildHub/main/excellentia-student/';
const assetUrl=u=>IS_PREVIEW?RAW_BASE+u.replace(/^\.\//,''):u;
const key='exc_gateway_v230';
const loadState=()=>{try{return JSON.parse(localStorage.getItem(key)||'{}')}catch{return {}}};
const saveState=v=>localStorage.setItem(key,JSON.stringify(v));
const state=loadState(); state.progress=state.progress||{}; state.history=state.history||[]; saveState(state);

function netLabel(){const e=$('#net');e.textContent=navigator.onLine?'En ligne · PWA':'Hors ligne · cache';}
addEventListener('online',netLabel);addEventListener('offline',netLabel);netLabel();

async function j(url){const finalUrl=assetUrl(url);const r=await fetch(finalUrl,{cache:'no-cache'});if(!r.ok)throw new Error(finalUrl+' '+r.status);return r.json();}
async function loadAll(){
  S.manifest=await j('./data/gateway-manifest.json');
  const [mods,less,rel]=await Promise.all([j('./data/modules.json'),j('./data/lessons.json'),j('./data/release.json')]);
  S.modules=mods;S.lessons=less;S.release=rel;
  const files=S.manifest.question_files;let done=0,all=[];
  for(let i=0;i<files.length;i+=4){
    const group=files.slice(i,i+4);
    const parts=await Promise.all(group.map(f=>j('./data/'+f)));
    for(const a of parts)all.push(...a);
    done+=group.length;
    const pct=Math.round(done/files.length*100);$('#loadPct').textContent=pct+'%';$('#loadBar').style.width=pct+'%';$('#loadText').textContent=done+' / '+files.length+' lots chargés';
  }
  const ids=new Set(),clean=[];
  for(const q of all){if(!q||!q.id||!Array.isArray(q.choices)||q.answer==null||ids.has(q.id))continue;ids.add(q.id);clean.push(q)}
  S.questions=clean;
  $('#qCount').textContent=clean.length.toLocaleString('fr-FR');
  $('#kCount').textContent=new Set(clean.map(q=>q.knowledge_id).filter(Boolean)).size.toLocaleString('fr-FR');
  document.documentElement.dataset.ready=String(clean.length);
  $('#loading').classList.add('hidden');$('#dashboard').classList.remove('hidden');
  renderDashboard();
  const saved=state.session;if(saved&&saved.items?.length) $('[data-action="resume"]').disabled=false; else $('[data-action="resume"]').disabled=true;
}
function mastery(q){const p=state.progress[q.knowledge_id||q.id]||{};return (p.correct||0)-(p.wrong||0)*.7}
function weighted(pool){return [...pool].sort((a,b)=>mastery(a)-mastery(b)+Math.random()-.5)}
function sample(pool,n){return weighted(pool).slice(0,Math.min(n,pool.length))}
function renderDashboard(){
  const total=Object.values(state.progress).reduce((n,p)=>n+(p.seen||0),0),correct=Object.values(state.progress).reduce((n,p)=>n+(p.correct||0),0);
  const mastered=Object.values(state.progress).filter(p=>(p.correct||0)>=3&&(p.correct||0)>(p.wrong||0)*2).length;
  $('#stats').innerHTML='<div><b>'+total+'</b><span>réponses</span></div><div><b>'+(total?Math.round(correct/total*100):0)+'%</b><span>réussite</span></div><div><b>'+mastered+'</b><span>maîtrisées</span></div>';
  $('#modules').innerHTML=S.modules.map(m=>{
    const c=S.questions.filter(q=>Number(q.module)===Number(m.id)).length;
    return '<article class="module"><h4>'+m.id+'. '+m.title+'</h4><p>'+m.description+'</p><div class="moduleFooter"><small>'+c.toLocaleString('fr-FR')+' questions</small><button data-module="'+m.id+'">Étudier</button></div></article>'
  }).join('');
  const lessonRows=[];
  for(const [mid,arr] of Object.entries(S.lessons.modules||{})) for(const l of arr) lessonRows.push([mid,l]);
  $('#lessons').innerHTML=lessonRows.slice(0,40).map(([mid,l])=>'<details class="lesson"><summary>'+l.title+'</summary><p>'+l.summary+'</p><ul>'+(l.points||[]).slice(0,4).map(x=>'<li>'+x+'</li>').join('')+'</ul><button data-lesson-module="'+mid+'">Questions du module</button></details>').join('');
  all('[data-module]').forEach(b=>b.onclick=()=>start({mode:'training',module:Number(b.dataset.module),count:30}));
  all('[data-lesson-module]').forEach(b=>b.onclick=()=>start({mode:'training',module:Number(b.dataset.lessonModule),count:20}));
}
function start({mode='training',module=null,count=30}={}){
  let pool=module?S.questions.filter(q=>Number(q.module)===module):S.questions;
  if(mode==='exam') count=100;
  const items=sample(pool,count).map(q=>q.id);
  S.session={mode,module,items,index:0,answers:[],started_at:Date.now(),paused:false,remaining_ms:40000,deadline:Date.now()+40000};
  state.session=S.session;saveState(state);showSession();
}
function restore(){if(!state.session)return;S.session=state.session;showSession();}
function currentQ(){const id=S.session.items[S.session.index];return S.questions.find(q=>q.id===id)}
function tick(){
  clearInterval(S.timer); if(!S.session||S.session.paused)return;
  S.timer=setInterval(()=>{
    const rem=Math.max(0,S.session.deadline-Date.now());S.session.remaining_ms=rem;
    const t=$('#timer');if(t){t.textContent=Math.ceil(rem/1000)+'s';t.classList.toggle('warn',rem<=10000)}
    if(rem<=0){clearInterval(S.timer);answer(null,true)}
  },200);
}
function showSession(){
  $('#dashboard').classList.add('hidden');$('#result').classList.add('hidden');$('#session').classList.remove('hidden');
  S.session=state.session||S.session;if(!S.session)return;
  if(S.session.paused){renderQuestion();return}
  if(!S.session.deadline)S.session.deadline=Date.now()+(S.session.remaining_ms||40000);
  renderQuestion();tick();
}
function renderQuestion(){
  const q=currentQ(); if(!q){finish();return}
  const n=S.session.index+1,total=S.session.items.length;
  const paused=S.session.paused;
  $('#session').innerHTML='<div class="card"><div class="sessionTop"><div><b>'+(S.session.mode==='exam'?'Examen blanc':'Entraînement')+'</b><div class="muted">Question '+n+' / '+total+(q.origin_year?' · EXETAT '+q.origin_year:'')+'</div></div><div id="timer" class="timer">'+Math.ceil((S.session.remaining_ms||40000)/1000)+'s</div></div><div class="progress"><i style="width:'+Math.round((n-1)/total*100)+'%"></i></div><div class="question">'+q.prompt+'</div><div class="choices">'+q.choices.map((c,i)=>'<button class="choice" data-choice="'+i+'" '+(paused?'disabled':'')+'>'+String.fromCharCode(65+i)+'. '+c+'</button>').join('')+'</div><div id="feedback"></div><div class="sessionActions"><button id="pauseBtn">'+(paused?'Reprendre':'Pause')+'</button><button id="quitBtn">Quitter</button></div></div>';
  all('[data-choice]').forEach(b=>b.onclick=()=>answer(Number(b.dataset.choice),false));
  $('#pauseBtn').onclick=()=>togglePause();$('#quitBtn').onclick=()=>home();
}
function togglePause(){
  if(!S.session.paused){S.session.remaining_ms=Math.max(0,S.session.deadline-Date.now());S.session.paused=true;clearInterval(S.timer)}
  else{S.session.paused=false;S.session.deadline=Date.now()+(S.session.remaining_ms||40000)}
  state.session=S.session;saveState(state);renderQuestion();tick();
}
function updateProgress(q,ok){
  const k=q.knowledge_id||q.id,p=state.progress[k]||{seen:0,correct:0,wrong:0};p.seen++;ok?p.correct++:p.wrong++;p.last_at=Date.now();state.progress[k]=p;
}
function answer(choice,timeout=false){
  clearInterval(S.timer);const q=currentQ();if(!q)return;
  const ok=choice===q.answer;updateProgress(q,ok);
  S.session.answers.push({id:q.id,choice,correct:q.answer,ok,timeout,at:Date.now()});
  state.session=S.session;saveState(state);
  if(S.session.mode==='exam'){next();return}
  all('[data-choice]').forEach((b,i)=>{b.disabled=true;if(i===q.answer)b.classList.add('correct');if(i===choice&&!ok)b.classList.add('wrong')});
  const fb=$('#feedback');fb.innerHTML='<div class="feedback"><b>'+(timeout?'Temps écoulé':ok?'Correct ✅':'Incorrect')+'</b><p>'+(q.explanation||('Réponse : '+q.choices[q.answer]))+'</p><button id="nextBtn" class="primary">Question suivante</button></div>';
  $('#nextBtn').onclick=next;saveState(state);
}
function next(){S.session.index++;if(S.session.index>=S.session.items.length){finish();return}S.session.remaining_ms=40000;S.session.deadline=Date.now()+40000;S.session.paused=false;state.session=S.session;saveState(state);renderQuestion();tick();}
function finish(){
  clearInterval(S.timer);const s=S.session,ans=s.answers||[],correct=ans.filter(a=>a.ok).length,score=ans.length?Math.round(correct/ans.length*100):0;
  state.history.push({mode:s.mode,module:s.module,score,correct,total:ans.length,at:Date.now()});state.history=state.history.slice(-50);delete state.session;saveState(state);S.session=null;
  $('#session').classList.add('hidden');$('#result').classList.remove('hidden');
  $('#result').innerHTML='<div class="card resultHero"><div class="badge">'+(s.mode==='exam'?'EXAMEN BLANC':'ENTRAÎNEMENT')+'</div><div class="score">'+score+'%</div><h2>'+correct+' / '+ans.length+'</h2><p>'+(score>=85?'Très solide.':score>=70?'Bon niveau, continue la consolidation.':'Revoir les connaissances faibles avant le prochain blanc.')+'</p><button class="primary" id="backHome">Retour à l’accueil</button></div>';
  $('#backHome').onclick=home;renderDashboard();
}
function home(){clearInterval(S.timer);$('#session').classList.add('hidden');$('#result').classList.add('hidden');$('#dashboard').classList.remove('hidden');renderDashboard()}
document.addEventListener('click',e=>{const a=e.target.closest('[data-action]');if(!a)return;if(a.dataset.action==='start-mix')start({mode:'training',count:40});if(a.dataset.action==='start-exam')start({mode:'exam',count:100});if(a.dataset.action==='resume')restore()});
all('[data-nav]').forEach(b=>b.onclick=()=>home());
if('serviceWorker'in navigator&&!IS_PREVIEW)navigator.serviceWorker.register('./sw.js').catch(()=>{});
loadAll().catch(err=>{$('#loadText').textContent='Erreur de chargement : '+err.message+' · Réessaie avec Internet une fois, puis le cache prendra le relais.';console.error(err)});
