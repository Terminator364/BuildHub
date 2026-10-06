
const qs=(s,r=document)=>r.querySelector(s), qsa=(s,r=document)=>[...r.querySelectorAll(s)];
const STORE='excellentia_gateway_student_v231', SESSION='excellentia_gateway_session_v231';
const TABS={
  home:[['overview','Vue d’ensemble'],['mission','Mission'],['day','Journée']],
  learn:[['modules','Modules'],['lessons','Leçons'],['bank','Banque']],
  train:[['guided','Guidé'],['sprint','Sprint'],['mix','Grand Mix']],
  review:[['due','À revoir'],['errors','Erreurs'],['weak','Faiblesses']],
  exam:[['mock','Examen blanc'],['history','Historique']],
  progress:[['overview','Vue d’ensemble'],['mastery','Maîtrise'],['history','Historique']]
};
const TITLES={home:'Accueil',learn:'Apprendre',train:'S’entraîner',review:'Réviser',exam:'Examens',progress:'Progression'};
const S={questions:[],modules:[],lessons:{modules:{}},manifest:null,space:'home',tab:'overview',session:null,timer:null,ready:false};
let P={progress:{},history:[],theme:'light',daily:null};
try{P={...P,...JSON.parse(localStorage.getItem(STORE)||'{}')}}catch{}
function save(){localStorage.setItem(STORE,JSON.stringify(P))}
function esc(v){return String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]))}
function num(v){return Number(v||0).toLocaleString('fr-FR')}
function pct(v){return Math.round(Number(v||0))+'%'}
function date(v){try{return new Date(v).toLocaleString('fr-FR',{day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'})}catch{return '—'}}
function clamp(v,a,b){return Math.max(a,Math.min(b,v))}
function toast(title,body){
  const stack=qs('#toasts'); if(!stack)return;
  const el=document.createElement('div'); el.className='toast'; el.innerHTML='<b>'+esc(title)+'</b><p>'+esc(body||'')+'</p>';
  stack.appendChild(el); setTimeout(()=>el.remove(),3300)
}
function metric(v,l){return '<div class="metric"><b>'+esc(v)+'</b><span>'+esc(l)+'</span></div>'}
function progressBar(v,kind=''){return '<div class="progress-track"><div class="progress-fill '+kind+'" style="width:'+clamp(Number(v||0),0,100)+'%"></div></div>'}
function stat(k){return P.progress[k]||{seen:0,correct:0,wrong:0,last_at:0}}
function allStats(){
  const vals=Object.values(P.progress);
  const seen=vals.reduce((n,p)=>n+(p.seen||0),0), correct=vals.reduce((n,p)=>n+(p.correct||0),0), wrong=vals.reduce((n,p)=>n+(p.wrong||0),0);
  const mastered=vals.filter(p=>(p.correct||0)>=3&&(p.correct||0)>=(p.wrong||0)*2+1).length;
  const weak=vals.filter(p=>(p.wrong||0)>(p.correct||0)).length;
  return {seen,correct,wrong,mastered,weak,accuracy:seen?correct/seen*100:0}
}
function mastery(q){const p=stat(q.knowledge_id||q.id); return (p.correct||0)*2-(p.wrong||0)*2-Math.min(4,(p.seen||0)*.15)}
function shuffle(a){const x=[...a];for(let i=x.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[x[i],x[j]]=[x[j],x[i]]}return x}
function choose(pool,n,weakFirst=true){
  const x=[...pool];
  if(weakFirst)x.sort((a,b)=>mastery(a)-mastery(b)+(Math.random()-.5)*1.4);
  else x.sort(()=>Math.random()-.5);
  return x.slice(0,Math.min(n,x.length));
}
function lessonRows(){
  const out=[];
  for(const [mid,arr] of Object.entries(S.lessons.modules||{})) for(const l of arr||[]) out.push({module:Number(mid),...l});
  return out
}
function questionsForModule(id){return S.questions.filter(q=>Number(q.module)===Number(id))}
function moduleById(id){return S.modules.find(m=>Number(m.id)===Number(id))}
function networkUI(){
  const on=navigator.onLine;
  qs('#netDot')?.classList.toggle('off',!on);
  if(qs('#netLabel'))qs('#netLabel').textContent=on?'Internet + cache local':'Hors ligne · cache local';
  qs('#syncPill')?.classList.toggle('off',!on);
  if(qs('#syncLabel'))qs('#syncLabel').textContent=on?'Connecté':'Hors ligne'
}
addEventListener('online',networkUI);addEventListener('offline',networkUI);

async function j(url){const r=await fetch(url,{cache:'no-cache'});if(!r.ok)throw new Error('HTTP '+r.status+' · '+url);return r.json()}
async function load(){
  const host=qs('#viewHost');
  host.innerHTML='<div class="empty-state"><div class="empty-inner"><div class="empty-icon">◌</div><h3>Chargement d’Excellentia</h3><p>Préparation du corpus et du cache hors ligne…</p></div></div>';
  S.manifest=await j('./data/gateway-manifest.json');
  const base=await Promise.all([j('./data/modules.json'),j('./data/lessons.json')]);
  S.modules=base[0];S.lessons=base[1];
  let all=[];
  for(let i=0;i<S.manifest.question_files.length;i+=4){
    const files=S.manifest.question_files.slice(i,i+4);
    const parts=await Promise.all(files.map(f=>j('./data/'+f)));
    parts.forEach(a=>all.push(...a));
  }
  const seen=new Set();S.questions=all.filter(q=>q&&q.id&&Array.isArray(q.choices)&&Number.isInteger(q.answer)&&!seen.has(q.id)&&seen.add(q.id));
  S.ready=true;
  document.documentElement.setAttribute('data-ready',String(S.questions.length));
  document.body.setAttribute('data-ready',String(S.questions.length));
  if(S.questions.length!==S.manifest.expected_questions)toast('Corpus partiel',S.questions.length+' / '+S.manifest.expected_questions+' questions');
  restoreSession();
  render();
}
function setActiveNav(){
  qsa('[data-space]').forEach(b=>b.classList.toggle('active',b.dataset.space===S.space));
}
function renderTabs(){
  const tabs=TABS[S.space]||[];
  if(!tabs.some(x=>x[0]===S.tab))S.tab=tabs[0]?.[0]||'overview';
  qs('#contextTabs').innerHTML=tabs.map(t=>'<button data-tab="'+t[0]+'" class="'+(t[0]===S.tab?'active':'')+'">'+esc(t[1])+'</button>').join('');
  qsa('#contextTabs [data-tab]').forEach(b=>b.onclick=()=>{S.tab=b.dataset.tab;render()});
}
function go(space,tab){
  if(!TITLES[space])space='home';
  S.space=space;S.tab=tab||(TABS[space]?.[0]?.[0]||'overview');
  closeMobile();render();
}
function render(){
  setActiveNav();renderTabs();networkUI();
  qs('#pageTitle').textContent=TITLES[S.space]||'Excellentia';
  qs('#breadcrumbs').textContent='Excellentia / '+(TITLES[S.space]||'Accueil');
  qs('#versionBadge').textContent='V'+(S.manifest?.version||'2.3.0');
  qs('#buildChip').textContent='V'+(S.manifest?.version||'2.3.0')+' · Élève';
  qs('#reviewNavBadge').textContent=allStats().weak;
  const host=qs('#viewHost');
  if(!S.ready){host.innerHTML='<div class="empty-state"><div class="empty-inner"><div class="empty-icon">◌</div><h3>Chargement</h3></div></div>';return}
  if(S.session){renderSession();return}
  if(S.space==='home')return renderHome();
  if(S.space==='learn')return renderLearn();
  if(S.space==='train')return renderTrain();
  if(S.space==='review')return renderReview();
  if(S.space==='exam')return renderExam();
  if(S.space==='progress')return renderProgress();
}
function homeHero(){
  const a=allStats(),last=P.history.at(-1);
  return '<section class="hero coach-hero"><div><div class="eyebrow">CULTURE GÉNÉRALE · EXCELLENTIA STUDY HUB · V'+esc(S.manifest.version)+'</div><h2>Ne choisis plus au hasard quoi réviser.</h2><p>La même plateforme Excellentia, maintenant accessible sans PC. Le moteur privilégie les notions faibles, les erreurs et les connaissances peu vues.</p><div class="hero-actions">'+
    (localStorage.getItem(SESSION)?'<button class="btn good" data-act="resume">Reprendre la session</button>':'<button class="btn good" data-act="mission">Voir ma mission</button>')+
    '<button class="btn secondary" data-act="sprint">Sprint 10 min</button></div></div>'+
    '<div class="readiness-ring" style="--score:'+Math.round(a.accuracy)+'"><div><b>'+Math.round(a.accuracy)+'</b><span>précision</span><small>'+(a.seen?'mesurée':'DÉMARRAGE')+'</small></div></div></section>'+
    '<div class="metric-grid">'+metric(num(S.questions.length),'questions culture')+metric(num(new Set(S.questions.map(q=>q.knowledge_id)).size),'notions culture')+metric(num(a.weak),'faiblesses')+metric(num(a.mastered),'maîtrisées')+metric(last?pct(last.score):'—','dernier blanc')+'</div>';
}
function renderHome(){
  const host=qs('#viewHost'), a=allStats();
  if(S.tab==='mission'){
    const weak=getWeakQuestions(30);
    host.innerHTML='<section class="section"><div class="section-head"><div><h2>Mission prioritaire</h2><p>Construite depuis tes erreurs et notions les moins maîtrisées.</p></div></div><div class="grid three">'+
      actionCard('◎','Corriger les faiblesses',weak.length+' questions prioritaires','Lancer','review','weak')+
      actionCard('↻','Révision active',Math.max(10,Math.min(30,a.weak))+' notions à revoir','Réviser','review','due')+
      actionCard('◇','Blanc froid','100 questions · 40 s/question','Démarrer','exam','mock')+
      '</div></section>';bindSpaceLinks();return
  }
  if(S.tab==='day'){
    host.innerHTML='<section class="hero"><div><div class="eyebrow">JOURNÉE DE TRAVAIL</div><h2>Parcours autonome, même si le PC est éteint.</h2><p>Enchaîne apprentissage, rappel, sprint et blanc sans perdre ta progression sur ce téléphone.</p><div class="hero-actions"><button class="btn good" id="dayStart">Commencer le bloc 1</button></div></div></section>'+
    '<section class="section"><div class="timeline">'+
      timeline('01','Apprendre','1 module faible · 20 min')+timeline('02','Rappel actif','20 notions faibles · 15 min')+timeline('03','Grand Mix','40 questions · 40 s/Q')+timeline('04','Blanc','100 questions froides')+
      '</div></section>';
    qs('#dayStart').onclick=()=>go('learn','modules');return
  }
  host.innerHTML=homeHero()+
    '<section class="section"><div class="section-head"><div><h2>Mission prioritaire</h2><p>Une prochaine action utile, pas une page vide.</p></div><button class="btn ghost small" id="allMission">Tout le plan</button></div><div class="mission-strip">'+
      '<button class="mission-card primary" data-go="review" data-tab="weak"><span class="mission-rank">1</span><div><b>Faiblesses</b><p>'+a.weak+' connaissances demandent une reprise ciblée.</p></div><em>→</em></button>'+
      '<button class="mission-card" data-go="train" data-tab="mix"><span class="mission-rank">2</span><div><b>Grand Mix</b><p>Interleaving sur tout le corpus.</p></div><em>40 Q</em></button>'+
      '<button class="mission-card" data-go="exam" data-tab="mock"><span class="mission-rank">3</span><div><b>Examen blanc</b><p>Mesurer le niveau réel sans correction immédiate.</p></div><em>100 Q</em></button>'+
    '</div></section>'+
    '<section class="section"><div class="section-head"><div><h2>Modules</h2><p>Les mêmes espaces de travail que la plateforme principale.</p></div><button class="btn ghost small" id="allModules">Tout voir</button></div><div class="module-grid">'+S.modules.slice(0,6).map(moduleCard).join('')+'</div></section>';
  bindSpaceLinks();bindModuleCards();
  qs('#allMission').onclick=()=>go('home','mission');qs('#allModules').onclick=()=>go('learn','modules');
  qsa('[data-act="mission"]').forEach(b=>b.onclick=()=>go('home','mission'));
  qsa('[data-act="sprint"]').forEach(b=>b.onclick=()=>startSession({mode:'training',count:15,label:'Sprint 10 min'}));
  qsa('[data-act="resume"]').forEach(b=>b.onclick=restoreSession);
}
function timeline(n,t,d){return '<div class="timeline-item"><b>'+n+'</b><div><strong>'+esc(t)+'</strong><p>'+esc(d)+'</p></div><span class="pill">Prêt</span></div>'}
function actionCard(icon,title,body,label,space,tab){return '<div class="card"><div class="mode-icon">'+icon+'</div><h3>'+esc(title)+'</h3><p>'+esc(body)+'</p><div style="margin-top:13px"><button class="btn secondary small" data-go="'+space+'" data-tab="'+tab+'">'+esc(label)+'</button></div></div>'}
function bindSpaceLinks(){qsa('[data-go]').forEach(b=>b.onclick=()=>go(b.dataset.go,b.dataset.tab))}
function moduleCard(m){
  const count=questionsForModule(m.id).length, p=moduleProgress(m.id);
  return '<article class="module-card"><div class="module-icon">'+m.id+'</div><div class="module-copy"><h3>'+esc(m.short||m.title)+'</h3><p>'+esc(m.description||'')+'</p><div class="mini-progress"><i style="width:'+p+'%"></i></div></div><div class="module-meta"><b>'+num(count)+' Q</b><button class="btn ghost small" data-module="'+m.id+'">Ouvrir</button></div></article>'
}
function moduleProgress(id){
  const ks=[...new Set(questionsForModule(id).map(q=>q.knowledge_id))], mastered=ks.filter(k=>{const p=stat(k);return (p.correct||0)>=3&&(p.correct||0)>=(p.wrong||0)*2+1}).length;
  return ks.length?Math.round(mastered/ks.length*100):0
}
function bindModuleCards(){qsa('[data-module]').forEach(b=>b.onclick=()=>openModule(Number(b.dataset.module)))}
function openDrawer(eyebrow,title,html){qs('#drawerEyebrow').textContent=eyebrow;qs('#drawerTitle').textContent=title;qs('#drawerBody').innerHTML=html;qs('#drawerBackdrop').classList.add('open')}
function closeDrawer(){qs('#drawerBackdrop').classList.remove('open')}
function openModule(id){
  const m=moduleById(id), lessons=lessonRows().filter(x=>x.module===id);
  const html='<div class="metric-grid" style="grid-template-columns:repeat(3,1fr);margin-top:0">'+metric(num(questionsForModule(id).length),'questions')+metric(num(lessons.length),'fiches')+metric(pct(moduleProgress(id)),'maîtrise')+'</div>'+
  '<section class="section"><div class="section-head"><div><h2>Fiches du module</h2><p>Lire puis tester immédiatement.</p></div></div><div class="grid">'+
  lessons.slice(0,30).map(l=>'<button class="card flat" data-lesson="'+esc(l.id)+'" data-mid="'+id+'" style="text-align:left"><h3>'+esc(l.title)+'</h3><p>'+esc(l.summary||'')+'</p></button>').join('')+
  '</div></section><div class="hero-actions"><button class="btn" id="drawerTrain">S’entraîner sur ce module</button></div>';
  openDrawer('MODULE '+id,m?.short||m?.title||'Module',html);
  qs('#drawerTrain').onclick=()=>{closeDrawer();startSession({mode:'training',module:id,count:30,label:m?.short||m?.title})};
  qsa('[data-lesson]').forEach(b=>b.onclick=()=>openLesson(Number(b.dataset.mid),b.dataset.lesson))
}
function openLesson(mid,id){
  const l=lessonRows().find(x=>x.module===mid&&String(x.id)===String(id)); if(!l)return;
  openDrawer('LEÇON · MODULE '+mid,l.title,'<div class="lesson-reader"><div class="eyebrow">COMPRENDRE</div><h2>'+esc(l.title)+'</h2><p>'+esc(l.summary||'')+'</p><h3>Points essentiels</h3><ul>'+(l.points||[]).map(x=>'<li>'+esc(x)+'</li>').join('')+'</ul>'+(l.recall_prompts?.length?'<div class="recall-box"><b>Rappel actif</b><p>'+esc(l.recall_prompts[0])+'</p></div>':'')+'<div class="hero-actions"><button class="btn good" id="lessonTest">Tester ce module</button></div></div>');
  qs('#lessonTest').onclick=()=>{closeDrawer();startSession({mode:'training',module:mid,count:15,label:'Mini-test · '+l.title})}
}
function renderLearn(){
  const host=qs('#viewHost');
  if(S.tab==='modules'){host.innerHTML='<section class="section"><div class="section-head"><div><h2>Modules</h2><p>Ouvre un module, lis ses fiches ou lance un entraînement ciblé.</p></div></div><div class="module-grid">'+S.modules.map(moduleCard).join('')+'</div></section>';bindModuleCards();return}
  if(S.tab==='lessons'){
    const rows=lessonRows();
    host.innerHTML='<section class="section"><div class="section-head"><div><h2>Leçons</h2><p>'+num(rows.length)+' fiches pédagogiques.</p></div></div><div class="bank-grid">'+rows.slice(0,100).map(l=>'<article class="bank-card"><header><span class="pill">M'+l.module+'</span></header><h3>'+esc(l.title)+'</h3><p>'+esc(l.summary||'')+'</p><footer><button class="btn ghost small" data-lesson="'+esc(l.id)+'" data-mid="'+l.module+'">Ouvrir</button></footer></article>').join('')+'</div></section>';qsa('[data-lesson]').forEach(b=>b.onclick=()=>openLesson(Number(b.dataset.mid),b.dataset.lesson));return
  }
  const list=S.questions.slice(0,300);
  host.innerHTML='<section class="section"><div class="section-head"><div><h2>Banque de questions</h2><p>Recherche dans les '+num(S.questions.length)+' questions.</p></div></div><div class="bank-toolbar"><input class="field" id="bankSearch" placeholder="Chercher une notion…"><select class="field" id="bankModule"><option value="">Tous modules</option>'+S.modules.map(m=>'<option value="'+m.id+'">Module '+m.id+'</option>').join('')+'</select></div><div class="bank-grid" id="bankGrid"></div></section>';
  const draw=()=>{const term=(qs('#bankSearch').value||'').toLowerCase(),mid=qs('#bankModule').value;const x=S.questions.filter(q=>(!mid||String(q.module)===mid)&&(!term||String(q.prompt).toLowerCase().includes(term)||String(q.domain||'').toLowerCase().includes(term))).slice(0,120);qs('#bankGrid').innerHTML=x.map(q=>'<article class="bank-card"><header><span class="pill">M'+q.module+'</span>'+(q.origin_year?'<span class="pill good">EXETAT '+q.origin_year+'</span>':'')+'</header><h3>'+esc(q.prompt)+'</h3><footer><button class="btn ghost small" data-one="'+q.id+'">Faire</button></footer></article>').join('');qsa('[data-one]').forEach(b=>b.onclick=()=>startSession({mode:'training',ids:[b.dataset.one],label:'Question ciblée'}))};draw();qs('#bankSearch').oninput=draw;qs('#bankModule').onchange=draw
}
function renderTrain(){
  const host=qs('#viewHost');
  if(S.tab==='guided'){host.innerHTML='<section class="section"><div class="section-head"><div><h2>Entraînement guidé</h2><p>Le moteur priorise les connaissances faibles et peu vues.</p></div></div><div class="mode-grid">'+S.modules.slice(0,8).map(m=>'<div class="mode-card"><div class="mode-icon">'+m.id+'</div><h3>'+esc(m.short||m.title)+'</h3><p>'+num(questionsForModule(m.id).length)+' questions disponibles.</p><div class="mode-foot"><span class="pill">'+pct(moduleProgress(m.id))+'</span><button class="btn small" data-train="'+m.id+'">Lancer 30</button></div></div>').join('')+'</div></section>';qsa('[data-train]').forEach(b=>b.onclick=()=>startSession({mode:'training',module:Number(b.dataset.train),count:30,label:moduleById(Number(b.dataset.train))?.short||'Module'}));return}
  if(S.tab==='sprint'){host.innerHTML='<section class="hero"><div><div class="eyebrow">SPRINT</div><h2>10 minutes. Zéro dispersion.</h2><p>15 questions prioritaires, 40 secondes par question.</p><div class="hero-actions"><button class="btn good" id="startSprint">Lancer</button></div></div></section>';qs('#startSprint').onclick=()=>startSession({mode:'training',count:15,label:'Sprint 10 min'});return}
  host.innerHTML='<section class="hero"><div><div class="eyebrow">GRAND MIX</div><h2>Interleaving sur tout le corpus.</h2><p>40 questions choisies en priorité parmi les connaissances faibles et sous-exposées.</p><div class="hero-actions"><button class="btn good" id="startMix">Lancer le Grand Mix</button></div></div></section>';qs('#startMix').onclick=()=>startSession({mode:'training',count:40,label:'Grand Mix'})
}
function getWeakQuestions(limit=100){
  const grouped=new Map();
  for(const q of S.questions){const k=q.knowledge_id||q.id,p=stat(k);if((p.wrong||0)>(p.correct||0)||((p.seen||0)>0&&(p.correct||0)/(p.seen||1)<.65)){if(!grouped.has(k))grouped.set(k,q)}}
  return choose([...grouped.values()],limit,true)
}
function renderReview(){
  const host=qs('#viewHost');
  let pool=[];
  if(S.tab==='errors')pool=S.questions.filter(q=>(stat(q.knowledge_id||q.id).wrong||0)>0);
  else if(S.tab==='weak')pool=getWeakQuestions(500);
  else pool=S.questions.filter(q=>{const p=stat(q.knowledge_id||q.id);return (p.seen||0)>0&&(Date.now()-(p.last_at||0)>24*3600*1000||p.wrong>p.correct)});
  const unique=[...new Map(pool.map(q=>[q.knowledge_id||q.id,q])).values()];
  host.innerHTML='<section class="section"><div class="section-head"><div><h2>'+(S.tab==='errors'?'Carnet d’erreurs':S.tab==='weak'?'Faiblesses':'Révisions dues')+'</h2><p>'+num(unique.length)+' connaissances disponibles.</p></div><button class="btn '+(unique.length?'':'secondary')+'" id="startReview" '+(unique.length?'':'disabled')+'>Lancer une série</button></div><div class="bank-grid">'+unique.slice(0,80).map(q=>'<article class="bank-card"><header><span class="pill">M'+q.module+'</span><span class="pill bad">'+(stat(q.knowledge_id).wrong||0)+' erreur(s)</span></header><h3>'+esc(q.prompt)+'</h3></article>').join('')+'</div></section>';
  qs('#startReview').onclick=()=>startSession({mode:'training',pool:unique,count:Math.min(30,unique.length),label:'Révision ciblée'})
}
function renderExam(){
  const host=qs('#viewHost');
  if(S.tab==='history'){
    host.innerHTML='<section class="section"><div class="section-head"><div><h2>Historique des blancs</h2><p>Seuls les examens terminés apparaissent ici.</p></div></div><div class="timeline">'+(P.history.filter(x=>x.mode==='exam').slice().reverse().map((x,i)=>'<div class="timeline-item"><b>'+pct(x.score)+'</b><div><strong>'+x.correct+' / '+x.total+'</strong><p>'+date(x.at)+'</p></div><span class="pill '+(x.score>=80?'good':x.score<60?'bad':'warn')+'">'+(x.score>=85?'Prête':x.score>=70?'Solide':'À consolider')+'</span></div>').join('')||'<div class="empty-state"><div class="empty-inner"><div class="empty-icon">◇</div><h3>Aucun blanc terminé</h3><p>Lance un premier examen froid de 100 questions.</p></div></div>')+'</div></section>';return
  }
  const last=P.history.filter(x=>x.mode==='exam').at(-1);
  host.innerHTML='<section class="hero"><div><div class="eyebrow">EXAMEN BLANC</div><h2>100 questions · 40 secondes chacune.</h2><p>Aucune correction n’est affichée pendant le blanc. Le score et les erreurs sont révélés seulement à la fin.</p><div class="hero-actions"><button class="btn good" id="startExam">Démarrer le blanc</button></div></div></section>'+
  '<div class="metric-grid">'+metric(last?pct(last.score):'—','dernier score')+metric(num(P.history.filter(x=>x.mode==='exam').length),'blancs terminés')+metric('40 s','par question')+metric('100','questions')+metric('Différée','correction')+'</div>';
  qs('#startExam').onclick=()=>startSession({mode:'exam',count:100,label:'Examen blanc'})
}
function renderProgress(){
  const host=qs('#viewHost'),a=allStats();
  if(S.tab==='mastery'){
    const rows=S.modules.map(m=>({m,score:moduleProgress(m.id),q:questionsForModule(m.id).length})).sort((a,b)=>a.score-b.score);
    host.innerHTML='<section class="section"><div class="section-head"><div><h2>Maîtrise par module</h2><p>Mesure basée sur les réponses enregistrées sur ce téléphone.</p></div></div><div class="grid">'+rows.map(x=>'<div class="card"><div class="card-row"><div><h3>'+esc(x.m.short||x.m.title)+'</h3><p>'+num(x.q)+' questions</p></div><b>'+pct(x.score)+'</b></div>'+progressBar(x.score,x.score>=70?'good':x.score<40?'warn':'')+'</div>').join('')+'</div></section>';return
  }
  if(S.tab==='history'){
    host.innerHTML='<section class="section"><div class="section-head"><div><h2>Historique récent</h2><p>Sessions terminées sur ce téléphone.</p></div></div><div class="timeline">'+P.history.slice().reverse().slice(0,50).map(x=>'<div class="timeline-item"><b>'+pct(x.score)+'</b><div><strong>'+esc(x.label||x.mode)+'</strong><p>'+x.correct+' / '+x.total+' · '+date(x.at)+'</p></div><span class="pill">'+esc(x.mode)+'</span></div>').join('')+'</div></section>';return
  }
  host.innerHTML='<section class="hero"><div><div class="eyebrow">PROGRESSION</div><h2>'+Math.round(a.accuracy)+'% de précision mesurée.</h2><p>La progression est locale à ce téléphone et reste disponible après fermeture du navigateur.</p></div></section>'+
  '<div class="metric-grid">'+metric(num(a.seen),'réponses')+metric(num(a.correct),'correctes')+metric(num(a.wrong),'incorrectes')+metric(num(a.mastered),'maîtrisées')+metric(num(a.weak),'faiblesses')+'</div>'+
  '<section class="section"><div class="module-grid">'+S.modules.map(moduleCard).join('')+'</div></section>';bindModuleCards()
}
function buildSession({mode='training',module=null,count=30,label='Session',pool=null,ids=null}){
  let qpool=ids?ids.map(id=>S.questions.find(q=>q.id===id)).filter(Boolean):(pool|| (module?questionsForModule(module):S.questions));
  const items=choose(qpool,count,mode!=='exam').map(q=>q.id);
  return {mode,module,label,items,index:0,answers:[],remaining_ms:40000,deadline:Date.now()+40000,paused:false,started_at:Date.now()}
}
function startSession(opts){S.session=buildSession(opts);localStorage.setItem(SESSION,JSON.stringify(S.session));render();startTimer()}
function restoreSession(){
  try{const x=JSON.parse(localStorage.getItem(SESSION)||'null');if(x&&x.items?.length){S.session=x;if(!x.paused&&(!x.deadline||x.deadline<Date.now())){x.remaining_ms=Math.max(0,x.remaining_ms||40000);x.deadline=Date.now()+x.remaining_ms}return true}}catch{}return false
}
function currentQuestion(){return S.questions.find(q=>q.id===S.session?.items?.[S.session.index])}
function saveSession(){if(S.session)localStorage.setItem(SESSION,JSON.stringify(S.session));else localStorage.removeItem(SESSION)}
function startTimer(){
  clearInterval(S.timer);if(!S.session||S.session.paused)return;
  S.timer=setInterval(()=>{const rem=Math.max(0,S.session.deadline-Date.now());S.session.remaining_ms=rem;const t=qs('#sessionTimer');if(t){t.textContent=Math.ceil(rem/1000)+' s';t.style.color=rem<=10000?'var(--bad)':''}if(rem<=0){clearInterval(S.timer);submitAnswer(null,true)}},200)
}
function renderSession(){
  const host=qs('#viewHost'),q=currentQuestion();if(!q){finishSession();return}
  const s=S.session,n=s.index+1,total=s.items.length,rem=Math.ceil((s.remaining_ms||40000)/1000);
  qs('#pageTitle').textContent=s.label||'Session';qs('#breadcrumbs').textContent='Excellentia / '+(s.mode==='exam'?'Examen':'Entraînement');
  qs('#contextTabs').innerHTML='<button class="active">'+(s.mode==='exam'?'Examen blanc':'Session active')+'</button>';
  host.innerHTML='<div class="question-shell"><section class="question-main"><div class="question-top"><span class="counter">Question '+n+' / '+total+(q.origin_year?' · EXETAT '+q.origin_year:'')+'</span><span class="pill">'+esc(q.domain||'Culture générale')+'</span></div><h2>'+esc(q.prompt)+'</h2><div class="answers">'+q.choices.map((c,i)=>'<button class="answer" data-answer="'+i+'"><span class="answer-key">'+String.fromCharCode(65+i)+'</span><span>'+esc(c)+'</span></button>').join('')+'</div><div id="sessionFeedback"></div><div class="question-nav"><button class="btn ghost" id="pauseSession">'+(s.paused?'Reprendre':'Pause')+'</button><button class="btn secondary" id="quitSession">Quitter</button></div></section><aside class="question-side"><div class="timer-card"><span>Temps restant</span><b id="sessionTimer">'+rem+' s</b><div class="progress-track"><div class="progress-fill '+(rem<=10?'warn':'')+'" style="width:'+(rem/40*100)+'%"></div></div></div><div class="card"><h3>'+esc(s.label||'Session')+'</h3><p>'+(s.mode==='exam'?'Correction à la fin.':'Correction après chaque réponse.')+'</p></div></aside></div>';
  qsa('[data-answer]').forEach(b=>b.onclick=()=>submitAnswer(Number(b.dataset.answer),false));
  qs('#pauseSession').onclick=togglePause;qs('#quitSession').onclick=()=>{if(confirm('Quitter la session ? Elle restera disponible pour reprise.')){S.session.paused=true;S.session.remaining_ms=Math.max(0,S.session.deadline-Date.now());saveSession();clearInterval(S.timer);go('home')}};
  if(!s.paused)startTimer()
}
function togglePause(){
  if(!S.session)return;
  if(S.session.paused){S.session.paused=false;S.session.deadline=Date.now()+(S.session.remaining_ms||40000)}
  else{S.session.remaining_ms=Math.max(0,S.session.deadline-Date.now());S.session.paused=true;clearInterval(S.timer)}
  saveSession();render()
}
function record(q,ok){const k=q.knowledge_id||q.id,p=stat(k);p.seen=(p.seen||0)+1;ok?p.correct=(p.correct||0)+1:p.wrong=(p.wrong||0)+1;p.last_at=Date.now();P.progress[k]=p;save()}
function submitAnswer(choice,timeout=false){
  if(!S.session)return;clearInterval(S.timer);const q=currentQuestion();if(!q)return;
  const ok=choice===q.answer;record(q,ok);S.session.answers.push({id:q.id,choice,correct:q.answer,ok,timeout,at:Date.now()});saveSession();
  if(S.session.mode==='exam'){return nextQuestion()}
  qsa('[data-answer]').forEach((b,i)=>{b.disabled=true;if(i===q.answer)b.classList.add('selected');if(i===q.answer)b.style.borderColor='var(--good)';if(i===choice&&!ok)b.style.borderColor='var(--bad)'});
  const fb=qs('#sessionFeedback');fb.innerHTML='<div class="lesson-note '+(ok?'':'warn')+'" style="margin-top:14px"><b>'+(timeout?'Temps écoulé':ok?'Correct ✅':'Incorrect')+'</b><p>'+esc(q.explanation||('Bonne réponse : '+q.choices[q.answer]))+'</p><button class="btn small" id="nextQuestion">Question suivante</button></div>';
  qs('#nextQuestion').onclick=nextQuestion
}
function nextQuestion(){
  S.session.index++;
  if(S.session.index>=S.session.items.length)return finishSession();
  S.session.remaining_ms=40000;S.session.deadline=Date.now()+40000;S.session.paused=false;saveSession();render();startTimer()
}
function finishSession(){
  if(!S.session)return;clearInterval(S.timer);
  const s=S.session,ans=s.answers||[],correct=ans.filter(x=>x.ok).length,total=s.items.length,score=total?Math.round(correct/total*100):0;
  P.history.push({mode:s.mode,label:s.label,score,correct,total,at:Date.now()});P.history=P.history.slice(-100);save();
  S.session=null;saveSession();S.space=s.mode==='exam'?'exam':'progress';S.tab=s.mode==='exam'?'history':'overview';render();
  openDrawer('SESSION TERMINÉE',score+' %','<div class="resultHero"><div class="score">'+score+'%</div><h2>'+correct+' / '+total+'</h2><p>'+(score>=85?'Très solide.':score>=70?'Bon niveau, continue la consolidation.':'Les erreurs doivent être retravaillées avant le prochain blanc.')+'</p><button class="btn good" id="resultClose">Continuer</button></div>');
  qs('#resultClose').onclick=closeDrawer
}
function closeMobile(){qs('#rail')?.classList.remove('open');qs('#mobileSheet')?.classList.remove('open');qs('#overlay')?.classList.remove('open')}
function openPalette(){
  const p=qs('#commandPalette');p.classList.add('open');p.setAttribute('aria-hidden','false');const i=qs('#commandInput');i.value='';drawSearch('');setTimeout(()=>i.focus(),20)
}
function closePalette(){qs('#commandPalette').classList.remove('open');qs('#commandPalette').setAttribute('aria-hidden','true')}
function drawSearch(term){
  const t=String(term||'').toLowerCase(),actions=[
    ['Accueil','home','overview'],['Modules','learn','modules'],['Leçons','learn','lessons'],['Banque','learn','bank'],['Sprint','train','sprint'],['Grand Mix','train','mix'],['Révisions','review','due'],['Examen blanc','exam','mock'],['Progression','progress','overview']
  ].filter(x=>!t||x[0].toLowerCase().includes(t));
  qs('#commandResults').innerHTML=actions.map((x,i)=>'<button data-cmd="'+i+'"><b>'+x[0]+'</b><span>'+TITLES[x[1]]+'</span></button>').join('');
  qsa('[data-cmd]').forEach(b=>b.onclick=()=>{const x=actions[Number(b.dataset.cmd)];closePalette();go(x[1],x[2])})
}
qsa('[data-space]').forEach(b=>b.onclick=()=>go(b.dataset.space));
qsa('[data-action="more"]').forEach(b=>b.onclick=()=>{qs('#mobileSheet').classList.toggle('open');qs('#overlay').classList.toggle('open')});
qs('#overlay').onclick=closeMobile;qs('#mobileMenu').onclick=()=>{qs('#rail').classList.toggle('open');qs('#overlay').classList.toggle('open')};
qs('#drawerClose').onclick=closeDrawer;qs('#drawerBackdrop').onclick=e=>{if(e.target.id==='drawerBackdrop')closeDrawer()};
qs('#commandButton').onclick=openPalette;qs('#commandInput').oninput=e=>drawSearch(e.target.value);qs('#commandPalette').onclick=e=>{if(e.target.id==='commandPalette')closePalette()};
addEventListener('keydown',e=>{if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='k'){e.preventDefault();openPalette()}if(e.key==='Escape'){closePalette();closeDrawer();closeMobile()}});
qs('#refreshButton').onclick=()=>location.reload();
qs('#themeToggle').onclick=()=>{document.body.classList.toggle('dark');P.theme=document.body.classList.contains('dark')?'dark':'light';save()};
if(P.theme==='dark')document.body.classList.add('dark');
qs('#collapseRail').onclick=()=>document.body.classList.toggle('rail-collapsed');
qs('#railScrollUp').onclick=()=>qs('#railScroll').scrollBy({top:-180,behavior:'smooth'});
qs('#railScrollDown').onclick=()=>qs('#railScroll').scrollBy({top:180,behavior:'smooth'});
if('serviceWorker' in navigator){
  navigator.serviceWorker.register('./sw.js?v=303',{updateViaCache:'none'}).then(async reg=>{
    try{await reg.update()}catch{}
    if(reg.waiting)reg.waiting.postMessage({type:'SKIP_WAITING'});
  }).catch(()=>{});
}
networkUI();load().catch(e=>{qs('#viewHost').innerHTML='<div class="empty-state"><div class="empty-inner"><div class="empty-icon">!</div><h3>Chargement impossible</h3><p>'+esc(e.message)+'</p><div class="actions"><button class="btn" onclick="location.reload()">Réessayer</button></div></div></div>'});
