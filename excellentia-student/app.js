(function(){
'use strict';

const qs=(s,r=document)=>r.querySelector(s), qsa=(s,r=document)=>Array.from(r.querySelectorAll(s));
const initialParams=new URLSearchParams(location.search);
const QUESTION_LIMIT_SECONDS=40;
const QUESTION_LIMIT_MS=QUESTION_LIMIT_SECONDS*1000;
const QUESTION_CLOCK_KEY='exc2_question_clock';
const state={
  space:initialParams.get('space')||localStorage.getItem('exc2_space')||'home',
  tab:initialParams.get('tab')||localStorage.getItem('exc2_tab')||'today',
  theme:localStorage.getItem('exc2_theme')||'light',
  railCollapsed:localStorage.getItem('exc2_rail')==='1',
  density:localStorage.getItem('exc2_density')||'comfortable',
  textScale:localStorage.getItem('exc2_text_scale')||'normal',
  reducedMotion:localStorage.getItem('exc2_reduced_motion')==='1',
  defaultDayHours:[2,4,6,8].includes(Number(localStorage.getItem('exc2_day_hours')))?Number(localStorage.getItem('exc2_day_hours')):6,
  me:null,status:null,modules:[],stats:null,coach:null,prep:null,mastery:null,notebook:null,day:null,session:null,lesson:null,sessionReturn:null,offlinePack:null,offline:[],toast:new Map(),
  immersive:null,offlineMode:false,currentQuestionStartedAt:Date.now(),questionDeadlineMs:0,questionTimeoutBusy:false,
  previewStudent:localStorage.getItem('exc2_preview_student')==='1',dayTicker:null,connectionTicker:null,mobileHeartbeat:null,failoverFailures:0,failoverBusy:false
};
try{state.offline=JSON.parse(localStorage.getItem('exc2_offline')||'[]')}catch{state.offline=[]}
try{const s=JSON.parse(localStorage.getItem('exc2_active_session')||'null');if(s&&['ACTIVE','PAUSED'].includes(s.state))state.session=s}catch{}
try{const d=JSON.parse(localStorage.getItem('exc2_active_day')||'null');if(d&&['ACTIVE','PAUSED'].includes(d.state))state.day=d}catch{}

const SPACES={
  home:{title:'Accueil',tabs:[['today',"Aujourd’hui"],['mission','Mission'],['day',"Journée d’étude"]]},
  learn:{title:'Apprendre',tabs:[['path','Parcours'],['curriculum','4 matières'],['modules','Modules'],['cards','Fiches'],['map','Carte des connaissances']]},
  train:{title:"S’entraîner",tabs:[['adaptive','Adaptatif'],['sprint','Sprint'],['quick','Rapide'],['bank','Banque'],['errors','Mes erreurs']]},
  review:{title:'Réviser',tabs:[['due','À faire maintenant'],['notebook',"Carnet d’erreurs"],['weak','Points faibles'],['history','Historique']]},
  exam:{title:'Examens',tabs:[['mock','Blanc Culture générale'],['mini','Mini-tests'],['history','Historique']]},
  progress:{title:'Progression',tabs:[['overview',"Vue d’ensemble"],['readiness','Préparation'],['mastery','Maîtrise'],['domains','Domaines'],['speed','Vitesse'],['history','Historique']]},
  admin:{title:'Administration',tabs:[['access','Élève & accès'],['connection','Connexion'],['corpus','Corpus'],['updates','Mise à jour'],['settings','Paramètres']]}
};
const DEFAULT_TAB=Object.fromEntries(Object.entries(SPACES).map(([k,v])=>[k,v.tabs[0][0]]));
const VIEW_GUIDES={
  'home:today':['Choisir la prochaine action utile','Reprends une journée/session si elle existe ; sinon pars vers Apprendre, S’entraîner ou Réviser.','Le tableau de bord se met à jour après chaque session fiable.'],
  'home:day':['Suivre une vraie journée guidée','Travaille bloc par bloc : cours → rappel → quiz → pause → révision.','Pause ou quitte sans perdre l’état ; le bloc suivant reprend au même endroit.'],
  'home:mission':['Exécuter la prochaine meilleure action','Le coach classe les actions selon dette de mémoire, erreurs, couverture et vitesse.','Fais la première mission avant de choisir manuellement un autre parcours.'],
  'learn:path':['Savoir dans quel ordre apprendre','Commence par le socle RDC, puis Afrique, monde, sciences, culture et actualité.','Entre dans un module, ouvre une leçon et suis ses 6 étapes.'],
  'learn:curriculum':['Voir tout le périmètre Excellentia','Les quatre matières officielles sont séparées des compétences transversales de raisonnement.','Culture générale est mesurée aujourd’hui ; les autres parcours restent explicitement non mesurés tant que leurs banques ne sont pas auditées.'],
  'learn:modules':['Choisir un domaine de travail','Ouvre un module pour voir ses leçons et lancer un entraînement ciblé.','Reviens ensuite aux erreurs ou à la journée guidée.'],
  'learn:cards':['Apprendre avant de tester','Choisis Cours pour une leçon complète ou Micro-fiches pour un rappel très court.','Fais le rappel actif puis le mini-test de la leçon.'],
  'learn:map':['Comprendre la structure du corpus','Observe les unités de connaissance et leurs variantes par module.','Ouvre le module qui paraît insuffisamment couvert ou fragile.'],
  'train:adaptive':['Laisser le moteur prioriser intelligemment','Choisis 20 ou 30 questions et réponds sans support.','Lis la correction ; erreurs et lenteur reprogramment les prochaines expositions.'],
  'train:sprint':['Transformer quelques minutes en entraînement utile','Chaque question dispose de 40 secondes ; le nombre de questions détermine automatiquement la durée totale.','Un sprint garde la correction immédiate, mais une question sans réponse à 40 s est comptée fausse et avancée automatiquement.'],
  'train:quick':['Faire un bloc court immédiatement','Choisis 10, 20 ou 30 questions selon le temps disponible.','Va dans Mes erreurs si une confusion se répète.'],
  'train:bank':['Explorer sans spoiler les réponses','Recherche une notion ou filtre par module ; la bonne réponse reste cachée.','Lance ensuite 10 questions du module ou un Mix 20.'],
  'train:errors':['Transformer les erreurs en apprentissage','Travaille les erreurs issues uniquement de sessions complètes.','Une confusion récurrente doit conduire à la leçon correspondante.'],
  'review:due':['Faire ce qui est arrivé à échéance','Lance les rappels dus et réponds sans support.','Le prochain intervalle est recalculé selon la performance.'],
  'review:notebook':['Réparer les confusions, pas seulement recompter les fautes','Les erreurs sont regroupées par notion et reliées au cours quand c’est possible.','Revoir le cours si la confusion persiste ; sinon lancer un drill ciblé.'],
  'review:weak':['Identifier les domaines fragiles','Lis les domaines classés par fréquence d’erreur.','Retourne au cours si faiblesse + lenteur ; entraîne-toi si le cours est déjà maîtrisé.'],
  'review:history':['Vérifier la régularité','Regarde les sessions fiables terminées et leur évolution.','Ne tiens pas compte des anciennes sessions invalidées techniquement.'],
  'exam:mock':['Mesurer endurance et couverture','Tous les blancs utilisent exactement 40 secondes par question, sans exception.','À 0 s, une question non répondue est comptée fausse et la suivante s’ouvre automatiquement.'],
  'exam:mini':['Tester un module rapidement','Choisis le module puis fais 10 questions à 40 secondes chacune, soit 6 min 40 s au maximum.','Reviens à la leçon si les erreurs montrent une connaissance absente.'],
  'exam:history':['Comparer les examens fiables','Observe uniquement les blancs terminés et complètement synchronisés.','Utilise la tendance, pas un score isolé, pour ajuster le travail.'],
  'progress:overview':['Voir la progression sans te noyer','Compare meilleur score, moyenne récente, domaines et dernières sessions.','Ouvre Domaines ou Vitesse pour diagnostiquer le détail.'],
  'progress:readiness':['Lire un indice interne de préparation','L’indice combine précision, couverture, rétention, vitesse et régularité.','Ce n’est ni un score officiel ni une prédiction de réussite.'],
  'progress:mastery':['Voir la maîtrise notion par notion','Une seule bonne réponse ne suffit pas à déclarer une notion maîtrisée.','Priorise Fragile, puis Learning, puis Consolidating ; garde les nouvelles notions dans le parcours d’apprentissage.'],
  'progress:domains':['Comparer précision par domaine','Repère les domaines sous 50–75 % et leur volume de réponses.','Croise ensuite avec Vitesse et Mes erreurs.'],
  'progress:speed':['Distinguer lenteur et méconnaissance','Compare temps moyen et précision par domaine.','Automatise ce qui est juste mais lent ; réapprends ce qui est lent et faux.'],
  'progress:history':['Suivre l’évolution réelle','Parcours toutes les sessions fiables dans l’ordre chronologique.','Cherche une tendance sur plusieurs sessions plutôt qu’un record ponctuel.'],
  'admin:access':['Contrôler qui entre comme Élève','Crée QR/code temporaire, vérifie les sessions actives et révoque si nécessaire.','L’appareil Élève n’accède jamais aux réglages Admin.'],
  'admin:connection':['Vérifier réseau, synchronisation et B-EDGE','Contrôle PWA, écritures en attente et état du nœud maison.','Synchronise avant un changement réseau important.'],
  'admin:corpus':['Contrôler le volume et la couverture','Vérifie questions, unités de connaissance et modules actifs.','Un bon corpus privilégie unités distinctes et sources, pas le gonflage.'],
  'admin:updates':['Mettre à jour sans perdre le travail','L’agent checkpoint la session, applique la mise à jour en priorité puis l’interface reprend automatiquement.','Si health échoue, rollback automatique vers la LKG.'],
  'admin:settings':['Adapter l’interface et les habitudes','Règle thème, densité, texte, animations et durée de journée.','Ces préférences restent locales et n’altèrent pas les données pédagogiques.']
};

function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function num(v){return Number(v||0).toLocaleString('fr-FR')}
function pct(v){return Number(v||0).toLocaleString('fr-FR',{maximumFractionDigits:1})+' %'}
function time(s){s=Math.max(0,Math.floor(Number(s||0)));return String(Math.floor(s/60)).padStart(2,'0')+':'+String(s%60).padStart(2,'0')}
function date(v){try{return new Date(v).toLocaleString('fr-FR',{dateStyle:'short',timeStyle:'short'})}catch{return '—'}}
function durationLabel(sec){
  sec=Math.max(0,Math.floor(Number(sec||0)));const h=Math.floor(sec/3600),m=Math.floor((sec%3600)/60),ss=sec%60;
  if(h)return h+' h '+String(m).padStart(2,'0')+' min';
  if(m)return m+' min '+String(ss).padStart(2,'0')+' s';
  return ss+' s'
}
function stopMobileHeartbeat(){if(state.mobileHeartbeat){clearInterval(state.mobileHeartbeat);state.mobileHeartbeat=null}}
function startMobileHeartbeat(){
  stopMobileHeartbeat();if(state.me?.device!=='PAIRED_LAN')return;
  const beat=async()=>{try{
    const p=await raw('/api/mobile/ping');setNetwork(Boolean(p?.ok));
    if(p?.ok&&state.offline.length)await flushOffline();
    const current=String(state.status?.build||''),live=String(p?.build||'');
    if(current&&live&&current!==live&&!window.__excReloading){
      persistSession();persistDay();window.__excReloading=true;location.reload();return;
    }
  }catch{setNetwork(false)}};
  beat();state.mobileHeartbeat=setInterval(beat,8000)
}
function saveOffline(){localStorage.setItem('exc2_offline',JSON.stringify(state.offline))}
function persistSession(){
  try{
    if(state.session&&['ACTIVE','PAUSED'].includes(state.session.state))localStorage.setItem('exc2_active_session',JSON.stringify(state.session));
    else localStorage.removeItem('exc2_active_session')
  }catch{}
}
function readQuestionClock(){try{return JSON.parse(localStorage.getItem(QUESTION_CLOCK_KEY)||'null')}catch{return null}}
function clearQuestionClock(){state.questionDeadlineMs=0;try{localStorage.removeItem(QUESTION_CLOCK_KEY)}catch{}}
function currentQuestion(){
  const s=state.session;if(!s||!Array.isArray(s.questions)||!s.questions.length)return null;
  const i=Math.max(0,Math.min(s.questions.length-1,Number(s.position||0)));return s.questions[i]||null
}
function startQuestionClock({force=false}={}){
  const s=state.session,q=currentQuestion();if(!s||!q||s.state!=='ACTIVE')return;
  const a=s.answers?.[q.id];if(a&&a.selected!==undefined){clearQuestionClock();return}
  const now=Date.now(),saved=readQuestionClock(),serverDeadline=Number(s.question_deadline_ms||0);
  if(!force&&serverDeadline>0){
    state.questionDeadlineMs=serverDeadline;
    localStorage.setItem(QUESTION_CLOCK_KEY,JSON.stringify({session_id:s.id,question_id:q.id,position:Number(s.position||0),deadline_ms:serverDeadline,remaining_ms:Math.max(0,serverDeadline-now),paused:false}));
    return
  }
  if(!force&&saved&&saved.session_id===s.id&&saved.question_id===q.id&&Number(saved.position)===Number(s.position)&&Number(saved.deadline_ms)>0){
    state.questionDeadlineMs=Number(saved.deadline_ms);return
  }
  state.questionDeadlineMs=now+QUESTION_LIMIT_MS;
  s.question_deadline_ms=state.questionDeadlineMs;s.question_remaining_ms=QUESTION_LIMIT_MS;
  localStorage.setItem(QUESTION_CLOCK_KEY,JSON.stringify({session_id:s.id,question_id:q.id,position:Number(s.position||0),deadline_ms:state.questionDeadlineMs,remaining_ms:QUESTION_LIMIT_MS,paused:false}))
}
function questionSecondsLeft(){
  if(!state.session||state.session.state!=='ACTIVE')return QUESTION_LIMIT_SECONDS;
  if(!state.questionDeadlineMs)startQuestionClock();
  return Math.max(0,Math.ceil((Number(state.questionDeadlineMs||0)-Date.now())/1000))
}
function pauseQuestionClock(){
  const s=state.session,q=currentQuestion();if(!s||!q)return;
  const a=s.answers?.[q.id];if(a&&a.selected!==undefined){clearQuestionClock();return}
  const remaining=Math.max(0,Number(state.questionDeadlineMs||Date.now())-Date.now());
  state.questionDeadlineMs=0;
  try{localStorage.setItem(QUESTION_CLOCK_KEY,JSON.stringify({session_id:s.id,question_id:q.id,position:Number(s.position||0),deadline_ms:0,remaining_ms:remaining,paused:true}))}catch{}
}
function resumeQuestionClock(){
  const s=state.session,q=currentQuestion();if(!s||!q||s.state!=='ACTIVE')return;
  const a=s.answers?.[q.id];if(a&&a.selected!==undefined){clearQuestionClock();return}
  const saved=readQuestionClock(),remaining=saved&&saved.session_id===s.id&&saved.question_id===q.id&&saved.paused?Math.max(0,Number(saved.remaining_ms||QUESTION_LIMIT_MS)):QUESTION_LIMIT_MS;
  state.questionDeadlineMs=Date.now()+remaining;
  localStorage.setItem(QUESTION_CLOCK_KEY,JSON.stringify({session_id:s.id,question_id:q.id,position:Number(s.position||0),deadline_ms:state.questionDeadlineMs,remaining_ms:remaining,paused:false}))
}
function persistDay(){
  try{
    if(state.day&&['ACTIVE','PAUSED'].includes(state.day.state))localStorage.setItem('exc2_active_day',JSON.stringify(state.day));
    else localStorage.removeItem('exc2_active_day')
  }catch{}
}
function toast(title,detail='',key=''){
  const k=key||title+'|'+detail,now=Date.now(),last=state.toast.get(k)||0;if(now-last<1800)return;state.toast.set(k,now);
  const host=qs('#toasts'),el=document.createElement('div');el.className='toast';el.innerHTML='<b>'+esc(title)+'</b>'+(detail?'<span>'+esc(detail)+'</span>':'');host.appendChild(el);
  while(host.children.length>3)host.firstElementChild.remove();setTimeout(()=>el.remove(),3400)
}
function continuityToken(){return localStorage.getItem('exc_failover_token')||''}
function continuityOffer(){return localStorage.getItem('exc_failover_offer_created_at')||''}
function continuityExpiry(){return Number(localStorage.getItem('exc_failover_pass_expires_at')||0)}
function continuityPrefix(){
  const raw=localStorage.getItem('exc_failover_origin_ip')||location.hostname||'',p=raw.split('.');
  if(p.length!==4)return null;const n=p.map(Number);
  if(n.some(x=>!Number.isInteger(x)||x<0||x>255))return null;
  const priv=n[0]===10||n[0]===192&&n[1]===168||n[0]===172&&n[1]>=16&&n[1]<=31;
  return priv?p.slice(0,3).join('.')+'.':null
}
function encodeContinuityState(){
  try{
    const s=state.session||JSON.parse(localStorage.getItem('exc2_active_session')||'null');if(!s||!Array.isArray(s.questions))return '';
    const answers={},rows=s.answers||{};let score=0;
    for(const q of s.questions){
      const a=rows[q.id];if(!a||a.selected===undefined)continue;
      answers[q.id]=Number(a.selected);if(a.correct===true)score++
    }
    const run={
      id:'handoff:'+String(s.id||Date.now()),origin_session_id:String(s.id||''),ids:s.questions.map(q=>q.id),i:Math.max(0,Math.min(s.questions.length-1,Number(s.position||0))),
      score,answers,mode:String(s.mode||'module'),module:Number(s.module||0),started:Date.parse(s.created_at||'')||Date.now(),
      question_started_at:Number(s.question_started_at_ms||state.currentQuestionStartedAt||Date.now()),
      deadlineAt:Number(state.questionDeadlineMs||s.question_deadline_ms||0),question_limit_ms:QUESTION_LIMIT_MS
    };
    const payload={run:JSON.stringify(run),outbox:'[]',pass_expires_at_ms:continuityExpiry()};
    return btoa(unescape(encodeURIComponent(JSON.stringify(payload)))).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'')
  }catch{return ''}
}
async function probeEdgeBase(base){
  if(!base)return null;const ctl=new AbortController(),t=setTimeout(()=>ctl.abort(),900);
  try{
    const r=await fetch(String(base).replace(/\/$/,'')+'/health',{cache:'no-store',mode:'cors',signal:ctl.signal});if(!r.ok)return null;
    const j=await r.json();if(j?.mode!=='EXCELLENTIA_EDGE_CONTINUITY')return null;
    const expected=continuityOffer();if(expected&&Number(j.pass_offer_created_at||0)!==Number(expected))return null;
    return String(base).replace(/\/$/,'')
  }catch{return null}finally{clearTimeout(t)}
}
async function discoverEdgeBase(){
  const remembered=await probeEdgeBase(localStorage.getItem('exc_failover_edge_base')||'');if(remembered)return remembered;
  const prefix=continuityPrefix();if(!prefix)return null;let next=1,found=null;
  async function worker(){
    while(!found&&next<255){
      const ip=prefix+(next++);if(ip===location.hostname)continue;
      const hit=await probeEdgeBase('http://'+ip+':8878');if(hit){found=hit;break}
    }
  }
  await Promise.all(Array.from({length:24},()=>worker()));
  if(found)localStorage.setItem('exc_failover_edge_base',found);return found
}
async function attemptEdgeFailover(reason='PC_UNREACHABLE'){
  if(state.failoverBusy)return true;
  const token=continuityToken(),exp=continuityExpiry();if(!token||(exp&&Date.now()>=exp))return false;
  state.failoverBusy=true;
  try{
    toast('Bascule de secours','PC indisponible · recherche de l’ancien téléphone…','edge-failover');
    const base=await discoverEdgeBase();if(!base){state.failoverBusy=false;return false}
    const encoded=encodeContinuityState(),tail=encoded?'&state='+encodeURIComponent(encoded):'';
    sessionStorage.setItem('exc_failover_reason',reason);
    location.replace(base+'/pair#t='+encodeURIComponent(token)+tail);return true
  }catch{state.failoverBusy=false;return false}
}
async function continuityHeartbeat(){
  if(!continuityToken()||state.failoverBusy)return;
  const exp=continuityExpiry();if(exp&&Date.now()>=exp)return;
  const ctl=new AbortController(),t=setTimeout(()=>ctl.abort(),1500);
  try{
    const r=await fetch('/api/mobile/ping',{cache:'no-store',credentials:'same-origin',signal:ctl.signal});
    if(!r.ok)throw new Error('PING_'+r.status);state.failoverFailures=0
  }catch{
    state.failoverFailures++;
    if(state.failoverFailures>=2)void attemptEdgeFailover('PC_HEARTBEAT_LOST')
  }finally{clearTimeout(t)}
}
async function raw(url,opts={}){
  const r=await fetch(url,{cache:'no-store',...opts});let j=null;try{j=await r.json()}catch{}
  if(!r.ok){const e=new Error(j?.error||('HTTP '+r.status));e.status=r.status;e.payload=j;throw e}return j
}
async function api(url,opts={}){
  try{const j=await raw(url,opts);setNetwork(true);state.failoverFailures=0;return j}
  catch(e){
    setNetwork(Boolean(e.status));
    if(!e.status&&continuityToken()){state.failoverFailures++;if(state.failoverFailures>=2)void attemptEdgeFailover('PC_API_UNREACHABLE')}
    throw e
  }
}
function setNetwork(ok){
  qs('#netDot')?.classList.toggle('off',!ok);const a=qs('#netLabel');if(a)a.textContent=ok?'Sauvegarde active':'Reprise locale';
  const p=qs('#syncPill');if(p){p.classList.toggle('off',!ok);const b=p.querySelector('b');if(b)b.textContent=ok?'Connecté':'Local'}
}
function queueWrite(url,body,key=''){
  const qid=body?.question_id||'';
  const derived=key||(qid?url+'|q|'+qid:url.includes('/progress')?url+'|progress':url+'|latest');
  const i=state.offline.findIndex(x=>(x.key||((x.body?.question_id)?x.url+'|q|'+x.body.question_id:x.url+'|latest'))===derived);
  const payload=qid?{...body,_offline_replay:true}:body;
  const it={key:derived,url,body:payload,at:new Date().toISOString()};
  if(i>=0)state.offline[i]=it;else state.offline.push(it);
  saveOffline();toast('Sauvegardé localement','Synchronisation automatique dès que le serveur répond.','offline')
}
async function flushOffline(){
  if(!state.offline.length)return true;const keep=[];let sent=0;
  for(const x of state.offline){try{await raw(x.url,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(x.body)});sent++}catch{keep.push(x)}}
  state.offline=keep;saveOffline();if(sent)toast('Synchronisation',sent+' écriture(s) envoyée(s).','sync');return !keep.length
}
setInterval(flushOffline,15000);window.addEventListener('online',flushOffline);

async function getOfflinePack(force=false){
  if(state.offlinePack&&!force)return state.offlinePack;
  const r=await fetch('/api/offline-pack',{cache:'no-store'});if(!r.ok)throw new Error('OFFLINE_PACK_UNAVAILABLE');
  state.offlinePack=await r.json();return state.offlinePack
}
function offlineNorm(v){return String(v||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'')}
function offlineTokens(value){
  const raw=String(value||''),stop=new Set(['avec','dans','pour','sans','cette','cours','fiche','module','lecon','notion','des','les','une','sur','aux','par','que','qui','est','sont','plus','vers','afin','ainsi','etre','avoir','ses','ces','tout','tous','toute','toutes']);
  const words=offlineNorm(raw).match(/[a-z0-9]{3,}/g)||[],acronyms=(raw.match(/\b[A-ZÀ-ÖØ-Þ]{2,8}\b/g)||[]).map(offlineNorm);
  const aliases={ua:['union','africaine'],fmi:['fonds','monetaire','international'],oms:['organisation','mondiale','sante'],onu:['nations','unies'],bad:['banque','africaine','developpement'],fao:['alimentation','agriculture'],pam:['alimentaire','humanitaire'],monuc:['mission','nations','unies','congo'],monusco:['stabilisation','congo']};
  const out=[...words,...acronyms];for(const a of acronyms)out.push(...(aliases[a]||[]));return [...new Set(out)].filter(x=>!stop.has(x))
}
function offlineLessonWorkspace(pack,module,id){
  const lesson=(pack?.lessons?.[String(module)]||[]).find(x=>String(x.id)===String(id));if(!lesson)return null;
  const override=pack?.lesson_overrides?.lessons?.[String(id)]||null,kind=String(override?.kind||lesson.lesson_kind||lesson.lesson_type||'KNOWLEDGE').toUpperCase(),today=new Date().toISOString().slice(0,10);
  const usable=q=>kind!=='DYNAMIC'||(['CURRENT','DYNAMIC','LIVE'].includes(String(q.stability||'').toUpperCase())&&q.source_url&&q.verified_at&&q.review_by&&String(q.review_by)>=today);
  const questions=pack.questions||[],curated=Array.isArray(override?.knowledge_ids)?override.knowledge_ids.map(String):[],ranked=[],seen=new Set();
  if(curated.length){
    for(let i=0;i<curated.length;i++){const q=questions.find(x=>String(x.knowledge_id)===curated[i]&&usable(x));if(q){ranked.push({q,score:100-i});seen.add(curated[i])}}
  }else{
    const anchors=[lesson.title,lesson.chapter,...(lesson.covers||[]),...(lesson.points||[]),...(lesson.objectives||[])].filter(Boolean),tokens=offlineTokens(anchors.join(' ')),phrases=(lesson.covers||[]).map(offlineNorm).filter(x=>x.length>=4);
    for(const q of questions){
      if(seen.has(q.knowledge_id)||!usable(q))continue;
      const correct=(q.choices||[])[Number(q.answer)]||'',text=offlineNorm([q.domain,q.subdomain,q.prompt,q.explanation,correct].join(' '));let score=0;
      for(const p of phrases)if(text.includes(p))score+=12;for(const t of tokens)if(text.includes(t))score+=/^\d+$/.test(t)?5:2;
      const ch=String(lesson.chapter||'').toLowerCase();if(String(q.subdomain||'').toLowerCase()===ch||String(q.domain||'').toLowerCase()===ch)score+=6;if(Number(q.module)===Number(module))score+=3;
      if(score>=9){ranked.push({q,score});seen.add(q.knowledge_id)}
    }
    ranked.sort((a,b)=>b.score-a.score||String(a.q.id).localeCompare(String(b.q.id)))
  }
  const facts=ranked.slice(0,12).map(({q,score})=>({question_id:q.id,knowledge_id:q.knowledge_id,domain:q.domain,subdomain:q.subdomain,prompt:q.prompt,answer:(q.choices||[])[Number(q.answer)]||'',explanation:q.explanation||'',source:q.source||'',source_url:q.source_url||'',verified_at:q.verified_at||'',review_by:q.review_by||'',stability:q.stability||'STABLE',difficulty:Number(q.difficulty||1),alignment_score:score,distractors:(q.choices||[]).filter((_,i)=>i!==Number(q.answer))}));
  const method=kind==='METHOD'||Number(module)===8,status=method?'METHOD_READY':kind==='DYNAMIC'?(facts.length>=5?'DYNAMIC_READY':facts.length>=2?'DYNAMIC_PARTIAL':'DYNAMIC_EMPTY'):(facts.length>=5?'TEACHING_READY':facts.length>=2?'TEACHING_PARTIAL':'TEACHING_SHALLOW');
  return {...lesson,module:Number(module),teaching_facts:facts,sources:[...new Set(facts.map(x=>x.source).filter(Boolean))],teaching_override:override||null,pedagogy:{kind:method?'METHOD':kind==='DYNAMIC'?'DYNAMIC':'KNOWLEDGE',aligned_facts:facts.length,recall_count:(lesson.recall_prompts||[]).length,objectives_count:(lesson.objectives||[]).length,status},_offline:true}
}
function offlineStatus(pack){
  const qs=pack?.questions||[],ku=new Set(qs.map(x=>x.knowledge_id)).size;
  return {service:'Excellentia Study Hub · cache',build:pack?.build||'offline',questions_loaded:qs.length,knowledge_units_loaded:ku,reviews_due:0,best_score:0,answers_saved:0,active_session_id:state.session?.id||null,modules:pack?.modules||[]}
}

function applyTheme(){
  document.body.classList.toggle('dark',state.theme==='dark');
  document.body.classList.toggle('rail-collapsed',state.railCollapsed);
  document.body.classList.toggle('density-compact',state.density==='compact');
  document.body.classList.toggle('text-large',state.textScale==='large');
  document.body.classList.toggle('reduced-motion',state.reducedMotion)
}
function enterImmersive(kind){state.immersive=kind;document.body.classList.add('immersive');document.body.dataset.immersive=kind||'';closeMobile();closeDrawer()}
function exitImmersive(){state.immersive=null;document.body.classList.remove('immersive');delete document.body.dataset.immersive}
function effectiveRole(){return state.me?.role==='ADMIN'&&state.previewStudent?'STUDENT':state.me?.role}
function firstTab(space){return DEFAULT_TAB[space]||'today'}
function validTab(space,tab){return (SPACES[space]?.tabs||[]).some(x=>x[0]===tab)}
function go(space,tab){
  if(!SPACES[space])space='home';
  if(space==='admin'&&effectiveRole()!=='ADMIN'){
    if(state.me?.admin_available){openAdminGate();return}
    space='home';
  }
  exitImmersive();
  state.space=space;state.tab=validTab(space,tab)?tab:firstTab(space);localStorage.setItem('exc2_space',space);localStorage.setItem('exc2_tab',state.tab);
  const nextUrl=new URL(location.href);nextUrl.searchParams.set('space',state.space);nextUrl.searchParams.set('tab',state.tab);history.replaceState({space:state.space,tab:state.tab},'',nextUrl);
  qsa('[data-space]').forEach(b=>b.classList.toggle('active',b.dataset.space===space));closeMobile();
  renderChrome();if(state.offlineMode)return renderOfflineSpace();render()
}
function renderChrome(){
  const m=SPACES[state.space];qs('#pageTitle').textContent=m.title;qs('#breadcrumbs').textContent='Excellentia / '+m.title;
  qs('#contextTabs').innerHTML=m.tabs.map(([k,l])=>'<button data-tab="'+k+'" class="'+(k===state.tab?'active':'')+'">'+esc(l)+'</button>').join('');
  qsa('#contextTabs [data-tab]').forEach(b=>b.onclick=()=>go(state.space,b.dataset.tab));
  qs('#contextActions').innerHTML=contextActions();
  bindContextActions();
}
function contextActions(){
  if(state.previewStudent)return '<span class="pill warn">APERÇU ÉLÈVE</span><button class="btn secondary small" id="exitPreview">Quitter l’aperçu</button>';
  if(state.space==='train')return '<button class="btn small" id="ctxQuick">Nouvelle série</button>';
  if(state.space==='learn')return '<button class="btn secondary small" id="ctxDay">Planifier la journée</button>';
  if(state.space==='review')return '<button class="btn small" id="ctxReview">Réviser maintenant</button>';
  if(state.space==='exam')return '<button class="btn small" id="ctxExam">Lancer un blanc</button>';
  if(state.space==='admin')return '<span class="pill good">ADMIN DÉVERROUILLÉ</span><button class="btn ghost small" id="adminLock">Verrouiller</button>';
  return ''
}
function bindContextActions(){
  qs('#exitPreview')?.addEventListener('click',()=>{state.previewStudent=false;localStorage.removeItem('exc2_preview_student');loadBase(true).then(()=>go('home','today'))});
  qs('#ctxQuick')?.addEventListener('click',()=>startSession({module:0,mode:'mixed',count:20,duration_seconds:900}));
  qs('#ctxDay')?.addEventListener('click',()=>go('home','day'));
  qs('#ctxReview')?.addEventListener('click',()=>startSession({module:0,mode:'review',count:20,duration_seconds:900}));
  qs('#ctxExam')?.addEventListener('click',()=>startSession({module:0,mode:'mock',count:50,duration_seconds:2700}));
  qs('#adminLock')?.addEventListener('click',async()=>{await api('/api/admin/lock',{method:'POST'});state.me=null;await loadBase(true);go('home','today');toast('Administration verrouillée')})
}
function openAdminGate(){
  const html='<div class="admin-gate"><div class="gate-icon">⌁</div><h3>Administration protégée</h3><p>Le mode Élève reste libre. Saisis le code administrateur pour ouvrir les réglages, le corpus, les accès et les mises à jour.</p><label class="eyebrow" for="adminPin">CODE ADMIN</label><input class="field gate-pin" id="adminPin" inputmode="numeric" autocomplete="off" maxlength="12" placeholder="••••"><div class="hero-actions"><button class="btn" id="adminUnlock">Déverrouiller</button><button class="btn ghost" id="adminCancel">Annuler</button></div><p class="gate-error" id="adminGateError"></p></div>';
  openDrawer('ACCÈS PROTÉGÉ','Administration',html);
  const submit=async()=>{const pin=qs('#adminPin')?.value||'';const err=qs('#adminGateError');try{await api('/api/admin/unlock',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({pin})});state.me=null;await loadBase(true);closeDrawer();go('admin','access')}catch(e){if(err)err.textContent=e.message==='ADMIN_PIN_INVALID'?'Code incorrect.':e.message}};
  qs('#adminUnlock')?.addEventListener('click',submit);qs('#adminCancel')?.addEventListener('click',closeDrawer);qs('#adminPin')?.addEventListener('keydown',e=>{if(e.key==='Enter')submit()});setTimeout(()=>qs('#adminPin')?.focus(),30)
}
function closeMobile(){qs('#rail')?.classList.remove('open');qs('#mobileSheet')?.classList.remove('open');qs('#overlay')?.classList.remove('open')}
function openDrawer(eyebrow,title,html){qs('#drawerEyebrow').textContent=eyebrow||'';qs('#drawerTitle').textContent=title||'';qs('#drawerBody').innerHTML=html;qs('#drawerBackdrop').classList.add('open')}
function closeDrawer(){qs('#drawerBackdrop').classList.remove('open')}
function setInspector(html=''){const el=qs('#inspector');el.innerHTML=html;el.classList.toggle('open',Boolean(html))}
function empty(icon,title,body,actions=''){return '<div class="empty-state"><div class="empty-inner"><div class="empty-icon">'+icon+'</div><h3>'+esc(title)+'</h3><p>'+esc(body)+'</p>'+(actions?'<div class="actions">'+actions+'</div>':'')+'</div></div>'}
function progressBar(v,kind=''){return '<div class="progress-track"><div class="progress-fill '+kind+'" style="width:'+Math.max(0,Math.min(100,Number(v||0)))+'%"></div></div>'}
function metric(v,l){return '<div class="metric"><b>'+esc(v)+'</b><span>'+esc(l)+'</span></div>'}
function injectViewGuide(){
  if(state.immersive||state.offlineMode)return;
  const host=qs('#viewHost'),g=VIEW_GUIDES[state.space+':'+state.tab];if(!host||!g||host.querySelector('.view-guide'))return;
  const el=document.createElement('section');el.className='view-guide';
  el.innerHTML='<div><span class="eyebrow">BUT</span><b>'+esc(g[0])+'</b></div><div><span class="eyebrow">CE QUE TU FAIS</span><p>'+esc(g[1])+'</p></div><div><span class="eyebrow">ENSUITE</span><p>'+esc(g[2])+'</p></div>';
  host.prepend(el)
}

function buildVersionLabel(build){
  const m=String(build||'').match(/v(\d+\.\d+\.\d+)(?:-([a-z]+))?/i);
  return m?{version:'V'+m[1],channel:(m[2]||'').toUpperCase()}: {version:'V—',channel:''}
}
async function loadBase(force=false){
  if(!state.me||force)state.me=await api('/api/me');
  state.offlineMode=false;
  if(!state.status||force){state.status=await api('/api/status');state.modules=state.status.modules||[]}
  const bv=buildVersionLabel(state.status?.build);qs('#versionBadge').textContent=bv.version;qs('#versionBadge').title=String(state.status?.build||'');qs('#buildChip').textContent=bv.version+(bv.channel?' · '+bv.channel:'');document.title='Excellentia Study Hub · '+bv.version;
  qs('#roleLabel').textContent=effectiveRole()==='ADMIN'?'Administrateur':(state.previewStudent?'Élève · aperçu':'Élève');
  qsa('.admin-nav').forEach(x=>{x.style.display=state.me?.admin_available||effectiveRole()==='ADMIN'?'':'none';x.classList.toggle('locked',effectiveRole()!=='ADMIN')});
  qs('#reviewNavBadge').textContent=num(state.status.reviews_due||0);
  if(state.me?.device==='PAIRED_LAN')startMobileHeartbeat();else stopMobileHeartbeat();
  return state.status
}
async function loadStats(force=false){if(!state.stats||force)state.stats=await api('/api/stats');return state.stats}
async function loadCoach(force=false){if(!state.coach||force)state.coach=await api('/api/coach');return state.coach}
async function loadPrep(force=false){if(!state.prep||force)state.prep=await api('/api/prep');return state.prep}
async function loadMastery(force=false){if(!state.mastery||force)state.mastery=await api('/api/mastery?limit=5000');return state.mastery}
async function loadNotebook(force=false){if(!state.notebook||force)state.notebook=await api('/api/error-notebook?limit=300');return state.notebook}


async function render(){
  setInspector('');const host=qs('#viewHost');host.innerHTML='<div class="empty-state"><div class="empty-inner"><div class="empty-icon">◌</div><h3>Chargement</h3></div></div>';
  try{
    await loadBase();if(effectiveRole()!=='ADMIN'&&state.space==='admin')return go('home');
    if(state.space==='home')await renderHome();
    if(state.space==='learn')await renderLearn();
    if(state.space==='train')await renderTrain();
    if(state.space==='review')await renderReview();
    if(state.space==='exam')await renderExam();
    if(state.space==='progress')await renderProgress();
    if(state.space==='admin')await renderAdmin();
    injectViewGuide()
  }catch(e){host.innerHTML=empty('!','Vue indisponible',e.message,'<button class="btn" id="retry">Réessayer</button>');qs('#retry')?.addEventListener('click',render)}
}

async function renderHome(){
  if(state.tab==='day')return renderDay();
  if(state.tab==='mission')return renderMission();
  const [st,coach,day]=await Promise.all([loadStats(),loadCoach(),api('/api/day/current').then(x=>x.day)]);
  const status=state.status,recent=(st.recent||[])[0],c=coach.components||{};
  qs('#viewHost').innerHTML=
    '<section class="hero coach-hero"><div><div class="eyebrow">EXCELLENTIA STUDY HUB · '+esc(buildVersionLabel(status.build).version)+'</div><h2>Ne choisis plus au hasard quoi réviser.</h2><p>Le cockpit combine apprentissage, mémoire, erreurs, vitesse et couverture pour proposer la prochaine action utile.</p><div class="hero-actions">'+
      (status.active_session_id?'<button class="btn good" id="homeResumeSession">Reprendre la session</button>':'<button class="btn good" id="homeMission">Voir ma mission</button>')+
      '<button class="btn secondary" id="homeSprint">Sprint 10 min</button></div></div>'+
      '<div class="readiness-ring" style="--score:'+Number(coach.training_index||0)+'"><div><b>'+num(coach.training_index||0)+'</b><span>indice entraînement</span><small>'+esc(coach.label||'DÉMARRAGE')+'</small></div></div></section>'+
    '<div class="metric-grid">'+metric(num(status.questions_loaded),'questions culture')+metric(num(status.knowledge_units_loaded),'notions culture')+metric(num(status.reviews_due),'révisions dues')+metric(num(coach.streak_days||0)+' j','série active')+metric(pct(c.coverage||0),'couverture mesurée')+'</div>'+
    '<section class="section"><div class="section-head"><div><h2>Mission prioritaire</h2><p>Calculée depuis les sessions fiables, jamais depuis une session incomplète.</p></div><button class="btn ghost small" id="openMission">Tout le plan</button></div><div class="mission-strip">'+
      (coach.mission||[]).slice(0,3).map((m,i)=>'<button class="mission-card '+(i===0?'primary':'')+'" data-home-mission="'+i+'"><span class="mission-rank">'+(i+1)+'</span><div><b>'+esc(m.title)+'</b><p>'+esc(m.reason)+'</p></div><em>'+(m.minutes?m.minutes+' min':'→')+'</em></button>').join('')+
    '</div></section>'+
    '<section class="section"><div class="section-head"><div><h2>Les 4 matières</h2><p>Culture générale est déjà mesurée. Mathématiques, Français et Anglais ont désormais leur carte de compétences, sans faux score tant que leurs banques ne sont pas auditées.</p></div><button class="btn ghost small" id="openCurriculum">Voir le blueprint</button></div><div class="subject-mini-grid">'+
      (coach.subjects||[]).map(x=>'<div class="subject-mini"><span>'+esc(x.icon||'•')+'</span><div><b>'+esc(x.title)+'</b><small>'+(x.status==='ENGINE_READY'?'mesurée':'programme prêt · non mesuré')+'</small></div></div>').join('')+
    '</div></section>'+
    '<section class="section"><div class="grid two"><div class="card"><div class="section-head"><div><h2>Dernier résultat fiable</h2><p>Les sessions techniquement incomplètes restent exclues.</p></div></div>'+
      (recent?'<div class="card-row"><div><b>'+pct(recent.score)+'</b><p>'+esc(recent.mode)+' · '+recent.total+' questions</p></div><span class="pill">'+date(recent.finished_at)+'</span></div>':'<p>Aucun résultat fiable enregistré.</p>')+
    '</div><div class="card"><div class="section-head"><div><h2>État du jour</h2><p>Le travail peut être fermé puis repris.</p></div></div>'+
      (day?'<div class="card-row"><div><b>Journée '+day.duration_hours+' h</b><p>Étape '+(Number(day.current_index)+1)+' / '+day.blocks.length+'</p></div><button class="btn small" id="resumeDay">Reprendre</button></div>':'<div class="card-row"><div><b>Aucune journée active</b><p>Créer un parcours guidé 55–10–55.</p></div><button class="btn secondary small" id="createDay">Créer</button></div>')+
    '</div></div></section>';
  qs('#homeResumeSession')?.addEventListener('click',async()=>{if(await restoreActiveSession())return;state.status=null;renderHome()});
  qs('#homeMission')?.addEventListener('click',()=>go('home','mission'));qs('#openMission').onclick=()=>go('home','mission');qs('#homeSprint').onclick=()=>go('train','sprint');qs('#openCurriculum').onclick=()=>go('learn','curriculum');
  qs('#resumeDay')?.addEventListener('click',()=>go('home','day'));qs('#createDay')?.addEventListener('click',()=>go('home','day'));
  qsa('[data-home-mission]').forEach(b=>b.onclick=()=>runMission((coach.mission||[])[Number(b.dataset.homeMission)]))
}
function actionCard(icon,title,body,label,space,tab){return '<div class="card"><div class="mode-icon">'+icon+'</div><h3>'+esc(title)+'</h3><p>'+esc(body)+'</p><div style="margin-top:13px"><button class="btn secondary small" data-go="'+space+'" data-tab="'+tab+'">'+esc(label)+'</button></div></div>'}
function bindSpaceLinks(){qsa('[data-go]').forEach(b=>b.onclick=()=>go(b.dataset.go,b.dataset.tab))}
function moduleCard(m){
  const count=Number(m.question_count||0),share=Math.min(100,Math.round(count/Math.max(1,state.status.questions_loaded)*100*4));
  const countLabel=m.status==='dynamic'?'Veille datée':m.status==='mix'?'Tous domaines':num(count)+' Q';
  return '<article class="module-card"><div class="module-icon">'+m.id+'</div><div class="module-copy"><h3>'+esc(m.short||m.title)+'</h3><p>'+esc(m.description||'')+'</p><div class="mini-progress"><i style="width:'+(m.status==='mix'?100:share)+'%"></i></div></div><div class="module-meta"><b>'+esc(countLabel)+'</b><button class="btn ghost small" data-module="'+m.id+'">Ouvrir</button></div></article>'
}
function bindModuleCards(){qsa('[data-module]').forEach(b=>b.onclick=()=>openModule(Number(b.dataset.module)))}
async function openModule(id){
  const m=state.modules.find(x=>Number(x.id)===id),l=await api('/api/lessons?module='+id);
  const html='<div class="metric-grid" style="grid-template-columns:repeat(3,1fr);margin-top:0">'+metric(num(m?.question_count||0),'questions')+metric(num((l.items||[]).length),'fiches')+metric(esc(m?.status||'prêt'),'état')+'</div>'+
    '<section class="section"><div class="section-head"><div><h2>Fiches du module</h2><p>Lire, rappeler sans support, puis s’entraîner.</p></div></div><div class="grid">'+
    ((l.items||[]).map(x=>'<button class="card flat" data-lesson="'+esc(x.id)+'" data-module-lesson="'+id+'" style="text-align:left"><h3>'+esc(x.title)+'</h3><p>'+esc(x.summary||'')+' · '+num(x.minutes)+' min</p></button>').join('')||empty('◫','Aucune fiche','Le module reste disponible dans les exercices.'))+
    '</div></section><div class="hero-actions">'+(m?.status==='dynamic'&&Number(m?.question_count||0)===0?'':('<button class="btn" id="drawerTrain">'+(m?.status==='mix'?'Lancer le Grand Mix':'S’entraîner sur ce module')+'</button>'))+'<button class="btn secondary" id="drawerDay">Ajouter à la journée</button></div>';
  openDrawer('MODULE '+id,m?.short||m?.title||'Module',html);
  if(qs('#drawerTrain'))qs('#drawerTrain').onclick=()=>{closeDrawer();startSession({module:m?.status==='mix'?0:id,mode:m?.status==='mix'?'mixed':'module',count:30,duration_seconds:1800})};
  qs('#drawerDay').onclick=()=>{closeDrawer();go('home','day')};
  qsa('[data-module-lesson]').forEach(b=>b.onclick=()=>openLesson(id,b.dataset.lesson))
}
async function openLesson(module,id,returnTarget=null){
  const back=returnTarget||{type:'nav',space:state.space,tab:state.tab};let x;
  try{x=await api('/api/lesson/workspace?module='+encodeURIComponent(module)+'&id='+encodeURIComponent(id))}
  catch(e){
    if(e.status)throw e;
    const pack=await getOfflinePack();x=offlineLessonWorkspace(pack,module,id);
    if(!x)throw e;setNetwork(false);toast('Leçon hors ligne','Contenu chargé depuis le cache local.','lesson-offline')
  }
  state.lesson={...x,_return:back,_step:'understand'};
  enterImmersive('lesson');renderLessonWorkspace()
}
function lessonSteps(){return [['understand','1','Comprendre'],['course','2','Cours guidé'],['memory','3','Mémoriser'],['recall','4','Rappel actif'],['test','5','Vérifier'],['sources','6','Sources']]}
function lessonPanel(x,step){
  const facts=x.teaching_facts||[],objectives=x.objectives||[],points=x.points||[],covers=x.covers||[],checks=x.mastery_checklist||[],recall=x.recall_prompts||[],method=x.pedagogy?.kind==='METHOD';
  if(step==='understand')return '<section class="teaching-section"><div class="eyebrow">ÉTAPE 1 · COMPRENDRE</div><h2>Ce que tu dois réellement comprendre</h2><p class="teaching-lead">'+esc(x.summary||'')+'</p><div class="teaching-objectives">'+objectives.map((o,i)=>'<div class="teaching-objective"><span>'+(i+1)+'</span><p>'+esc(o)+'</p></div>').join('')+'</div><div class="lesson-note"><b>Méthode</b><p>Ne mémorise pas encore mot à mot. Cherche d’abord les liens : date → événement → acteur → conséquence → confusion possible.</p></div></section>';
  if(step==='course')return method?'<section class="teaching-section"><div class="eyebrow">ÉTAPE 2 · MÉTHODE GUIDÉE</div><h2>Transformer la méthode en gestes concrets</h2><p class="teaching-lead">Ici, il n’y a pas de liste de faits à apprendre : le but est d’acquérir une procédure que tu peux reproduire sous pression.</p><div class="teaching-core">'+points.map((p,i)=>'<div class="core-point"><span>'+String(i+1).padStart(2,'0')+'</span><p>'+esc(p)+'</p></div>').join('')+'</div><div class="lesson-note"><b>Règle d’utilisation</b><p>Applique chaque étape immédiatement sur une vraie question. Une méthode n’est maîtrisée que si elle améliore la précision ou la vitesse en situation.</p></div></section>':'<section class="teaching-section"><div class="eyebrow">ÉTAPE 2 · COURS GUIDÉ</div><h2>Construire le thème, pas réciter un résumé</h2><div class="teaching-core">'+points.map((p,i)=>'<div class="core-point"><span>'+String(i+1).padStart(2,'0')+'</span><p>'+esc(p)+'</p></div>').join('')+'</div><div class="section-head teaching-subhead"><div><h3>Faits strictement alignés</h3><p>Le moteur rassemble les repères réellement liés au thème, y compris s’ils proviennent d’un autre module du corpus.</p></div><span class="pill '+(x.pedagogy?.status==='TEACHING_READY'?'good':'warn')+'">'+num(facts.length)+' faits alignés</span></div><div class="fact-stack">'+(facts.length?facts.map((f,i)=>'<article class="fact-card"><div class="fact-meta"><span class="eyebrow">'+esc(f.domain||'NOTION')+' · '+esc(f.subdomain||'')+'</span><span class="pill">'+esc(f.stability||'STABLE')+'</span></div><h3>'+esc(f.prompt)+'</h3><div class="fact-answer"><b>'+esc(f.answer)+'</b><p>'+esc(f.explanation||'')+'</p></div></article>').join(''):'<div class="lesson-note warn"><b>Leçon à approfondir</b><p>Pas assez de faits strictement alignés. Cette leçon reste visible mais n’est pas considérée profonde tant que le corpus associé n’est pas enrichi.</p></div>')+'</div></section>';
  if(step==='memory')return '<section class="teaching-section"><div class="eyebrow">ÉTAPE 3 · MÉMORISER</div><h2>Repères à restituer sans support</h2><p class="teaching-lead">Clique sur les repères pour les masquer, puis essaie de les reconstruire de mémoire.</p><div class="memory-board">'+covers.map((p,i)=>'<button class="memory-chip" data-memory="'+i+'">'+esc(p)+'</button>').join('')+'</div><h3 class="teaching-h3">Critères de maîtrise</h3><div class="checklist">'+checks.map((p,i)=>'<label><input type="checkbox" data-master="'+i+'"><span>'+esc(p)+'</span></label>').join('')+'</div></section>';
  if(step==='recall')return '<section class="teaching-section"><div class="eyebrow">ÉTAPE 4 · RAPPEL ACTIF</div><h2>Produire la réponse avant de la voir</h2><p class="teaching-lead">Réponds oralement ou sur papier. Révèle seulement après avoir tenté.</p><div class="recall-stack">'+recall.map((p,i)=>{const f=facts[i%Math.max(1,facts.length)];return '<div class="recall-item"><div class="recall-num">'+(i+1)+'</div><div><p>'+esc(p)+'</p><button class="btn secondary small" data-recall-reveal="'+i+'">Révéler un repère</button><div class="recall-help" id="recallHelp'+i+'" hidden>'+(f?'<b>'+esc(f.answer)+'</b><p>'+esc(f.explanation||'')+'</p>':'<p>Restitue les points du cours sans rouvrir l’étape précédente.</p>')+'</div></div></div>'}).join('')+'</div></section>';
  if(step==='test')return method?'<section class="teaching-section"><div class="eyebrow">ÉTAPE 5 · MISE EN PRATIQUE</div><h2>Tester la méthode sur de vraies questions</h2><p class="teaching-lead">Une courte série mixte sert de terrain d’application : utilise volontairement la technique de cette leçon et observe précision, vitesse et hésitations.</p><div class="lesson-test-card"><div><b>10 questions mixtes</b><span>Application pratique de la méthode</span></div><button class="btn good" id="lessonPractice">Lancer la mise en pratique</button></div></section>':'<section class="teaching-section"><div class="eyebrow">ÉTAPE 5 · VÉRIFIER</div><h2>Mini-évaluation ciblée sur cette leçon</h2><p class="teaching-lead">Le test utilise uniquement les unités de connaissance alignées, puis réinjecte les erreurs dans les révisions.</p><div class="lesson-test-card"><div><b>'+Math.max(5,Math.min(15,facts.length||10))+' questions</b><span>'+num(facts.length)+' notions/faits alignés disponibles</span></div><button class="btn good" id="lessonPractice">Lancer le mini-test</button></div><div class="lesson-note"><b>Après le test</b><p>Ne relis pas toute la leçon. Reviens uniquement sur les erreurs, les réponses lentes et les confusions.</p></div></section>';
  return method?'<section class="teaching-section"><div class="eyebrow">ÉTAPE 6 · BILAN MÉTHODE</div><h2>Quand considérer cette méthode acquise ?</h2><div class="checklist">'+checks.map((p,i)=>'<label><input type="checkbox"><span>'+esc(p)+'</span></label>').join('')+'</div><div class="lesson-note"><b>Statut pédagogique</b><p>Méthode guidée · '+num(x.pedagogy?.recall_count||0)+' exercices de rappel.</p></div></section>':'<section class="teaching-section"><div class="eyebrow">ÉTAPE 6 · SOURCES & TRAÇABILITÉ</div><h2>D’où viennent les faits utilisés</h2><div class="source-stack">'+((x.sources||[]).length?(x.sources||[]).map((s,i)=>'<div class="source-row"><span>'+(i+1)+'</span><p>'+esc(s)+'</p></div>').join(''):'<p class="teaching-lead">Aucune source distincte n’a été extraite pour cette leçon.</p>')+'</div><div class="lesson-note"><b>Statut pédagogique</b><p>'+esc(x.pedagogy?.status||'—')+' · '+num(x.pedagogy?.aligned_facts||0)+' faits alignés · '+num(x.pedagogy?.recall_count||0)+' rappels actifs.</p></div></section>'
}
function renderLessonWorkspace(){
  const x=state.lesson;if(!x)return;enterImmersive('lesson');const step=x._step||'understand',steps=lessonSteps(),m=state.modules.find(v=>Number(v.id)===Number(x.module));
  const method=x.pedagogy?.kind==='METHOD',ready=['TEACHING_READY','METHOD_READY','DYNAMIC_READY'].includes(x.pedagogy?.status),offline=Boolean(x._offline);
  const fromDay=x._return?.type==='day';
  const dayLabel=fromDay&&state.day?'<span class="pill good">Journée '+state.day.duration_hours+' h</span><small>Bloc '+(Number(x._return.block_index??state.day.current_index)+1)+' / '+state.day.blocks.length+'</small>':'<small>Leçon autonome</small>';
  const completeDay=fromDay&&step==='sources'?'<div class="lesson-complete-bar"><div><b>Leçon parcourue</b><span>Valide le bloc seulement si tu as réellement terminé le cours et le rappel.</span></div><button class="btn good" id="lessonCompleteDay">Valider ce bloc et revenir à la journée</button></div>':'';
  qs('#viewHost').innerHTML='<div class="focus-workspace lesson-workspace"><header class="focus-topbar"><button class="btn ghost small" id="lessonBack">← Retour</button><div class="focus-title"><span class="eyebrow">APPRENDRE · '+esc(m?.short||('MODULE '+x.module))+'</span><b>'+esc(x.title)+'</b></div><div class="focus-meta"><span class="pill">'+num(x.minutes)+' min</span>'+(offline?'<span class="pill warn">OFFLINE</span>':'')+'<span class="pill '+(ready?'good':'warn')+'">'+esc(method?'Coaching méthodologique':ready?'Leçon qualifiée':'À approfondir')+'</span></div></header><div class="lesson-focus-grid"><aside class="lesson-focus-nav"><div class="eyebrow">PARCOURS DE LA LEÇON</div>'+steps.map(([k,n,l])=>'<button data-lesson-step="'+k+'" class="'+(step===k?'active':'')+'"><span>'+n+'</span><b>'+esc(l)+'</b></button>').join('')+'<div class="lesson-day-context">'+dayLabel+'</div></aside><main class="lesson-workspace-main">'+lessonPanel(x,step)+completeDay+'</main><aside class="lesson-focus-side"><div class="eyebrow">OBJECTIFS</div>'+(x.objectives||[]).map(o=>'<p>✓ '+esc(o)+'</p>').join('')+'<div class="focus-side-actions"><button class="btn secondary small" id="lessonCards">Micro-fiches liées</button><button class="btn ghost small" id="lessonExit">Quitter la leçon</button></div></aside></div></div>';
  qsa('[data-lesson-step]').forEach(b=>b.onclick=()=>{x._step=b.dataset.lessonStep;renderLessonWorkspace()});
  qsa('[data-memory]').forEach(b=>b.onclick=()=>b.classList.toggle('hidden-memory'));
  qsa('[data-recall-reveal]').forEach(b=>b.onclick=()=>{const h=qs('#recallHelp'+b.dataset.recallReveal);if(h)h.hidden=!h.hidden});
  qs('#lessonBack').onclick=closeLessonWorkspace;qs('#lessonExit').onclick=closeLessonWorkspace;
  qs('#lessonCards')?.addEventListener('click',()=>{if(offline)return toast('Mode hors ligne','La bibliothèque complète se resynchronise dès que le serveur revient.','offline-library');if(method){state.sessionReturn={type:'lesson',module:x.module,id:x.id,step:'test',return_target:x._return};return startSession({module:0,mode:'mixed',count:10,duration_seconds:600})}exitImmersive();state.cardMode='micro';state.cardModule=Number(x.module);state.lesson=null;go('learn','cards')});
  qs('#lessonPractice')?.addEventListener('click',()=>{if(offline)return toast('Mini-test en attente','Reconnecte le serveur pour créer une session fiable et synchronisée.','offline-test');state.sessionReturn={type:'lesson',module:x.module,id:x.id,step:'test',return_target:x._return};if(method)return startSession({module:0,mode:'mixed',count:10,duration_seconds:600});const ids=(x.teaching_facts||[]).map(f=>f.knowledge_id);startSession({module:Number(x.module),mode:'lesson',knowledge_ids:ids,count:Math.max(5,Math.min(15,ids.length||10)),duration_seconds:900})});
  qs('#lessonCompleteDay')?.addEventListener('click',async()=>{const idx=Number(x._return?.block_index??state.day?.current_index??0);state.lesson=null;exitImmersive();await updateDay('complete_block',idx)})
}
function closeLessonWorkspace(){
  const x=state.lesson,r=x?._return;state.lesson=null;exitImmersive();
  if(r?.type==='day')return go('home','day');
  return go(r?.space||'learn',r?.tab||'modules')
}
function openMicrocard(x){
  const html='<div class="lesson-reader" style="border:0;padding:0"><div class="eyebrow">MICRO-FICHE · '+esc(x.domain||'')+' · '+esc(x.subdomain||'')+'</div>'+
    '<h2>'+esc(x.front||'Notion')+'</h2>'+
    '<div class="card flat" style="margin-top:12px"><div class="eyebrow">RÉPONSE</div><h3 style="font-size:20px;margin-top:6px">'+esc(x.answer||'')+'</h3><p>'+esc(x.explanation||'')+'</p></div>'+
    '<div class="stat-line"><span>Variantes de questions</span><b>'+num(x.variants||1)+'</b></div>'+
    '<div class="stat-line"><span>Stabilité</span><b>'+esc(x.stability||'STABLE')+'</b></div>'+
    '<div class="stat-line"><span>Source</span><b>'+esc(x.source||'—')+'</b></div>'+
    '<div class="hero-actions"><button class="btn" id="microPractice">Questions du module</button></div></div>';
  openDrawer('MICRO-FICHE',x.front||'Notion',html);
  qs('#microPractice').onclick=()=>{closeDrawer();startSession({module:Number(x.module||0),mode:'module',count:10,duration_seconds:600})}
}

function masteryTone(stage){return stage==='MASTERED'?'good':stage==='CONSOLIDATING'?'accent':stage==='LEARNING'?'warn':stage==='FRAGILE'?'bad':'muted'}
function masteryLabel(stage){return ({NEW:'Nouvelle',FRAGILE:'Fragile',LEARNING:'En apprentissage',CONSOLIDATING:'À consolider',MASTERED:'Maîtrisée'})[stage]||stage}
async function runMission(m){
  if(!m)return;
  if(m.kind==='RESUME'){if(await restoreActiveSession())return;state.status=null;return go('home','today')}
  if(m.kind==='LEARN'&&m.module)return openModule(Number(m.module));
  return go(m.space||'home',m.tab||'today')
}
async function renderMission(){
  const c=await loadCoach(true),x=c.components||{};
  const components=[['Précision',x.accuracy],['Couverture',x.coverage],['Rétention',x.retention],['Vitesse',x.speed],['Régularité',x.consistency]];
  qs('#viewHost').innerHTML=
    '<section class="hero mission-hero"><div><div class="eyebrow">COACH · MISSION DU JOUR</div><h2>'+esc(c.label||'DÉMARRAGE')+'</h2><p>'+esc(c.disclaimer||'')+'</p></div><div class="readiness-ring large" style="--score:'+num(c.training_index||0)+'"><div><b>'+num(c.training_index||0)+'</b><span>/ 100</span><small>indice interne</small></div></div></section>'+
    '<section class="section"><div class="grid two"><div class="card"><div class="section-head"><div><h2>Pourquoi cette mission ?</h2><p>Le moteur décompose le niveau au lieu de résumer tout par un score.</p></div></div><div class="coach-components">'+components.map(([n,v])=>'<div class="coach-component"><div><span>'+n+'</span><b>'+num(v||0)+' %</b></div>'+progressBar(v||0,(v||0)>=75?'good':(v||0)<45?'warn':'')+'</div>').join('')+'</div></div>'+
    '<div class="card"><div class="section-head"><div><h2>Diagnostic express</h2><p>Lecture immédiate des signaux utiles.</p></div></div>'+
      '<div class="stat-line"><span>Révisions dues</span><b>'+num(c.reviews_due||0)+'</b></div>'+
      '<div class="stat-line"><span>Notions jamais vues</span><b>'+num(c.mastery?.unseen||0)+'</b></div>'+
      '<div class="stat-line"><span>Carnet d’erreurs</span><b>'+num(c.error_notebook_count||0)+' notion(s)</b></div>'+
      '<div class="stat-line"><span>Série d’étude</span><b>'+num(c.streak_days||0)+' jour(s)</b></div>'+
      '<div class="stat-line"><span>Domaine le plus fragile</span><b>'+esc(c.weak_domain?.domain||'pas encore mesurable')+'</b></div>'+
    '</div></div></section>'+
    '<section class="section"><div class="section-head"><div><h2>Ordre d’exécution</h2><p>Commence par 1. Le reste est déjà préparé si tu as encore du temps.</p></div></div><div class="mission-list">'+
      (c.mission||[]).map((m,i)=>'<button class="mission-card '+(i===0?'primary':'')+'" data-mission="'+i+'"><span class="mission-rank">'+(i+1)+'</span><div><b>'+esc(m.title)+'</b><p>'+esc(m.reason)+'</p></div><em>'+(m.minutes?m.minutes+' min':'ouvrir')+'</em></button>').join('')+
    '</div></section>';
  qsa('[data-mission]').forEach(b=>b.onclick=()=>runMission((c.mission||[])[Number(b.dataset.mission)]))
}
async function renderCurriculum(){
  const p=await loadPrep(),c=await loadCoach(),subjects=p.subjects||[];
  qs('#viewHost').innerHTML=
    '<section class="hero"><div class="eyebrow">BLUEPRINT EXCELLENTIA</div><h2>Quatre matières, une préparation cohérente.</h2><p>Le système distingue ce qui est officiellement annoncé de notre structuration pédagogique interne. Aucun score n’est inventé pour une matière non encore instrumentée.</p></section>'+
    '<div class="subject-grid">'+subjects.map(x=>'<article class="card subject-card '+(x.status==='ENGINE_READY'?'ready':'framework')+'"><header><span class="subject-icon">'+esc(x.icon||'•')+'</span><div><div class="eyebrow">'+(x.status==='ENGINE_READY'?'MOTEUR ACTIF':'PROGRAMME STRUCTURÉ')+'</div><h2>'+esc(x.title)+'</h2></div><span class="pill '+(x.status==='ENGINE_READY'?'good':'warn')+'">'+(x.status==='ENGINE_READY'?'MESURÉ':'NON MESURÉ')+'</span></header><p>'+esc(x.description||'')+'</p><details '+(x.status==='ENGINE_READY'?'open':'')+'><summary>Compétences couvertes</summary><div class="skill-chips">'+(x.skills||[]).map(k=>'<span class="skill-chip">'+esc(k)+'</span>').join('')+'</div></details>'+(x.status==='ENGINE_READY'?'<button class="btn small" data-subject-culture>Ouvrir Culture générale</button>':'<div class="subject-roadmap"><b>Étape suivante</b><span>Construire une banque auditable avant d’activer une note de maîtrise.</span></div>')+'</article>').join('')+'</div>'+
    '<section class="section"><div class="card transversal-card"><div class="card-row"><div><div class="eyebrow">TRANSVERSAL</div><h2>'+esc(p.transversal?.title||'Raisonnement analytique')+'</h2></div><span class="pill">sans faux barème officiel</span></div><p>'+esc(p.transversal?.description||'')+'</p><div class="skill-chips">'+(p.transversal?.skills||[]).map(k=>'<span class="skill-chip">'+esc(k)+'</span>').join('')+'</div></div></section>'+
    '<section class="section"><div class="card source-card"><b>Référence</b><p>Les quatre matières viennent de la communication officielle Excellentia. Les sous-compétences et l’indice d’entraînement sont des outils pédagogiques internes.</p></div></section>';
  qs('[data-subject-culture]')?.addEventListener('click',()=>go('learn','modules'))
}
async function renderSprint(){
  const c=await loadCoach();
  const plans=[{m:5,q:7,label:'Éclair',desc:'Réactivation pure'},{m:10,q:15,label:'Sprint',desc:'Vitesse + rappel'},{m:15,q:22,label:'Standard',desc:'Bloc complet court'},{m:25,q:37,label:'Profond',desc:'Couverture plus large'}];
  qs('#viewHost').innerHTML=
    '<section class="hero"><div class="eyebrow">SMART SPRINT · 40 S / QUESTION</div><h2>Combien de minutes as-tu ?</h2><p>Chaque question a exactement 40 secondes. Le nombre de questions est calibré sur le temps choisi ; à 0 s, absence de réponse = erreur et passage automatique.</p></section>'+
    '<section class="section"><div class="sprint-grid">'+plans.map(x=>'<button class="sprint-card" data-sprint="'+x.m+'"><span>'+x.m+'</span><b>minutes</b><h3>'+x.label+'</h3><p>'+x.desc+' · '+x.q+' questions max</p></button>').join('')+'</div></section>'+
    '<section class="section"><div class="grid two"><div class="card"><h3>Priorité actuelle</h3><p>'+(c.reviews_due?num(c.reviews_due)+' rappels sont dus. Fais-les avant un sprint si tu as au moins 15 minutes.':'Pas de dette urgente : le sprint peut servir à étendre la couverture.')+'</p></div><div class="card"><h3>Règle du sprint</h3><p>40 secondes par question. Pas de support ; une réponse validée verrouille la question. Sans réponse à 0 s : erreur automatique, puis question suivante.</p></div></div></section>';
  qsa('[data-sprint]').forEach(b=>{b.onclick=()=>{const m=Number(b.dataset.sprint),p=plans.find(x=>x.m===m);startSession({module:0,mode:'mixed',count:p.q,duration_seconds:m*60})}})
}
async function renderNotebook(){
  const j=await loadNotebook(true),arr=j.items||[];
  qs('#viewHost').innerHTML=
    '<section class="hero"><div class="eyebrow">CARNET D’ERREURS INTELLIGENT</div><h2>'+(arr.length?num(arr.length)+' notions à surveiller.':'Aucune confusion fiable enregistrée.')+'</h2><p>Les erreurs sont regroupées par connaissance : cinq formulations ratées d’une même notion ne comptent plus comme cinq problèmes différents.</p></section>'+
    (arr.length?'<div class="notebook-grid">'+arr.map((x,i)=>'<article class="card notebook-card '+(x.action==='RELEARN'?'critical':'')+'"><div class="card-row"><div><span class="pill '+(x.action==='RELEARN'?'bad':x.action==='REVIEW'?'warn':'')+'">'+esc(x.action==='RELEARN'?'RÉAPPRENDRE':x.action==='REVIEW'?'RÉVISER':'DRILL')+'</span><span class="eyebrow">'+esc(x.domain)+'</span></div><b>'+num(x.accuracy)+' %</b></div><h3>'+esc(x.subdomain||x.knowledge_id)+'</h3><p>'+esc(x.sample?.prompt||'')+'</p><div class="notebook-answer"><span>Correction de référence</span><b>'+esc(x.sample?.answer||'—')+'</b><small>'+esc(x.sample?.explanation||'')+'</small></div><div class="stat-line"><span>Erreurs fiables</span><b>'+num(x.misses)+'</b></div><div class="stat-line"><span>Tentatives</span><b>'+num(x.attempts)+'</b></div><div class="hero-actions">'+(x.lesson?'<button class="btn small" data-notebook-lesson="'+i+'">Revoir le cours</button>':'')+'<button class="btn secondary small" data-notebook-drill="'+i+'">Drill ciblé</button></div></article>').join('')+'</div>':empty('✓','Carnet vide','Les erreurs des sessions complètes apparaîtront automatiquement ici.','<button class="btn" id="notebookStart">Lancer un sprint</button>'));
  qsa('[data-notebook-lesson]').forEach(b=>{b.onclick=()=>{const x=arr[Number(b.dataset.notebookLesson)];openLesson(Number(x.lesson.module||x.module),x.lesson.lesson_id)}});
  qsa('[data-notebook-drill]').forEach(b=>{b.onclick=()=>{const x=arr[Number(b.dataset.notebookDrill)];startSession({module:Number(x.module||0),mode:'lesson',knowledge_ids:[x.knowledge_id],count:5,duration_seconds:300})}});
  qs('#notebookStart')?.addEventListener('click',()=>go('train','sprint'))
}
async function renderMastery(){
  const data=await loadMastery(true),items=data.items||[],summary=data.summary||{},b=summary.buckets||{};
  qs('#viewHost').innerHTML=
    '<section class="hero"><div class="eyebrow">RADAR DE MAÎTRISE</div><h2>'+num(summary.seen||0)+' notions rencontrées sur '+num(summary.total||0)+'.</h2><p>Une notion n’est jamais déclarée maîtrisée après une seule bonne réponse : le score est plafonné tant que l’exposition reste faible.</p></section>'+
    '<div class="mastery-buckets">'+[['NEW','Nouvelles'],['FRAGILE','Fragiles'],['LEARNING','Apprentissage'],['CONSOLIDATING','Consolidation'],['MASTERED','Maîtrisées']].map(([k,l])=>'<button data-stage="'+k+'" class="mastery-bucket '+masteryTone(k)+'"><b>'+num(b[k]||0)+'</b><span>'+l+'</span></button>').join('')+'</div>'+
    '<div class="card mastery-toolbar"><input class="field" id="masterySearch" placeholder="Rechercher domaine, notion…"><select class="field" id="masteryStage"><option value="">Tous les états</option><option value="FRAGILE">Fragiles</option><option value="LEARNING">En apprentissage</option><option value="CONSOLIDATING">À consolider</option><option value="MASTERED">Maîtrisées</option><option value="NEW">Nouvelles</option></select><span class="pill">'+num(summary.coverage_pct||0)+' % couverture</span></div><div id="masteryList"></div>';
  const draw=()=>{
    const q=(qs('#masterySearch').value||'').trim().toLowerCase(),stage=qs('#masteryStage').value;
    const rows=items.filter(x=>(!stage||x.stage===stage)&&(!q||(x.domain+' '+x.subdomain+' '+x.knowledge_id).toLowerCase().includes(q))).slice(0,150);
    qs('#masteryList').innerHTML=rows.length?'<div class="mastery-list">'+rows.map(x=>'<article class="mastery-row"><div class="mastery-score '+masteryTone(x.stage)+'"><b>'+num(x.mastery)+'</b><span>/100</span></div><div class="mastery-main"><div class="card-row"><div><span class="eyebrow">'+esc(x.domain)+' · M'+x.module+'</span><h3>'+esc(x.subdomain||x.knowledge_id)+'</h3></div><span class="pill '+masteryTone(x.stage)+'">'+masteryLabel(x.stage)+'</span></div>'+progressBar(x.mastery,masteryTone(x.stage))+'<div class="mastery-meta"><span>'+num(x.attempts)+' tentative(s)</span><span>'+num(x.accuracy)+' % précision</span><span>'+(x.avg_ms?Math.round(x.avg_ms/1000)+' s':'—')+'</span><span>'+(x.due?'révision due':'mémoire à jour')+'</span></div></div></article>').join('')+'</div>':empty('⌁','Aucune notion correspondante','Change le filtre ou la recherche.');
  };
  draw();qs('#masterySearch').oninput=draw;qs('#masteryStage').onchange=draw;qsa('[data-stage]').forEach(x=>x.onclick=()=>{qs('#masteryStage').value=x.dataset.stage;draw()})
}
async function renderReadiness(){
  const c=await loadCoach(true),p=await loadPrep(),x=c.components||{};
  const comps=[['Précision','Qualité des réponses fiables',x.accuracy],['Couverture','Part des notions déjà rencontrées',x.coverage],['Rétention','Dette de répétition espacée',x.retention],['Vitesse','Temps de réponse observé',x.speed],['Régularité','Sessions fiables sur 7 jours',x.consistency]];
  qs('#viewHost').innerHTML=
    '<section class="hero readiness-hero"><div><div class="eyebrow">INDICE DE PRÉPARATION INTERNE</div><h2>'+esc(c.label||'DÉMARRAGE')+'</h2><p>'+esc(c.disclaimer||'')+'</p></div><div class="readiness-ring large" style="--score:'+num(c.training_index||0)+'"><div><b>'+num(c.training_index||0)+'</b><span>/100</span><small>entraînement</small></div></div></section>'+
    '<section class="section"><div class="readiness-components">'+comps.map(([n,d,v])=>'<article class="card readiness-component"><div class="card-row"><div><h3>'+n+'</h3><p>'+d+'</p></div><b>'+num(v||0)+' %</b></div>'+progressBar(v||0,(v||0)>=75?'good':(v||0)<45?'warn':'')+'</article>').join('')+'</div></section>'+
    '<section class="section"><div class="section-head"><div><h2>Couverture du concours</h2><p>Ne pas confondre “programme structuré” et “niveau mesuré”.</p></div></div><div class="subject-mini-grid">'+(p.subjects||[]).map(y=>'<div class="subject-mini"><span>'+esc(y.icon||'•')+'</span><div><b>'+esc(y.title)+'</b><small>'+(y.coverage_mode==='measured'?'mesure active':'mesure à construire')+'</small></div><em class="'+(y.coverage_mode==='measured'?'good':'warn')+'">'+(y.coverage_mode==='measured'?num(x.coverage||0)+' %':'—')+'</em></div>').join('')+'</div></section>'
}

async function renderLearn(){
  if(state.tab==='curriculum')return renderCurriculum();
  if(state.tab==='modules')return renderModules();
  if(state.tab==='cards')return renderCards();
  if(state.tab==='map')return renderKnowledgeMap();
  const total=state.status.knowledge_units_loaded||0;
  qs('#viewHost').innerHTML='<section class="hero"><div class="eyebrow">PARCOURS D’APPRENTISSAGE</div><h2>Comprendre avant de répéter.</h2><p>Les fiches et les unités de connaissance alimentent directement les entraînements. La progression n’est pas une succession de PDF.</p><div class="hero-actions"><button class="btn good" id="learnContinue">Continuer le Module 2</button><button class="btn secondary" id="learnDay">Planifier 6 h</button></div></section>'+
    '<div class="metric-grid">'+metric(num(total),'notions cataloguées')+metric(num(state.modules.length),'modules')+metric(num(state.status.questions_loaded),'questions liées')+metric(num(state.status.reviews_due),'rappels à revoir')+metric('8 facteurs','moteur adaptatif')+'</div>'+
    '<section class="section"><div class="section-head"><div><h2>Ordre recommandé</h2><p>Socle national → Afrique → monde → sciences → culture → actualité → grand mix.</p></div></div><div class="module-grid">'+state.modules.map(moduleCard).join('')+'</div></section>';
  qs('#learnContinue').onclick=()=>openModule(2);qs('#learnDay').onclick=()=>go('home','day');bindModuleCards()
}
async function renderModules(){
  qs('#viewHost').innerHTML='<div class="section-head"><div><h2>Modules</h2><p>Chaque module regroupe fiches, notions, questions et progression.</p></div></div><div class="module-grid">'+state.modules.map(moduleCard).join('')+'</div>';bindModuleCards()
}
async function renderCards(){
  state.cardMode=state.cardMode||'courses';
  const index=await api('/api/lessons/index'),all=index.items||[];
  let cards=[];
  if(state.cardMode==='micro'){
    const micro=await api('/api/microcards?limit=2000'+(state.cardModule?'&module='+state.cardModule:''));
    cards=micro.items||[];
  }
  const modules=[...new Set(all.map(x=>x.module))].sort((a,b)=>a-b);
  qs('#viewHost').innerHTML=
    '<div class="section-head"><div><h2>Bibliothèque d’apprentissage</h2><p>'+num(all.length)+' cours structurés · '+num(state.status?.knowledge_units_loaded||0)+' micro-fiches disponibles.</p></div></div>'+
    '<div class="card" style="padding:8px;margin-bottom:12px"><div class="card-row"><div style="display:flex;gap:6px;flex-wrap:wrap"><button class="btn '+(state.cardMode==='courses'?'':'secondary')+' small" id="showCourses">Cours</button><button class="btn '+(state.cardMode==='micro'?'':'secondary')+' small" id="showMicro">Micro-fiches</button></div><div style="display:flex;gap:6px"><select class="field" id="cardModule"><option value="">Tous les modules</option>'+modules.map(m=>'<option value="'+m+'" '+(Number(state.cardModule)===m?'selected':'')+'>Module '+m+'</option>').join('')+'</select><input class="field" id="cardSearch" placeholder="Rechercher…"></div></div></div>'+
    '<div id="cardLibrary"></div>';

  const draw=()=>{
    const q=(qs('#cardSearch').value||'').trim().toLowerCase(),m=Number(qs('#cardModule').value||0);state.cardModule=m||0;
    if(state.cardMode==='courses'){
      const rows=all.filter(x=>(!m||x.module===m)&&(!q||(x.title+' '+x.summary+' '+(x.chapter||'')).toLowerCase().includes(q)));
      qs('#cardLibrary').innerHTML=rows.length?'<div class="grid two">'+rows.map(x=>'<button class="card" data-card-module="'+x.module+'" data-card-id="'+esc(x.id)+'" style="text-align:left"><div class="eyebrow">MODULE '+x.module+' · '+esc(x.chapter||'COURS')+' · '+num(x.minutes)+' MIN</div><h3>'+esc(x.title)+'</h3><p>'+esc(x.summary||'')+'</p><div style="margin-top:10px"><span class="pill">'+num(x.points_count||0)+' points clés</span><span class="pill">'+num(x.recall_count||0)+' rappels actifs</span><span class="pill">'+num(x.knowledge_count||0)+' repères</span></div></button>').join('')+'</div>':empty('◫','Aucun cours','Modifie le filtre ou la recherche.');
      qsa('[data-card-module]').forEach(b=>b.onclick=()=>openLesson(Number(b.dataset.cardModule),b.dataset.cardId))
    }else{
      const rows=cards.filter(x=>(!m||Number(x.module)===m)&&(!q||(x.front+' '+x.answer+' '+x.domain+' '+x.subdomain).toLowerCase().includes(q))).slice(0,300);
      qs('#cardLibrary').innerHTML=rows.length?'<div class="bank-grid">'+rows.map((x,i)=>'<button class="bank-card" data-micro="'+i+'" style="text-align:left"><header><span class="eyebrow">'+esc(x.domain)+'</span><span class="pill">'+esc(x.stability)+'</span></header><h3>'+esc(x.front)+'</h3><footer><span class="pill">'+esc(x.subdomain||'')+'</span><span class="pill">'+num(x.variants)+' variante(s)</span></footer></button>').join('')+'</div>':empty('◫','Aucune micro-fiche','Modifie le filtre ou la recherche.');
      qsa('[data-micro]').forEach(b=>b.onclick=()=>openMicrocard(rows[Number(b.dataset.micro)]))
    }
  };
  qs('#showCourses').onclick=()=>{state.cardMode='courses';renderCards()};
  qs('#showMicro').onclick=()=>{state.cardMode='micro';renderCards()};
  qs('#cardModule').onchange=()=>{if(state.cardMode==='micro')renderCards();else draw()};
  qs('#cardSearch').oninput=draw;draw()
}
function modeCard(icon,title,body,meta,mode){
  return '<article class="mode-card"><div class="mode-icon">'+esc(icon)+'</div><h3>'+esc(title)+'</h3><p>'+esc(body)+'</p><div class="mode-foot"><span class="pill">'+esc(meta)+'</span><button class="btn small" data-mode="'+esc(mode)+'">Lancer</button></div></article>'
}
async function renderTrain(){
  if(state.tab==='sprint')return renderSprint();
  if(state.tab==='errors')return renderErrors();
  if(state.tab==='bank')return renderBank();
  if(state.tab==='quick')return renderQuick();
  const due=Number(state.status?.reviews_due||0);
  qs('#viewHost').innerHTML=
    '<section class="hero"><div class="eyebrow">ENTRAÎNEMENT ADAPTATIF</div><h2>Le moteur choisit quoi travailler, pas seulement au hasard.</h2><p>Il tient compte des erreurs fiables, de la maîtrise, de la vitesse, des expositions, des révisions dues, de la difficulté, de la couverture et de la fraîcheur.</p><div class="hero-actions"><button class="btn good" id="adaptive20">Lancer 20 questions</button><button class="btn secondary" id="adaptive30">30 questions</button></div></section>'+
    '<div class="metric-grid">'+metric('8','facteurs adaptatifs')+metric(num(due),'révisions dues')+metric(num(state.status?.knowledge_units_loaded||0),'notions disponibles')+metric('1 / notion','max par session')+metric('Blueprint','couverture contrôlée')+'</div>'+
    '<section class="section"><div class="section-head"><div><h2>Choisir selon ton objectif</h2><p>Tu n’as pas besoin de régler des paramètres techniques : choisis simplement la forme de travail.</p></div></div><div class="mode-grid">'+
      modeCard('◎','Adaptatif 20','Rééquilibre automatiquement lacunes, nouveauté et couverture.','13 min 20 s max','adaptive20')+
      modeCard('◉','Adaptatif 30','Bloc plus long pour consolider plusieurs domaines.','20 min max','adaptive30')+
      modeCard('↻','Révisions dues',due?'Travaille en priorité les rappels arrivés à échéance.':'Aucun rappel dû : le moteur basculera vers les points faibles.','13 min 20 s max','review20')+
    '</div></section>'+
    '<section class="section"><div class="grid two"><div class="card"><h3>Ce que fait le moteur</h3><p>Il sélectionne à l’intérieur d’un blueprint de couverture. Une faiblesse ne peut donc pas faire disparaître complètement les autres domaines.</p></div><div class="card"><h3>Ce que tu dois faire</h3><p>Réponds sans support, utilise « Je ne sais pas » quand nécessaire, puis lis la correction. La prochaine sélection s’adaptera à tes résultats fiables.</p></div></div></section>';
  qs('#adaptive20').onclick=()=>startSession({module:0,mode:'mixed',count:20,duration_seconds:900});
  qs('#adaptive30').onclick=()=>startSession({module:0,mode:'mixed',count:30,duration_seconds:1500});
  qsa('[data-mode]').forEach(b=>{
    if(b.dataset.mode==='adaptive20')b.onclick=()=>startSession({module:0,mode:'mixed',count:20,duration_seconds:900});
    if(b.dataset.mode==='adaptive30')b.onclick=()=>startSession({module:0,mode:'mixed',count:30,duration_seconds:1500});
    if(b.dataset.mode==='review20')b.onclick=()=>startSession({module:0,mode:'review',count:20,duration_seconds:900})
  })
}
async function renderQuick(){
  qs('#viewHost').innerHTML=
    '<section class="hero"><div class="eyebrow">SÉRIE RAPIDE</div><h2>Un bloc court, immédiatement.</h2><p>Idéal entre deux cours ou quand tu as peu de temps. La correction reste synchronisée et les erreurs alimentent les révisions.</p></section>'+
    '<section class="section"><div class="mode-grid">'+
      modeCard('⚡','10 questions','Sprint très court pour automatiser les repères.','6 min 40 s max','quick10')+
      modeCard('◎','20 questions','Bloc standard de consolidation.','13 min 20 s max','quick20')+
      modeCard('◫','30 questions','Série plus dense sans devenir un examen blanc.','20 min max','quick30')+
    '</div></section><section class="section"><div class="card"><h3>Conseil d’utilisation</h3><p>Ne relis pas le cours entre les questions. Termine la série, regarde la correction, puis ouvre « Mes erreurs » si une confusion revient.</p></div></section>';
  qsa('[data-mode]').forEach(b=>{
    if(b.dataset.mode==='quick10')b.onclick=()=>startSession({module:0,mode:'mixed',count:10,duration_seconds:420});
    if(b.dataset.mode==='quick20')b.onclick=()=>startSession({module:0,mode:'mixed',count:20,duration_seconds:900});
    if(b.dataset.mode==='quick30')b.onclick=()=>startSession({module:0,mode:'mixed',count:30,duration_seconds:1500})
  })
}
async function renderBank(){
  const load=async()=>{
    const q=encodeURIComponent((qs('#bankSearch')?.value||'').trim()),module=Number(qs('#bankModule')?.value||0);
    const j=await api('/api/bank?limit=180'+(q?'&q='+q:'')+(module?'&module='+module:'')),rows=j.items||[];
    const host=qs('#bankResults');if(!host)return;
    host.innerHTML=rows.length?'<div class="bank-grid">'+rows.map(x=>'<article class="bank-card"><header><span class="eyebrow">MODULE '+x.module+' · '+esc(x.domain)+'</span><span class="pill">'+esc(x.stability||'STABLE')+'</span></header><h3>'+esc(x.prompt)+'</h3><footer><span class="pill">'+esc(x.subdomain||'')+'</span><span class="pill">Difficulté '+num(x.difficulty||1)+'</span><button class="btn ghost small" data-bank-module="'+x.module+'">10 Q du module</button></footer></article>').join('')+'</div>':empty('⌕','Aucune question trouvée','Essaie un autre mot-clé ou enlève le filtre de module.');
    qsa('[data-bank-module]').forEach(b=>b.onclick=()=>startSession({module:Number(b.dataset.bankModule),mode:'module',count:10,duration_seconds:600}));
    const count=qs('#bankCount');if(count)count.textContent=num(rows.length)+' affichée(s)'
  };
  qs('#viewHost').innerHTML=
    '<div class="section-head"><div><h2>Banque de questions</h2><p>Explorer le corpus sans révéler la bonne réponse avant l’entraînement.</p></div><span class="pill" id="bankCount">—</span></div>'+
    '<div class="bank-toolbar"><input class="field" id="bankSearch" placeholder="Chercher une notion, un domaine, un mot…"><select class="field" id="bankModule"><option value="">Tous les modules</option>'+state.modules.slice(0,7).map(m=>'<option value="'+m.id+'">Module '+m.id+' · '+esc(m.short||m.title)+'</option>').join('')+'</select><button class="btn" id="bankMixed">Mix 20</button><button class="btn secondary" id="bankReset">Réinitialiser</button></div>'+
    '<div class="lesson-note"><b>Mode exploration</b><p>Cette vue montre les énoncés et métadonnées, pas les réponses. Pour travailler une notion, lance une série du module correspondant.</p></div><div id="bankResults" style="margin-top:12px"></div>';
  let timer=null;qs('#bankSearch').oninput=()=>{clearTimeout(timer);timer=setTimeout(load,180)};qs('#bankModule').onchange=load;qs('#bankMixed').onclick=()=>startSession({module:0,mode:'mixed',count:20,duration_seconds:900});qs('#bankReset').onclick=()=>{qs('#bankSearch').value='';qs('#bankModule').value='';load()};await load()
}
async function renderKnowledgeMap(){
  const j=await api('/api/knowledge'),items=j.items||[],groups={};
  for(const x of items){
    const m=Number(x.module||0);groups[m]??={count:0,questions:0,domains:{}};
    groups[m].count++;groups[m].questions+=Number(x.question_count||0);
    const d=x.domain||'Autre';groups[m].domains[d]=(groups[m].domains[d]||0)+1
  }
  qs('#viewHost').innerHTML=
    '<section class="hero"><div class="eyebrow">CARTE DES CONNAISSANCES</div><h2>Voir comment le corpus est réellement structuré.</h2><p>Chaque unité représente une connaissance distincte. Les variantes de questions restent rattachées à la même unité pour éviter le faux volume.</p></section>'+
    '<div class="metric-grid">'+metric(num(items.length),'unités visibles')+metric(num(state.modules.length),'modules')+metric(num(items.reduce((n,x)=>n+Number(x.question_count||0),0)),'variantes liées')+metric('1 notion','par session au maximum')+metric('STABLE + CURRENT','fraîcheur séparée')+'</div>'+
    '<section class="section"><div class="grid two">'+state.modules.map(m=>{const g=groups[Number(m.id)]||{count:0,questions:0,domains:{}};const top=Object.entries(g.domains).sort((a,b)=>b[1]-a[1]).slice(0,4);return '<article class="card knowledge-map-card"><div class="card-row"><div><div class="eyebrow">MODULE '+m.id+'</div><h3>'+esc(m.short||m.title)+'</h3></div><button class="btn ghost small" data-map-module="'+m.id+'">Ouvrir</button></div><div class="stat-line"><span>Unités de connaissance</span><b>'+num(g.count)+'</b></div><div class="stat-line"><span>Questions liées</span><b>'+num(g.questions)+'</b></div><div class="knowledge-domain-chips">'+top.map(([d,n])=>'<span class="pill">'+esc(d)+' · '+num(n)+'</span>').join('')+'</div></article>'}).join('')+'</div></section>';
  qsa('[data-map-module]').forEach(b=>b.onclick=()=>openModule(Number(b.dataset.mapModule)))
}
async function renderErrors(){
  const j=await api('/api/errors?limit=120'),arr=j.items||[];
  qs('#viewHost').innerHTML='<div class="section-head"><div><h2>Mes erreurs</h2><p>Uniquement les erreurs issues de sessions techniquement complètes.</p></div>'+(arr.length?'<button class="btn" id="errorsStart">Travailler maintenant</button>':'')+'</div>'+
    (arr.length?'<div class="grid two">'+arr.map(x=>'<div class="card"><div class="card-row"><span class="pill bad">'+num(x.misses)+' erreur(s)</span><span class="eyebrow">'+esc(x.domain)+'</span></div><h3 style="margin-top:11px">'+esc(x.prompt)+'</h3><p>Dernière erreur : '+date(x.last_miss)+'</p></div>').join('')+'</div>':empty('✓','Aucune erreur fiable enregistrée','Commence une série : les erreurs apparaîtront ici automatiquement.','<button class="btn" id="errorsMix">Lancer une série</button>'));
  qs('#errorsStart')?.addEventListener('click',()=>startSession({module:0,mode:'review',count:20,duration_seconds:900}));qs('#errorsMix')?.addEventListener('click',()=>startSession({module:0,mode:'mixed',count:20,duration_seconds:900}))
}

async function renderReview(){
  if(state.tab==='notebook')return renderNotebook();
  if(state.tab==='weak')return renderWeak();
  if(state.tab==='history')return renderReviewHistory();
  const j=await api('/api/reviews?limit=120'),arr=j.items||[];
  qs('#viewHost').innerHTML='<section class="hero"><div class="eyebrow">RÉPÉTITION ESPACÉE</div><h2>'+(arr.length?num(arr.length)+' rappels sont prêts.':'Rien n’est en retard.')+'</h2><p>Le calendrier se nourrit uniquement des sessions fiables. Les réponses non synchronisées ne créent jamais de faux rappels.</p>'+(arr.length?'<div class="hero-actions"><button class="btn good" id="reviewStart">Réviser maintenant</button></div>':'')+'</section>'+
    '<section class="section">'+(arr.length?'<div class="grid two">'+arr.map(x=>'<div class="card"><div class="card-row"><span class="eyebrow">'+esc(x.domain)+'</span><span class="pill">'+num(x.interval_days)+' j</span></div><h3 style="margin-top:10px">'+esc(x.prompt)+'</h3><p>Échéance : '+date(x.due_at)+' · '+num(x.lapses)+' rechute(s)</p></div>').join('')+'</div>':empty('↻','Aucune révision due','Utilise ce temps pour apprendre une nouvelle fiche ou lancer un entraînement adaptatif.','<button class="btn" data-go="learn" data-tab="cards">Voir les fiches</button><button class="btn secondary" data-go="train" data-tab="adaptive">S’entraîner</button>'))+'</section>';
  qs('#reviewStart')?.addEventListener('click',()=>startSession({module:0,mode:'review',count:Math.min(30,arr.length),duration_seconds:1200}));bindSpaceLinks()
}
async function renderWeak(){
  const e=await api('/api/errors?limit=120'),groups={};for(const x of e.items||[]){groups[x.domain]??={n:0,misses:0};groups[x.domain].n++;groups[x.domain].misses+=Number(x.misses||0)}
  const a=Object.entries(groups).sort((a,b)=>b[1].misses-a[1].misses);
  qs('#viewHost').innerHTML='<div class="section-head"><div><h2>Points faibles</h2><p>Domaines triés par fréquence d’erreur.</p></div></div>'+(a.length?'<div class="domain-list">'+a.map(([d,x])=>'<div class="card domain-row"><b>'+esc(d)+'</b>'+progressBar(Math.min(100,x.misses*8),'warn')+'<span>'+x.misses+' erreurs</span></div>').join('')+'</div>':empty('✓','Pas encore de faiblesse mesurable','Les statistiques apparaissent après des sessions fiables.'))
}
async function renderReviewHistory(){
  const st=await loadStats(true);qs('#viewHost').innerHTML='<div class="section-head"><div><h2>Historique de révision</h2><p>Sessions terminées et scores fiables.</p></div></div>'+historyTable(st.recent||[])
}

async function renderExam(){
  if(state.tab==='mini')return renderMini();
  if(state.tab==='history'){const st=await loadStats(true);qs('#viewHost').innerHTML='<div class="section-head"><div><h2>Historique des examens</h2><p>Résultats fiables uniquement.</p></div></div>'+historyTable((st.recent||[]).filter(x=>x.mode==='mock'));return}
  const ex=await api('/api/exetat/coverage');
  const ready=(ex.lanes||[]).every(x=>x.ready_for_50);
  qs('#viewHost').innerHTML='<section class="hero"><div class="eyebrow">BLANC CULTURE GÉNÉRALE · CALIBRAGE EXETAT</div><h2>Le contenu suit désormais 2 Civisme · 6 Géographie · 6 Histoire · 6 Philosophie par tranche de 20.</h2><p>Le calibrage reproduit la structure de Culture générale EXETAT ; la durée interne est désormais uniforme : 40 secondes par question, quel que soit le format.</p><div class="hero-actions"><button class="btn good" id="mock20x">20 questions · 2/6/6/6</button><button class="btn secondary" id="mock40x">40 questions · double bloc</button></div></section>'+
    '<div class="metric-grid">'+(ex.lanes||[]).map(x=>metric(num(x.knowledge_units),esc(x.label)+' notions')).join('')+metric(ready?'Prêt':'À renforcer','capacité 50')+'</div>'+
    '<section class="section"><div class="grid three">'+
      modeCard('◇','EXETAT 20','Composition exacte du blueprint Culture générale.','entraînement','mock20x')+
      modeCard('◈','EXETAT 40','Deux blocs pour tester endurance et stabilité.','entraînement long','mock40x')+
      modeCard('⚡','Demi-bloc 10','1 Civisme · 3 Géographie · 3 Histoire · 3 Philosophie.','sprint','mock10x')+
    '</div></section>';
  const launch=(n,sec)=>startSession({module:0,mode:'mock',count:n,duration_seconds:sec});
  qs('#mock20x').onclick=()=>launch(20,1200);qs('#mock40x').onclick=()=>launch(40,2400);
  qsa('[data-mode]').forEach(b=>{if(b.dataset.mode==='mock20x')b.onclick=()=>launch(20,1200);if(b.dataset.mode==='mock40x')b.onclick=()=>launch(40,2400);if(b.dataset.mode==='mock10x')b.onclick=()=>launch(10,600)})
}
async function renderMini(){
  qs('#viewHost').innerHTML='<div class="section-head"><div><h2>Mini-tests</h2><p>Tests courts pour une matière ou un objectif précis.</p></div></div><div class="module-grid">'+state.modules.slice(0,7).map(m=>'<article class="module-card"><div class="module-icon">'+m.id+'</div><div class="module-copy"><h3>'+esc(m.short||m.title)+'</h3><p>10 questions · 40 s/question · 6 min 40 s max</p></div><div class="module-meta"><button class="btn small" data-mini="'+m.id+'">Lancer</button></div></article>').join('')+'</div>';qsa('[data-mini]').forEach(b=>b.onclick=()=>startSession({module:Number(b.dataset.mini),mode:'module',count:10,duration_seconds:480}))
}
function historyTable(rows){
  if(!rows.length)return empty('◇','Aucun résultat','Termine une session fiable pour alimenter cet historique.');
  return '<div class="card"><table class="history-table"><thead><tr><th>Date</th><th>Mode</th><th>Questions</th><th>Score</th></tr></thead><tbody>'+rows.map(x=>'<tr><td>'+date(x.finished_at||x.created_at)+'</td><td>'+esc(x.mode)+'</td><td>'+num(x.total)+'</td><td><b>'+pct(x.score)+'</b></td></tr>').join('')+'</tbody></table></div>'
}

async function renderProgress(){
  if(state.tab==='readiness')return renderReadiness();
  if(state.tab==='mastery')return renderMastery();
  const st=await loadStats(true);
  if(state.tab==='domains')return renderDomains(st);
  if(state.tab==='speed')return renderSpeed(st);
  if(state.tab==='history'){qs('#viewHost').innerHTML='<div class="section-head"><div><h2>Historique</h2><p>Toutes les sessions fiables.</p></div></div>'+historyTable(st.recent||[]);return}
  const avg=st.recent?.length?Math.round(st.recent.reduce((n,x)=>n+Number(x.score||0),0)/st.recent.length):0;
  qs('#viewHost').innerHTML='<div class="metric-grid">'+metric(pct(state.status.best_score),'meilleur score')+metric(pct(avg),'moyenne récente')+metric(num(state.status.sessions_finished),'sessions fiables')+metric(num(state.status.answers_saved),'réponses')+metric(num(state.status.knowledge_units_loaded),'notions indexées')+'</div>'+
    '<section class="section"><div class="grid two"><div class="card"><div class="section-head"><div><h2>Domaines</h2><p>Précision observée.</p></div></div><div class="domain-list">'+(st.domains||[]).slice(0,8).map(x=>'<div class="domain-row"><b>'+esc(x.domain)+'</b>'+progressBar(x.pct,x.pct>=75?'good':x.pct<50?'warn':'')+'<span>'+pct(x.pct)+'</span></div>').join('')+'</div></div><div class="card"><div class="section-head"><div><h2>Dernières sessions</h2><p>Évolution récente.</p></div></div>'+((st.recent||[]).slice(0,6).map(x=>'<div class="stat-line"><span>'+date(x.finished_at)+'</span><b>'+pct(x.score)+'</b></div>').join('')||'<p>Aucune session.</p>')+'</div></div></section>'
}
function renderDomains(st){
  qs('#viewHost').innerHTML='<div class="section-head"><div><h2>Performance par domaine</h2><p>Précision issue des réponses fiables.</p></div></div><div class="domain-list">'+((st.domains||[]).map(x=>'<div class="card domain-row"><b>'+esc(x.domain)+'</b>'+progressBar(x.pct,x.pct>=75?'good':x.pct<50?'warn':'')+'<span>'+pct(x.pct)+'</span></div>').join('')||empty('▥','Aucune donnée','Les domaines apparaîtront après les premières sessions.'))+'</div>'
}
function renderSpeed(st){
  const s=st.speed||{},timed=Number(s.timed||0),avg=Math.round(Number(s.avg_ms||0)/1000),fast=timed?Math.round(100*Number(s.fast_30s||0)/timed):0,slow=timed?Math.round(100*Number(s.over_40s||0)/timed):0;
  const rows=(st.domains||[]).filter(x=>Number(x.avg_ms||0)>0).sort((a,b)=>Number(b.avg_ms)-Number(a.avg_ms));
  qs('#viewHost').innerHTML=
    '<div class="section-head"><div><h2>Vitesse de réponse</h2><p>Mesures calculées uniquement sur les réponses de sessions complètes et fiables.</p></div></div>'+
    '<div class="metric-grid">'+metric(timed?avg+' s':'—','temps moyen')+metric(timed?fast+' %':'—','réponses ≤ 30 s')+metric(timed?slow+' %':'—','anciennes réponses > 40 s')+metric(num(timed),'réponses chronométrées')+metric('40 s','limite stricte par question')+'</div>'+
    '<section class="section"><div class="grid two"><div class="card"><div class="section-head"><div><h2>Domaines les plus lents</h2><p>Un domaine lent n’est pas automatiquement faible : compare toujours vitesse et précision.</p></div></div>'+
      (rows.length?rows.slice(0,8).map(x=>'<div class="stat-line"><span>'+esc(x.domain)+' · '+pct(x.pct)+'</span><b>'+Math.round(Number(x.avg_ms)/1000)+' s</b></div>').join(''):'<p>Pas encore assez de réponses chronométrées.</p>')+
    '</div><div class="card"><div class="section-head"><div><h2>Comment l’utiliser</h2><p>Lecture pratique des données.</p></div></div><div class="study-sequence">'+
      '<div class="study-step"><span>1</span><p>Précision basse + lenteur : retourne au cours et au rappel actif.</p></div>'+
      '<div class="study-step"><span>2</span><p>Précision haute + lenteur : travaille des séries rapides pour automatiser.</p></div>'+
      '<div class="study-step"><span>3</span><p>Rapide + erreurs : ralentis et vérifie les confusions ou lectures trop hâtives.</p></div>'+
      '<div class="study-step"><span>4</span><p>Rapide + juste : laisse la répétition espacée éloigner progressivement la prochaine exposition.</p></div>'+
    '</div></div></div></section>'
}

async function renderAdmin(){
  if(state.tab==='connection')return renderConnection();
  if(state.tab==='corpus')return renderCorpus();
  if(state.tab==='updates')return renderUpdates();
  if(state.tab==='settings')return renderSettings();
  const p=await api('/api/mobile/status');
  qs('#viewHost').innerHTML=
    '<section class="connection-hero"><div><div class="eyebrow">ACCÈS ÉLÈVE · LAN ROBUSTE</div><h2>Un QR qui reste valable pendant la durée choisie.</h2><p>Le pass peut être rescanné après une coupure ou une perte de session. L’accès 8 h est recommandé pour une vraie journée de travail.</p></div><div class="connection-status '+(p.session_count?'online':'idle')+'"><b>'+num(p.session_count)+'</b><span>appareil(s) actif(s)</span></div></section>'+
    '<div class="grid two"><div class="admin-card"><div class="card-row"><div><div class="eyebrow">NOUVEAU PASS</div><h3>Choisir la durée</h3></div><span class="pill">'+esc(p.lan_ip||'Wi-Fi indisponible')+'</span></div>'+
      '<div class="hero-actions pair-actions"><button class="btn good" data-pair="480">8 h recommandé</button>'+[30,60,90,120,180,240,360].map(m=>'<button class="btn secondary small" data-pair="'+m+'">'+(m<60?m+' min':(m%60?Math.floor(m/60)+' h '+(m%60)+' min':m/60+' h'))+'</button>').join('')+'</div>'+
      '<div id="pairPreview" class="pair-preview"></div></div>'+
    '<div class="admin-card"><div class="section-head"><div><div class="eyebrow">MONITEUR LIVE</div><h3>Connexion téléphone</h3></div><button class="btn ghost small" id="openConnectionMonitor">Détails</button></div><div id="mobileLiveMonitor">'+mobileMonitorHtml(p)+'</div><div id="accessList">'+accessList(p.sessions||[])+'</div><button class="btn danger small" id="revokeAll" style="margin-top:12px">Révoquer tous les accès</button></div></div>'+
    '<section class="section"><div class="card"><div class="card-row"><div><h3>Aperçu élève</h3><p>Tester le même espace que le téléphone sans quitter le PC administrateur.</p></div><button class="btn secondary small" id="previewStudent">Ouvrir</button></div></div></section>';
  if(p.pair)showPair(p.pair);
  qs('#previewStudent')?.addEventListener('click',()=>{state.previewStudent=true;localStorage.setItem('exc2_preview_student','1');go('home','today')});
  qsa('[data-pair]').forEach(b=>b.onclick=async()=>{const x=await api('/api/mobile/pair?minutes='+b.dataset.pair,{method:'POST'});showPair(x.pair);drawMobileStatus(x)});
  qs('#revokeAll').onclick=async()=>{await api('/api/mobile/revoke',{method:'POST'});toast('Accès révoqués');renderAdmin()};
  qs('#openConnectionMonitor').onclick=()=>go('admin','connection');
  bindPhoneRevokes();startMobileAdminMonitor()
}
function accessList(items){
  return items.length?items.map(x=>{
    const live=x.online?'<span class="link-dot online"></span>en ligne':x.last_seen?'<span class="link-dot idle"></span>en attente':'<span class="link-dot off"></span>jamais vu';
    return '<div class="phone-session"><div><b>Appareil '+esc((x.id||'session').slice(-6))+'</b><span>'+live+' · '+durationLabel(x.remaining_seconds)+' restantes</span><small>'+(x.remote?'LAN '+esc(x.remote)+' · ':'')+(x.last_seen?'vu '+date(x.last_seen):'aucune activité')+'</small></div><button class="btn ghost small" data-revoke-phone="'+esc(x.id)+'">Révoquer</button></div>'
  }).join(''):'<div class="empty-state compact"><div class="empty-inner"><h3>Aucun accès actif</h3><p>Crée un pass 8 h ou une durée plus courte.</p></div></div>'
}
function showPair(p){
  const host=qs('#pairPreview');if(!host||!p)return;
  host.dataset.qr=String(p.qr_url||'');host.dataset.transport=String(p.transport||'');
  const edgeReady=Boolean(p.qr_url)&&['B_EDGE_PRIMARY','B_EDGE_PERSISTED'].includes(String(p.transport||''));
  if(!edgeReady&&p.edge_required!==false){
    host.innerHTML='<div class="connection-warning"><b>QR B‑EDGE en attente.</b><br>L’ancien téléphone est le serveur permanent. Aucun QR PC fragile n’est proposé. Ouvre BCP Edge Server sur l’ancien téléphone : son écran « Excellentia · accès permanent » porte le QR à scanner.</div>'+
      '<div class="qr-detail"><div class="stat-line"><span>Durée préparée</span><b>'+durationLabel(p.minutes*60)+'</b></div>'+
      '<div class="stat-line"><span>Transport</span><b>B‑EDGE obligatoire</b></div>'+
      '<p class="muted-note">Le PC peut changer de réseau ou s’éteindre. Le téléphone élève doit seulement être sur le même Wi‑Fi que l’ancien téléphone B‑EDGE.</p></div>';
    return
  }
  host.innerHTML='<div class="qr-grid durable-qr"><div><div class="qr-box" id="qrBox"></div><div class="qr-caption">QR B‑EDGE · même Wi‑Fi que l’ancien téléphone · PC indépendant</div></div><div class="qr-detail">'+
    '<div class="card-row"><div><span class="eyebrow">PASS DE CONNEXION EDGE</span><h2>'+esc(p.code||'—')+'</h2></div><span class="pill good">'+durationLabel(p.remaining_seconds)+'</span></div>'+
    '<p><b>La durée choisie démarre au premier scan réussi.</b> Le serveur de référence est l’ancien téléphone B‑EDGE, pas le PC.</p>'+
    '<div class="stat-line"><span>'+(p.activated?'Accès expire':'Pass prêt')+'</span><b>'+date(p.session_expires_at||p.offer_expires_at)+'</b></div>'+
    '<div class="stat-line"><span>Transport</span><b>Ancien téléphone B‑EDGE</b></div>'+
    '<div class="stat-line"><span>Reconnexions</span><b>'+num(p.claims||0)+' / '+num(p.max_claims||512)+'</b></div>'+
    '<div class="qr-links"><code>'+esc(p.qr_url)+'</code></div>'+
    '<p class="muted-note">Après le scan, le PC peut changer de Wi‑Fi ou s’éteindre. Les progrès sont conservés par B‑EDGE puis réconciliés au retour du PC.</p></div></div>';
  const q=qs('#qrBox');if(window.QRCode&&p.qr_url)new QRCode(q,{text:p.qr_url,width:190,height:190})
}
function mobileMonitorHtml(p){
  const edge=p.edge_continuity?.ok?'<div class="monitor-row"><span>Nœud permanent</span><b class="good-text">B‑EDGE prêt</b></div>':p.auto_edge_enabled?'<div class="monitor-row"><span>Nœud permanent</span><b>en attente / QR sur B‑EDGE</b></div>':'';
  const pair=p.pair?'<div class="monitor-row"><span>Pass '+(p.pair.minutes<60?p.pair.minutes+' min':(p.pair.minutes%60?Math.floor(p.pair.minutes/60)+' h '+(p.pair.minutes%60)+' min':p.pair.minutes/60+' h'))+(p.pair.activated?' · actif':' · en attente du 1er scan')+'</span><b>'+durationLabel(p.pair.remaining_seconds)+'</b></div>':'<div class="monitor-row"><span>Pass QR</span><b>aucun</b></div>';
  return '<div class="connection-monitor">'+
    '<div class="monitor-row"><span>Serveur</span><b class="good-text">● actif</b></div>'+
    '<div class="monitor-row"><span>Adresse LAN</span><b>'+esc(p.base_url||'indisponible')+'</b></div>'+
    '<div class="monitor-row"><span>Anti-veille</span><b>'+(p.keep_awake?'actif':'en attente')+'</b></div>'+
    '<div class="monitor-row"><span>Accès actifs</span><b>'+num(p.session_count||0)+'</b></div>'+pair+edge+
    '<div class="monitor-row"><span>Uptime serveur</span><b>'+durationLabel(p.server_uptime_seconds||0)+'</b></div>'+
  '</div>'
}
function bindPhoneRevokes(){qsa('[data-revoke-phone]').forEach(b=>b.onclick=async()=>{await api('/api/mobile/session/revoke?id='+encodeURIComponent(b.dataset.revokePhone),{method:'POST'});const p=await api('/api/mobile/status');drawMobileStatus(p);toast('Accès téléphone révoqué')})}
function drawMobileStatus(p){
  const m=qs('#mobileLiveMonitor');if(m)m.innerHTML=mobileMonitorHtml(p);
  const a=qs('#accessList');if(a){a.innerHTML=accessList(p.sessions||[]);bindPhoneRevokes()}
  const preview=qs('#pairPreview');if(preview&&p.pair&&(!preview.querySelector('#qrBox')||p.pair.ip_changed||preview.dataset.qr!==String(p.pair.qr_url||'')||preview.dataset.transport!==String(p.pair.transport||'')))showPair(p.pair)
}
function startMobileAdminMonitor(){
  if(state.connectionTicker)clearInterval(state.connectionTicker);
  state.connectionTicker=setInterval(async()=>{
    if(state.space!=='admin'||!['access','connection'].includes(state.tab)){clearInterval(state.connectionTicker);state.connectionTicker=null;return}
    try{const p=await api('/api/mobile/status');drawMobileStatus(p)}catch{}
  },4000)
}
async function renderConnection(){
  const p=await api('/api/mobile/status');
  qs('#viewHost').innerHTML=
    '<section class="connection-hero"><div><div class="eyebrow">MONITEUR DE LIAISON</div><h2>Téléphone ↔ PC principal</h2><p>Le moniteur se met à jour toutes les 4 secondes. Un appareil est considéré en ligne s’il a répondu récemment au heartbeat.</p></div><div class="connection-status '+(p.session_count?'online':'idle')+'"><b>'+num(p.session_count)+'</b><span>session(s)</span></div></section>'+
    '<div class="grid two"><div class="admin-card"><div class="section-head"><div><h3>État du serveur</h3><p>Accès LAN local, sans dépendre d’Internet.</p></div></div><div id="mobileLiveMonitor">'+mobileMonitorHtml(p)+'</div>'+
      '<div class="hero-actions"><button class="btn good" id="connectionPass8h">Créer/renouveler un pass 8 h</button><button class="btn secondary small" id="adminSync">Synchroniser</button></div><div id="pairPreview" class="pair-preview"></div></div>'+
    '<div class="admin-card"><div class="section-head"><div><h3>Appareils autorisés</h3><p>Dernière activité et temps restant en direct.</p></div></div><div id="accessList">'+accessList(p.sessions||[])+'</div></div></div>'+
    '<section class="section"><div class="card"><div class="card-row"><div><div class="eyebrow">B-EDGE / SERVEURS</div><h3>Diagnostic séparé</h3><p>Le test serveur n’est plus lancé automatiquement à l’ouverture de cet écran : cela évite d’ajouter de la latence au QR.</p></div><button class="btn secondary small" id="edgeManual">Tester maintenant</button></div><div id="edgePanel"></div></div></section>';
  if(p.pair)showPair(p.pair);
  qs('#connectionPass8h').onclick=async()=>{const x=await api('/api/mobile/pair?minutes=480',{method:'POST'});showPair(x.pair);drawMobileStatus(x)};
  qs('#adminSync').onclick=async()=>{const ok=await flushOffline();toast(ok?'Synchronisation terminée':'Synchronisation partielle',ok?'Toutes les écritures locales ont été reçues.':state.offline.length+' écriture(s) restent en attente.',ok?'sync-ok':'sync-pending')};
  bindPhoneRevokes();startMobileAdminMonitor();
  qs('#edgeManual').onclick=async()=>{
    const host=qs('#edgePanel');host.innerHTML='<p class="muted-note">Vérification B-EDGE…</p>';
    try{const edge=await api('/api/bedge/status');host.innerHTML='<div class="monitor-row"><span>Mode</span><b>'+esc(edge.mode||'—')+'</b></div><div class="monitor-row"><span>TLS</span><b>'+(edge.pin_ok?'validé':'non validé')+'</b></div>'}
    catch(e){host.innerHTML='<div class="connection-warning">Diagnostic serveur indisponible : '+esc(e.message)+'</div>'}
  }
}
async function renderCorpus(){
  const [ex,srcs,prov]=await Promise.all([api('/api/exetat/coverage'),api('/api/exetat/sources'),api('/api/exetat/provenance')]);
  const label={civics:'Civisme',geography:'Géographie',history:'Histoire',philosophy:'Philosophie'};
  const rejected=(srcs.sources||[]).filter(x=>x.status==='REJECTED').length;
  qs('#viewHost').innerHTML=
    '<div class="metric-grid">'+metric(num(state.status.questions_loaded),'questions actives')+metric(num(state.status.knowledge_units_loaded),'notions distinctes')+metric(num(prov.observed_total||0),'items EXETAT observés')+metric(num(prov.active_recovered_total||0),'items récupérés actifs')+metric(num(prov.verification?.FACT_CHECKED||0),'contre-vérifiés')+metric(num(prov.verification?.ARCHIVE_ONLY||0),'archive seule')+metric(num((srcs.sources||[]).length),'sources EXETAT')+metric(num((ex.sources?.years||[]).length),'années repérées')+metric(num(rejected),'sources rejetées')+'</div>'+
    '<section class="section"><div class="section-head"><div><h2>Blueprint Culture générale EXETAT</h2><p>Un bloc de 20 vise 2 Civisme + 6 Géographie + 6 Histoire + 6 Philosophie. Excellentia utilise l’EXETAT comme niveau de référence ; ce ratio n’est pas présenté comme un barème officiel Excellentia.</p></div></div><div class="exetat-lane-grid">'+
      (ex.lanes||[]).map(x=>'<article class="card exetat-lane '+(x.ready_for_50?'ready':'gap')+'"><div class="card-row"><div><div class="eyebrow">'+esc(label[x.id]||x.label)+'</div><h2>'+num(x.knowledge_units)+' notions</h2></div><span class="pill '+(x.ready_for_50?'good':'bad')+'">'+num(x.target_per_20)+'/20</span></div><div class="stat-line"><span>Questions actives</span><b>'+num(x.questions)+'</b></div><div class="stat-line"><span>Notions issues d’annales/archives</span><b>'+num(x.archive_knowledge_units||0)+'</b></div><div class="stat-line"><span>Items confirmés/rapportés</span><b>'+num(x.actual_knowledge_units||0)+'</b></div><div class="stat-line"><span>Notions calibrées EXETAT</span><b>'+num(x.calibrated_knowledge_units||0)+'</b></div><div class="stat-line"><span>Profondeur archives</span><b>'+(x.archive_depth_ready?'suffisante':'à renforcer')+'</b></div><div class="stat-line"><span>Capacité blanc 50</span><b>'+(x.ready_for_50?'OK':'À renforcer')+'</b></div></article>').join('')+
    '</div></section>'+
    '<section class="section"><div class="grid two"><div class="card"><div class="section-head"><div><h2>Pipeline par année</h2><p>On descend du plus récent vers l’ancien, sans confondre vrai item, recueil et simulation.</p></div></div>'+
      (srcs.sources||[]).slice().sort((a,b)=>Number(b.year)-Number(a.year)).slice(0,12).map(x=>'<div class="source-line"><span><b>'+esc(x.year)+'</b> · '+esc(x.kind)+'</span><em class="'+(x.status==='REJECTED'?'bad':x.status==='VERIFIED_STRUCTURE'?'good':'')+'">'+esc(x.status)+'</em></div>').join('')+
    '</div><div class="card"><div class="section-head"><div><h2>Ancien corpus conservé</h2><p>Les modules généraux restent disponibles pour apprendre, mais les blancs Culture générale n’utilisent plus leur ancien quota arbitraire.</p></div></div>'+
      state.modules.map(m=>'<div class="stat-line"><span>Module '+m.id+' · '+esc(m.short||m.title)+'</span><b>'+num(m.question_count)+' Q</b></div>').join('')+
    '</div></div></section>'+
    '<section class="section"><div class="card"><div class="section-head"><div><h2>Provenance réellement récupérée</h2><p>Les observations d’annales restent séparées des questions activées. <b>FACT_CHECKED</b> = correction recoupée indépendamment ; <b>ARCHIVE_ONLY</b> = provenance d’annale conservée mais correction encore à recouper.</p></div></div><div class="year-provenance">'+
      Object.entries(prov.observed_by_year||{}).sort((a,b)=>Number(b[0])-Number(a[0])).map(([year,n])=>'<div class="source-line"><span><b>'+esc(year)+'</b> · '+num(n)+' notion(s) observée(s)</span><em>'+num((prov.active_recovered_by_year||{})[year]||0)+' active(s)</em></div>').join('')+
    '</div></div></section>'
}
async function renderUpdates(){
  const [u,safety]=await Promise.all([api('/api/update/status'),api('/api/system/update-safety')]),phase=u.progress?.phase||'IDLE',per=Number(u.progress?.percent||0),waiting=phase==='WAITING_FOR_IDLE';
  const reason=safety.reason==='ACTIVE_SESSION'?'session de questions active':safety.reason==='ACTIVE_STUDY_DAY'?'journée de travail active':'aucun travail bloquant';
  qs('#viewHost').innerHTML='<div class="grid two"><div class="admin-card"><div class="eyebrow">MISE À JOUR AUTONOME</div><h3>'+esc(u.active_version||state.status.build)+'</h3><div class="setting-row"><span>Agent résident</span><b>'+(u.installed?'installé':'non installé')+'</b></div><div class="setting-row"><span>Phase</span><b>'+esc(phase)+'</b></div><div class="setting-row"><span>Activation autorisée maintenant</span><b>'+(safety.safe_to_activate?'oui':'non · '+esc(reason))+'</b></div><div class="setting-row"><span>Version candidate préparée</span><b>'+esc(u.progress?.target_version||u.agent?.pending_activation||'—')+'</b></div><div class="setting-row"><span>Rollback</span><b>'+(u.rollback_available?'disponible':'aucun')+'</b></div>'+progressBar(per,per===100?'good':waiting?'warn':'')+(waiting?'<div class="lesson-note" style="margin-top:12px"><b>Mise à jour prête, travail protégé</b><p>Le téléchargement, les SHA, le self-test et le préflight peuvent être faits en arrière-plan. L’activation attend une pause sûre au lieu de fermer la session.</p></div>':'')+'<button class="btn secondary small" id="updateNow" style="margin-top:13px">Vérifier maintenant</button></div><div class="admin-card"><div class="eyebrow">PIPELINE DE PROMOTION</div><h3>Sans Desktop Commander</h3><p style="color:var(--muted);font-size:12px;line-height:1.65">Manifest SHA-256 → téléchargement → staging A/B → syntaxe → audit corpus → audit UI → runtime → contre-audit profond → préflight isolé → attente d’un point sûr → activation → health check → rollback automatique.</p><div class="setting-row"><span>Données élève</span><b>SQLite séparé du code</b></div><div class="setting-row"><span>Contrôle de session</span><b>activation différée</b></div><div class="setting-row"><span>Fréquence agent</span><b>toutes les 30 min + demande manuelle</b></div></div></div>';
  qs('#updateNow').onclick=async()=>{await api('/api/update/request',{method:'POST'});toast('Vérification demandée','L’agent autonome télécharge et contrôle sans interrompre le travail.')}
}
function renderSettings(){
  const pwaReady=localStorage.getItem('exc2_pwa_ready')==='1';
  qs('#viewHost').innerHTML=
    '<div class="grid two settings-grid">'+
      '<div class="admin-card"><div class="eyebrow">APPARENCE & ERGONOMIE</div><h3>Interface</h3>'+
        '<div class="setting-row"><span>Thème</span><button class="btn secondary small" id="setTheme">'+(state.theme==='dark'?'Passer en clair':'Passer en sombre')+'</button></div>'+
        '<div class="setting-row"><span>Navigation</span><button class="btn secondary small" id="setRail">'+(state.railCollapsed?'Déployer la barre':'Réduire la barre')+'</button></div>'+
        '<div class="setting-row"><span>Densité</span><button class="btn secondary small" id="setDensity">'+(state.density==='compact'?'Mode confortable':'Mode compact')+'</button></div>'+
        '<div class="setting-row"><span>Taille du texte</span><button class="btn secondary small" id="setTextScale">'+(state.textScale==='large'?'Taille normale':'Texte agrandi')+'</button></div>'+
        '<div class="setting-row"><span>Animations</span><button class="btn secondary small" id="setMotion">'+(state.reducedMotion?'Réactiver':'Réduire')+'</button></div>'+
      '</div>'+
      '<div class="admin-card"><div class="eyebrow">JOURNÉE D’ÉTUDE</div><h3>Préférences de travail</h3>'+
        '<div class="setting-row"><span>Durée préférée</span><select class="field setting-select" id="setDayHours">'+[2,4,6,8].map(h=>'<option value="'+h+'" '+(state.defaultDayHours===h?'selected':'')+'>'+h+' h</option>').join('')+'</select></div>'+
        '<div class="setting-row"><span>Reprise après fermeture</span><b>automatique</b></div>'+
        '<div class="setting-row"><span>Sauvegarde locale</span><b>session + journée</b></div>'+
        '<div class="setting-row"><span>Activation d’une mise à jour</span><b>prioritaire · checkpoint puis reprise</b></div>'+
        '<button class="btn secondary small" id="openStudyDay" style="margin-top:13px">Ouvrir la journée d’étude</button>'+
      '</div>'+
      '<div class="admin-card"><div class="eyebrow">AUTONOMIE & SYNCHRONISATION</div><h3>Fonctionnement sans surveillance</h3>'+
        '<div class="setting-row"><span>Synchronisation navigateur</span><b>toutes les 15 s</b></div>'+
        '<div class="setting-row"><span>Pack hors ligne</span><b>'+(pwaReady?'prêt':'initialisation')+'</b></div>'+
        '<div class="setting-row"><span>Recherche de mise à jour</span><b>à l’ouverture + toutes les 2 min</b></div>'+
        '<div class="setting-row"><span>Desktop Commander</span><b>non requis</b></div>'+
        '<div class="hero-actions"><button class="btn secondary small" id="openConnection">Connexion & synchro</button><button class="btn secondary small" id="openUpdates">Mise à jour</button></div>'+
      '</div>'+
      '<div class="admin-card"><div class="eyebrow">DIAGNOSTIC LOCAL</div><h3>Ressources & identité</h3>'+
        '<div class="setting-row"><span>Build</span><b>'+esc(state.status?.build||'—')+'</b></div>'+
        '<div class="setting-row"><span>RAM Study Hub</span><b>'+num(state.status?.resources?.rss_mb)+' Mo</b></div>'+
        '<div class="setting-row"><span>Questions chargées</span><b>'+num(state.status?.questions_loaded)+'</b></div>'+
        '<div class="setting-row"><span>Notions distinctes</span><b>'+num(state.status?.knowledge_units_loaded)+'</b></div>'+
        '<p class="settings-note">Les préférences d’interface sont locales à cet appareil. Les données pédagogiques restent dans SQLite, séparées du code et des slots de mise à jour.</p>'+
      '</div>'+
    '</div>';
  qs('#setTheme').onclick=()=>{state.theme=state.theme==='dark'?'light':'dark';localStorage.setItem('exc2_theme',state.theme);applyTheme();renderSettings()};
  qs('#setRail').onclick=()=>{state.railCollapsed=!state.railCollapsed;localStorage.setItem('exc2_rail',state.railCollapsed?'1':'0');applyTheme();renderSettings()};
  qs('#setDensity').onclick=()=>{state.density=state.density==='compact'?'comfortable':'compact';localStorage.setItem('exc2_density',state.density);applyTheme();renderSettings()};
  qs('#setTextScale').onclick=()=>{state.textScale=state.textScale==='large'?'normal':'large';localStorage.setItem('exc2_text_scale',state.textScale);applyTheme();renderSettings()};
  qs('#setMotion').onclick=()=>{state.reducedMotion=!state.reducedMotion;localStorage.setItem('exc2_reduced_motion',state.reducedMotion?'1':'0');applyTheme();renderSettings()};
  qs('#setDayHours').onchange=e=>{state.defaultDayHours=Number(e.target.value)||6;localStorage.setItem('exc2_day_hours',String(state.defaultDayHours));toast('Préférence enregistrée',state.defaultDayHours+' h sera mise en avant pour la prochaine journée.','day-hours')};
  qs('#openStudyDay').onclick=()=>go('home','day');
  qs('#openConnection').onclick=()=>go('admin','connection');
  qs('#openUpdates').onclick=()=>go('admin','updates')
}

async function renderDay(){
  clearInterval(state.dayTicker);state.dayTicker=null;
  try{
    const remote=(await api('/api/day/current')).day||null;state.day=remote;persistDay()
  }catch(e){
    if(e.status)throw e;
    if(!state.day)try{state.day=JSON.parse(localStorage.getItem('exc2_active_day')||'null')}catch{}
    if(!state.day)throw e;setNetwork(false)
  }
  if(!state.day){
    exitImmersive();
    qs('#viewHost').innerHTML='<section class="hero"><div class="eyebrow">JOURNÉE DE TRAVAIL GUIDÉE</div><h2>Choisir une durée, puis suivre le parcours sans se demander quoi faire ensuite.</h2><p>Les journées sont découpées en blocs focus de 55 minutes, séparés par de vraies pauses. Chaque bloc alterne fiches d’enseignement et validation interactive.</p></section><section class="section"><div class="day-picker">'+[2,4,6,8].map(h=>'<button class="day-option '+(state.defaultDayHours===h?'preferred':'')+'" data-hours="'+h+'"><b>'+h+' h'+(state.defaultDayHours===h?' · préférée':'')+'</b><span>'+(h===2?'55 min · pause 10 min · 55 min':h<=4?'Blocs de 55 min + pauses guidées':h<=6?'Journée complète · fiches + tests + révisions':'Intensive · alternance focus / pause / consolidation')+'</span></button>').join('')+'</div></section><section class="section"><div class="grid three">'+actionCard('1','Comprendre','Une fiche d’enseignement complète, structurée et guidée.','Explorer','learn','modules')+actionCard('2','Valider','Chaque fiche se termine par une correction interactive et un score.','S’entraîner','train','adaptive')+actionCard('3','Continuer','Le planning montre les résultats et indique précisément l’étape suivante.','Voir les révisions','review','due')+'</div></section>';
    qsa('[data-hours]').forEach(b=>b.onclick=()=>createDay(Number(b.dataset.hours)));bindSpaceLinks();return
  }
  enterImmersive('day');
  const d=state.day,idx=Number(d.current_index||0),cur=d.blocks[idx],done=d.blocks.filter(x=>x.state==='DONE').length,pr=Math.round(done/Math.max(1,d.blocks.length)*100),paused=d.state==='PAUSED',next=d.blocks[idx+1];
  qs('#viewHost').innerHTML='<div class="focus-workspace workday-workspace '+(paused?'is-paused':'')+'"><header class="focus-topbar"><button class="btn ghost small" id="exitDay">← Tableau de bord</button><div class="focus-title"><span class="eyebrow">JOURNÉE GUIDÉE</span><b>'+d.duration_hours+' h · '+done+' / '+d.blocks.length+' étapes terminées</b></div><div class="focus-meta"><button class="btn secondary small" id="pauseDay">'+(paused?'▶ Reprendre':'Ⅱ Pause')+'</button><span class="pill '+(paused?'warn':'good')+'">'+esc(paused?'EN PAUSE':'EN COURS')+'</span></div></header><div class="workday-grid"><aside class="workday-plan"><div class="workday-progress"><div><span>Progression globale</span><b>'+pr+' %</b></div>'+progressBar(pr,'good')+'</div><div class="workday-timeline">'+dayTimelineHtml(d,idx)+'</div></aside><main class="workday-main"><div class="eyebrow">'+esc(cur?.phase_label||'BLOC ACTUEL')+' · ÉTAPE '+(idx+1)+' / '+d.blocks.length+'</div><h1>'+esc(cur?.title||'Journée terminée')+'</h1><p class="workday-lead">'+esc(cur?blockInstruction(cur):'Tous les blocs sont terminés. Consulte le bilan puis ferme la journée.')+'</p>'+(paused?'<div class="paused-banner"><b>Journée en pause</b><span>Tu peux fermer le navigateur. La progression reste enregistrée.</span><button class="btn good" id="resumeDayInside">Reprendre</button></div>':'')+dayActionHtml(cur,paused)+'<section class="workday-method"><h3>Comment travailler cette étape</h3><div class="method-grid">'+blockMethod(cur).map((x,i)=>'<div><span>'+String(i+1).padStart(2,'0')+'</span><p>'+esc(x)+'</p></div>').join('')+'</div></section></main><aside class="workday-side"><div class="eyebrow">CONTRÔLE DE SESSION</div><div class="session-stat"><span>État</span><b>'+esc(d.state)+'</b></div><div class="session-stat"><span>Étape</span><b>'+(idx+1)+' / '+d.blocks.length+'</b></div><div class="session-stat"><span>Durée</span><b>'+num(cur?.minutes||0)+' min</b></div>'+(cur?.phase_label?'<div class="session-stat"><span>Bloc</span><b>'+esc(cur.phase_label)+'</b></div>':'')+(Number.isFinite(dayScore(cur))?'<div class="session-stat"><span>Résultat</span><b>'+Math.round(dayScore(cur))+' %</b></div>':'')+'<div class="next-block"><span>Ensuite</span><b>'+esc(next?.title||'Bilan de journée')+'</b><small>'+esc(next?dayKind(next.kind):'Fin')+'</small></div><p class="session-tip">Le score de chaque validation reste attaché à la fiche correspondante. Les erreurs alimentent automatiquement les révisions.</p></aside></div></div>';
  qsa('[data-block]').forEach(b=>b.onclick=()=>{if(!paused)updateDay('move',Number(b.dataset.block))});
  qs('#launchBlock')?.addEventListener('click',()=>launchBlock(cur));
  qs('#completeBlock')?.addEventListener('click',()=>{if(cur?.kind==='lesson'&&!Number.isFinite(dayScore(cur))&&!confirm('Cette fiche n’a pas encore de mini-test enregistré. La valider quand même ?'))return;updateDay('complete_block',idx)});
  qs('#pauseDay')?.addEventListener('click',()=>updateDay(paused?'resume':'pause',idx));qs('#resumeDayInside')?.addEventListener('click',()=>updateDay('resume',idx));
  qs('#exitDay').onclick=async()=>{if(d.state==='ACTIVE')await updateDay('pause',idx);exitImmersive();go('home','today')};
  startBreakTicker(cur)
}
function dayKind(k){return ({lesson:'Apprentissage',break:'Pause',recall:'Rappel actif',quiz:'Questions ciblées',review:'Révision',mixed:'Série mixte'})[k]||k}
function blockInstruction(b){
  if(!b)return '';
  return ({lesson:'Lis la leçon en cherchant les liens, puis passe au rappel sans support.',recall:'Ferme le cours et restitue les idées clés avant toute révélation.',quiz:'Réponds sans support. Les erreurs seront réinjectées dans les révisions.',review:'Travaille uniquement les notions arrivées à échéance ou fragiles.',mixed:'Mélange les domaines pour vérifier la robustesse sous changement de contexte.',break:'Pause réelle : éloigne-toi de l’écran et reprends seulement à la fin du bloc.'})[b.kind]||'Suis les étapes du bloc puis valide-le.'
}
function blockMethod(b){
  if(!b)return ['Consulter le bilan.'];
  if(b.kind==='lesson')return ['Comprendre le thème avant de mémoriser.','Masquer les repères et tenter de les restituer.','Faire le rappel actif.','Terminer par le mini-test ciblé.'];
  if(b.kind==='recall')return ['Répondre sans rouvrir la leçon.','Noter les hésitations.','Vérifier après la tentative.','Revoir uniquement ce qui a échoué.'];
  if(b.kind==='quiz'||b.kind==='mixed'||b.kind==='review')return ['Répondre en conditions réelles.','Utiliser « Je ne sais pas » plutôt que deviner au hasard.','Corriger immédiatement.','Laisser le moteur programmer la prochaine révision.'];
  return ['Quitter l’écran.','Boire ou marcher quelques minutes.','Ne pas réviser pendant la pause.','Reprendre seulement quand le bloc suivant commence.']
}
async function createDay(hours){state.day=await api('/api/day/start',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({hours,start_module:2})});persistDay();renderDay()}
function applyDayLocal(action,index,payload={}){
  const d=state.day;if(!d)return null;
  const blocks=d.blocks||[],idx=Math.max(0,Math.min(blocks.length-1,Number(index??d.current_index??0)));
  if(action==='pause')d.state='PAUSED';
  else if(action==='resume')d.state='ACTIVE';
  else if(action==='start_block'){const b=blocks[idx];if(b&&b.state!=='DONE'){b.state='ACTIVE';b.started_at=b.started_at||new Date().toISOString()}d.state='ACTIVE';d.current_index=idx}
  else if(action==='move')d.current_index=idx;
  else if(action==='record_result'){
    const b=blocks[idx];if(b){
      const score=Math.max(0,Math.min(100,Number(payload.score||0)));b.score=score;b.validation_score=score;b.session_id=payload.session_id||b.session_id||null;
      b.correct=Math.max(0,Number(payload.correct||0));b.wrong=Math.max(0,Number(payload.wrong||0));b.blank=Math.max(0,Number(payload.blank||0));b.last_result_at=new Date().toISOString()
    }
  }else if(action==='complete_block'){
    const b=blocks[idx];if(b&&b.state!=='DONE'){b.state='DONE';b.started_at=b.started_at||new Date().toISOString();b.completed_at=new Date().toISOString()}
    const next=blocks.findIndex((x,i)=>i>idx&&x.state!=='DONE');
    if(blocks.every(x=>x.state==='DONE'))d.state='FINISHED';
    else d.current_index=next>=0?next:Math.min(blocks.length-1,idx+1)
  }
  d.updated_at=new Date().toISOString();persistDay();return d
}
async function updateDay(action,index){
  const idx=Number(index??state.day.current_index),body={action,current_index:idx,expected_index:idx},url='/api/day/'+state.day.id+'/update';
  try{state.day=await api(url,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});persistDay()}
  catch(e){
    if(e.status)throw e;
    applyDayLocal(action,idx);
    const key=action==='complete_block'?url+'|complete|'+idx:url+'|state';
    queueWrite(url,body,key);setNetwork(false)
  }
  renderDay()
}
async function recordDayResult(session,ret){
  const target=ret?.type==='day'?ret:(ret?.type==='lesson'&&ret.return_target?.type==='day'?ret.return_target:null);
  if(!target||!session)return;
  const answers=session.answers||{};let correct=0,wrong=0,blank=0;
  for(const q of session.questions||[]){const a=answers[q.id];if(!a||Number(a.selected)<0||a.unsure)blank++;else if(a.correct)correct++;else wrong++}
  const payload={action:'record_result',current_index:Number(target.block_index??0),expected_index:Number(target.block_index??0),session_id:session.id,score:Number(session.score||0),correct,wrong,blank};
  const url='/api/day/'+target.day_id+'/update';
  try{
    if(state.day?.id===target.day_id){state.day=await api(url,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(payload)});persistDay()}
    else await api(url,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(payload)})
  }catch(e){
    if(!e.status&&state.day?.id===target.day_id){applyDayLocal('record_result',Number(target.block_index||0),payload);queueWrite(url,payload,url+'|result|'+payload.current_index)}
  }
}
function dayScore(b){
  const raw=b?.validation_score??b?.score;return raw===null||raw===undefined||raw===''?null:Number(raw)
}
function dayTimelineHtml(d,idx){
  let previous=null;
  return (d.blocks||[]).map((b,i)=>{
    const phase=b.phase_label||'',head=phase&&phase!==previous?'<div class="timeline-phase"><span>'+esc(phase)+'</span></div>':'';
    previous=phase||previous;
    const score=dayScore(b),result=Number.isFinite(score)?'<span class="block-score '+(score>=70?'good':score>=50?'warn':'bad')+'">'+Math.round(score)+' %</span>':'';
    return head+'<button class="workday-block '+(i===idx?'active ':'')+(b.state==='DONE'?'done ':'')+(b.state==='ACTIVE'?'running':'')+'" data-block="'+i+'"><span class="block-index">'+(i+1)+'</span><div><b>'+esc(b.title)+'</b><small>'+b.minutes+' min · '+dayKind(b.kind)+(b.module?' · M'+b.module:'')+'</small>'+result+'</div><em>'+(b.state==='DONE'?'✓':i===idx?'▶':'○')+'</em></button>'
  }).join('')
}
function dayActionHtml(cur,paused){
  if(!cur)return '';
  if(cur.kind==='break'){
    const started=cur.state==='ACTIVE';
    return '<div class="workday-actions"><button class="btn good" id="launchBlock" '+(paused||started?'disabled':'')+'>'+(started?'Pause en cours…':'Commencer la pause')+'</button><button class="btn secondary" id="completeBlock" '+(paused?'disabled':'')+'>'+(started?'Terminer la pause':'Passer la pause')+'</button></div>'+(started?'<div class="break-clock"><span>Temps conseillé restant</span><b id="breakTimer">—</b><small>La reprise reste manuelle : le système ne force jamais le passage au bloc suivant.</small></div>':'')
  }
  const score=dayScore(cur);
  const secondary=cur.kind==='lesson'&&!Number.isFinite(score)?'Valider sans mini-test':'Marquer terminé';
  return '<div class="workday-actions"><button class="btn good" id="launchBlock" '+(paused?'disabled':'')+'>Ouvrir ce bloc</button><button class="btn secondary" id="completeBlock" '+(paused?'disabled':'')+'>'+secondary+'</button></div>'+(Number.isFinite(score)?'<div class="block-outcome"><span>Dernière validation</span><b>'+Math.round(score)+' %</b><small>'+num(cur.correct||0)+' correctes · '+num(cur.wrong||0)+' erreurs · '+num(cur.blank||0)+' sans réponse</small></div>':'')
}
function startBreakTicker(cur){
  clearInterval(state.dayTicker);state.dayTicker=null;
  if(!cur||cur.kind!=='break'||cur.state!=='ACTIVE'||!cur.started_at)return;
  const end=new Date(cur.started_at).getTime()+Number(cur.minutes||10)*60000;
  const tick=()=>{const el=qs('#breakTimer');if(!el)return;const sec=Math.max(0,Math.ceil((end-Date.now())/1000));el.textContent=sec>0?time(sec):'Pause terminée';if(sec<=0){clearInterval(state.dayTicker);state.dayTicker=null}};
  tick();state.dayTicker=setInterval(tick,1000)
}

async function launchBlock(b){
  if(!b)return;await updateDay('start_block',state.day.current_index);
  if(b.kind==='break'){toast('Pause commencée','Éloigne-toi de l’écran. Reviens quand le compteur est terminé, puis confirme la reprise.','day-break');return}
  if((b.kind==='lesson'||b.kind==='recall')&&b.lesson_id)return openLesson(b.module||2,b.lesson_id,{type:'day',day_id:state.day.id,block_index:Number(state.day.current_index)});
  if(b.kind==='lesson'||b.kind==='recall'){exitImmersive();return openModule(b.module||2)}
  if(b.kind==='quiz'){state.sessionReturn={type:'day',day_id:state.day.id,block_index:Number(state.day.current_index),complete_on_return:true};return startSession({module:b.module||2,mode:'module',count:Math.max(8,Math.min(25,Math.round(b.minutes*.8))),duration_seconds:b.minutes*60})}
  if(b.kind==='review'){state.sessionReturn={type:'day',day_id:state.day.id,block_index:Number(state.day.current_index),complete_on_return:true};return startSession({module:0,mode:'review',count:Math.max(8,Math.min(25,Math.round(b.minutes*.8))),duration_seconds:b.minutes*60})}
  if(b.kind==='mixed'){state.sessionReturn={type:'day',day_id:state.day.id,block_index:Number(state.day.current_index),complete_on_return:true};return startSession({module:0,mode:'mixed',count:Math.max(8,Math.min(30,Math.round(b.minutes*.8))),duration_seconds:b.minutes*60})}
}
async function startSession(opts){
  try{
    state.session=await api('/api/session/start',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(opts)});
    persistSession();state.currentQuestionStartedAt=Date.now();startQuestionClock({force:true});enterImmersive('session');
    if(state.session.resumed)toast('Session reprise','Une session existante était encore active. Aucun doublon n’a été créé.','session-resumed');
    renderSession()
  }catch(e){toast('Session impossible',e.message)}
}
async function restoreActiveSession(){
  const id=state.status?.active_session_id;if(!id)return false;
  try{
    const s=await api('/api/session/'+encodeURIComponent(id));
    if(!s||!['ACTIVE','PAUSED'].includes(s.state))return false;
    state.session=s;persistSession();state.currentQuestionStartedAt=Date.now();startQuestionClock();enterImmersive('session');renderSession();return true
  }catch{return false}
}
function answerState(q){return state.session?.answers?.[q.id]||{}}
async function saveAnswer(q,selected,extra={}){
  const s=state.session;
  const elapsed=Math.max(0,Number(extra.elapsed_ms??(Date.now()-state.currentQuestionStartedAt)));
  const timedOut=Boolean(extra.timed_out)||elapsed>=QUESTION_LIMIT_MS;
  const effectiveSelected=timedOut?-1:selected;
  const a={question_id:q.id,selected:effectiveSelected,unsure:effectiveSelected<0,marked:Boolean(answerState(q).marked),confidence:0,elapsed_ms:timedOut?QUESTION_LIMIT_MS:elapsed,timed_out:timedOut};
  let result=null;
  try{result=await api('/api/session/'+s.id+'/answer',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(a)})}
  catch(e){if(!e.status)queueWrite('/api/session/'+s.id+'/answer',a);else throw e}
  const feedback=result?.feedback||null;
  s.answers[q.id]={...(s.answers[q.id]||{}),...a,...(feedback?{correct:Boolean(feedback.correct),correct_index:Number(feedback.correct_index),explanation:feedback.explanation||'',answer:feedback.answer||''}:{})};
  clearQuestionClock();s.question_deadline_ms=0;s.question_remaining_ms=0;persistSession();state.currentQuestionStartedAt=Date.now();return feedback
}
async function setSessionState(next,{rerender=true}={}){
  const s=state.session;if(!s||!['ACTIVE','PAUSED'].includes(s.state))return;
  const body={position:Number(s.position||0),remaining_seconds:Number(s.remaining_seconds||0),state:next};let result=null;
  try{result=await api('/api/session/'+s.id+'/progress',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)})}catch(e){if(!e.status)queueWrite('/api/session/'+s.id+'/progress',body);else{toast('État non enregistré',e.message,'session-state');return}}
  s.state=next;
  if(result){s.question_deadline_ms=Number(result.question_deadline_ms||0);s.question_remaining_ms=Number(result.question_remaining_ms||0);s.question_started_at_ms=Number(result.question_started_at_ms||0)}
  persistSession();state.currentQuestionStartedAt=Date.now();if(rerender)renderSession()
}
async function toggleSessionPause(){
  const s=state.session;if(!s)return;
  const pausing=s.state==='ACTIVE';if(pausing)pauseQuestionClock();
  await setSessionState(pausing?'PAUSED':'ACTIVE');
  if(!pausing)resumeQuestionClock();
  toast(s.state==='PAUSED'?'Session en pause':'Session reprise',s.state==='PAUSED'?'Les chronomètres sont arrêtés. Tu peux revenir plus tard.':'40 secondes repartent sur la question en cours.','session-pause')
}
async function leaveSession(){
  const s=state.session;if(s?.state==='ACTIVE'){pauseQuestionClock();await setSessionState('PAUSED',{rerender:false})};
  clearInterval(state.ticker);exitImmersive();const r=state.sessionReturn;state.session=null;state.status=null;
  if(r?.type==='lesson')return openLesson(r.module,r.id,r.return_target||null);
  if(r?.type==='day')return go('home','day');
  return go('home','today')
}
function renderSession(){
  const s=state.session;if(!s)return;enterImmersive('session');
  const i=Math.max(0,Math.min(s.questions.length-1,Number(s.position||0))),q=s.questions[i],a=answerState(q),answered=Object.keys(s.answers||{}).length,paused=s.state==='PAUSED';
  const feedbackMode=s.mode!=='mock',revealed=feedbackMode&&a.correct_index!==undefined&&a.correct_index!==null,locked=a.selected!==undefined;
  if(!paused&&!locked)startQuestionClock();
  const questionRemaining=locked?0:questionSecondsLeft();
  const answeredIds=new Set(Object.keys(s.answers||{}));
  const answerButtons=q.choices.map((x,n)=>{
    const selected=Number(a.selected)===n,correct=revealed&&Number(a.correct_index)===n,wrong=revealed&&selected&&!a.correct;
    return '<button '+(paused||locked?'disabled ':'')+'class="answer '+(selected?'selected ':'')+(correct?'feedback-correct ':'')+(wrong?'feedback-wrong ':'')+'" data-answer="'+n+'"><span class="answer-key">'+String.fromCharCode(65+n)+'</span><span>'+esc(x)+'</span></button>'
  }).join('');
  const feedback=revealed?'<div class="answer-feedback '+(a.correct?'good':'bad')+'"><div><b>'+(a.correct?'✓ Bonne réponse':'✕ À corriger')+'</b><span>'+(a.correct?'Tu as choisi la bonne réponse.':'La bonne réponse est en vert ; ton choix reste en rouge.')+'</span></div>'+(a.explanation?'<p>'+esc(a.explanation)+'</p>':'')+'</div>':(feedbackMode&&a.selected!==undefined?'<div class="answer-feedback warn"><div><b>Correction en attente</b><span>La réponse est sauvegardée localement. Tu peux continuer ; la correction sera réconciliée dès la reconnexion.</span></div></div>':'');
  qs('#viewHost').innerHTML='<div class="focus-workspace session-workspace '+(paused?'is-paused':'')+'"><header class="focus-topbar"><button class="btn ghost small" id="exitSession">← Retour</button><div class="focus-title"><span class="eyebrow">SESSION · '+esc(String(s.mode||'').toUpperCase())+'</span><b>'+esc(s.mode==='mock'?'Examen blanc':s.mode==='lesson'?'Mini-test de fiche':'Entraînement interactif')+'</b></div><div class="focus-meta"><button class="btn secondary small" id="pauseSession">'+(paused?'▶ Reprendre':'Ⅱ Pause')+'</button><div class="focus-timer question-clock '+(!locked&&questionRemaining<=10?'urgent':'')+'"><span>Question · 40 s</span><b id="questionTimerValue">'+(locked?'Répondu':time(questionRemaining))+'</b><small id="timerValue">Session '+time(s.remaining_seconds)+'</small></div></div></header><div class="session-focus-grid"><aside class="question-map"><div class="eyebrow">QUESTIONS</div><div class="question-map-grid">'+s.questions.map((z,n)=>{const zA=answerState(z),known=zA.correct_index!==undefined&&zA.correct_index!==null;return '<button data-jump="'+n+'" class="'+(n===i?'active ':'')+(answeredIds.has(z.id)?'done ':'')+(known?(zA.correct?'map-correct':'map-wrong'):'')+'">'+(n+1)+'</button>'}).join('')+'</div><div class="question-map-foot"><span><i class="dot done"></i>'+answered+' répondues</span><span><i class="dot"></i>'+(s.total-answered)+' restantes</span></div></aside><main class="focus-question"><div class="question-top"><span class="pill">'+esc(q.domain)+' · '+esc(q.subdomain)+'</span><span class="counter">Question '+(i+1)+' / '+s.total+'</span></div><div class="question-progress">'+progressBar(Math.round((i+1)/Math.max(1,s.total)*100),'good')+'</div><h2>'+esc(q.prompt)+'</h2><div class="answers">'+answerButtons+'</div>'+feedback+(paused?'<div class="paused-banner"><b>Session en pause</b><span>Le temps est arrêté. Reprends quand tu es prête.</span><button class="btn good" id="resumeInside">Reprendre la session</button></div>':'')+'<div class="question-nav"><button class="btn ghost" id="prevQ" '+(i===0||paused||!locked?'disabled':'')+'>← Précédente</button><button class="btn secondary" id="blankQ" '+(paused||locked?'disabled':'')+'>Je ne sais pas</button>'+(i===s.total-1?'<button class="btn good" id="finishSession" '+(paused||!locked?'disabled':'')+'>Terminer et corriger</button>':'<button class="btn" id="nextQ" '+(paused||!locked?'disabled':'')+'>Continuer →</button>')+'</div></main><aside class="session-focus-side"><div class="session-stat"><span>Progression</span><b>'+answered+' / '+s.total+'</b>'+progressBar(Math.round(answered/Math.max(1,s.total)*100),'good')+'</div><div class="session-stat"><span>Mode</span><b>'+(feedbackMode?'Correction immédiate':'Examen sans aide')+'</b></div><div class="session-stat"><span>Module</span><b>'+(s.module||'Mix')+'</b></div><div class="session-stat"><span>Synchronisation</span><b>'+(state.offline.length?num(state.offline.length)+' en attente':'À jour')+'</b></div><p class="session-tip">'+(feedbackMode?'Une réponse verrouille la question, affiche le bon choix et conserve l’erreur pour la révision.':'Aucune bonne réponse n’est révélée avant la fin de l’examen blanc.')+'</p></aside></div></div>';
  setInspector('');
  if(!paused&&!locked)qsa('[data-answer]').forEach(b=>b.onclick=async()=>{await saveAnswer(q,Number(b.dataset.answer));renderSession()});
  qsa('[data-jump]').forEach(b=>b.onclick=()=>{const target=Number(b.dataset.jump);if(paused)return;if(!locked&&target!==i){toast('Question en cours','Réponds ou attends la fin des 40 secondes avant de changer de question.','question-lock');return}moveSession(target)});
  qs('#prevQ').onclick=()=>moveSession(i-1);
  qs('#blankQ').onclick=async()=>{await saveAnswer(q,-1);if(i<s.total-1)await moveSession(i+1);else await finishSession()};
  qs('#nextQ')?.addEventListener('click',()=>moveSession(i+1));qs('#finishSession')?.addEventListener('click',finishSession);qs('#exitSession').onclick=leaveSession;
  qs('#pauseSession').onclick=toggleSessionPause;qs('#resumeInside')?.addEventListener('click',toggleSessionPause);startTicker()
}
async function moveSession(pos){
  const s=state.session;if(!s||s.state!=='ACTIVE')return;
  const target=Math.max(0,Math.min(s.total-1,pos)),previous=Number(s.position||0);if(target===previous){renderSession();return}
  const body={position:target,remaining_seconds:s.remaining_seconds,state:'ACTIVE'};let result=null;
  try{result=await api('/api/session/'+s.id+'/progress',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)})}
  catch(e){
    if(!e.status){queueWrite('/api/session/'+s.id+'/progress',body)}
    else{toast('Passage impossible',e.message==='QUESTION_NOT_ANSWERED'?'Réponds à la question ou attends les 40 secondes.':e.message,'progress-http');return}
  }
  s.position=target;
  if(result){s.question_deadline_ms=Number(result.question_deadline_ms||0);s.question_remaining_ms=Number(result.question_remaining_ms||QUESTION_LIMIT_MS);s.question_started_at_ms=Number(result.question_started_at_ms||Date.now())}
  else{s.question_deadline_ms=0;s.question_remaining_ms=QUESTION_LIMIT_MS;s.question_started_at_ms=Date.now()}
  persistSession();state.currentQuestionStartedAt=Date.now();clearQuestionClock();startQuestionClock();renderSession()
}
async function expireCurrentQuestion(){
  if(state.questionTimeoutBusy)return;
  const s=state.session,q=currentQuestion();if(!s||!q||s.state!=='ACTIVE'||s.answers?.[q.id]?.selected!==undefined)return;
  state.questionTimeoutBusy=true;clearInterval(state.ticker);
  try{
    await saveAnswer(q,-1,{timed_out:true,elapsed_ms:QUESTION_LIMIT_MS});
    toast('40 secondes écoulées','Question comptée incorrecte. Passage automatique à la suivante.','question-timeout');
    const i=Number(s.position||0);
    if(i<s.total-1)await moveSession(i+1);else await finishSession()
  }finally{state.questionTimeoutBusy=false}
}
function paintQuestionClock(){
  const q=currentQuestion(),answered=q&&state.session?.answers?.[q.id]?.selected!==undefined,qLeft=answered?0:questionSecondsLeft(),qEl=qs('#questionTimerValue'),box=qEl?.closest('.question-clock'),sessionEl=qs('#timerValue');
  if(qEl)qEl.textContent=answered?'Répondu':time(qLeft);if(sessionEl)sessionEl.textContent='Budget '+time(state.session?.remaining_seconds||0);
  if(box)box.classList.toggle('urgent',!answered&&qLeft<=10)
}
function startTicker(){
  clearInterval(state.ticker);if(!state.session||state.session.state!=='ACTIVE')return;startQuestionClock();paintQuestionClock();
  state.ticker=setInterval(async()=>{
    if(!state.session||state.session.state!=='ACTIVE'||state.questionTimeoutBusy)return;
    const q=currentQuestion(),answered=q&&state.session.answers?.[q.id]?.selected!==undefined;
    if(!answered)state.session.remaining_seconds=Math.max(0,Number(state.session.remaining_seconds||0)-1);
    if(state.session.remaining_seconds%5===0)persistSession();paintQuestionClock();
    if(!answered&&questionSecondsLeft()<=0){await expireCurrentQuestion();return}
  },1000)
}
async function finishSession(){
  const s=state.session,ans=s.questions.map(q=>{const a=(s.answers||{})[q.id]||{};return {question_id:q.id,selected:Number.isFinite(Number(a.selected))?Number(a.selected):-1,unsure:a.selected===undefined||Boolean(a.unsure)||Number(a.selected)<0,marked:Boolean(a.marked),confidence:0,elapsed_ms:Number(a.elapsed_ms||0)}});
  try{
    state.session=await api('/api/session/'+s.id+'/finish',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({answers_snapshot:ans})});
    localStorage.removeItem('exc2_active_session');state.offline=state.offline.filter(x=>!x.url.includes('/api/session/'+s.id+'/'));saveOffline();state.status=null;state.stats=null;state.coach=null;state.mastery=null;state.notebook=null;
    await recordDayResult(state.session,state.sessionReturn);renderResult()
  }catch(e){if(e.payload?.error==='INCOMPLETE_SYNC')toast('Correction suspendue',e.payload.received+' / '+e.payload.total+' réponses reçues. Rien n’est compté faux.','finish');else if(!e.status){persistSession();toast('Correction en attente','La session reste intacte. Reconnecte le serveur puis relance la correction.','finish-offline')}else toast('Correction impossible',e.message)}
}
function renderResult(){
  clearInterval(state.ticker);enterImmersive('session');const s=state.session,answers=s.answers||{};let good=0,bad=0,blank=0,totalMs=0;
  for(const q of s.questions){const a=answers[q.id];if(!a||Number(a.selected)<0||a.unsure)blank++;else if(a.correct)good++;else bad++;totalMs+=Number(a?.elapsed_ms||0)}
  const avg=(good+bad+blank)?Math.round(totalMs/(good+bad+blank)/1000):0,ret=state.sessionReturn;
  const returnLabel=ret?.type==='lesson'?(ret.return_target?.type==='day'?'Retour à la fiche · puis planning':'Retour à la fiche'):ret?.type==='day'?'Retour au planning':'';
  const ordered=[...s.questions].sort((qa,qb)=>{const a=answers[qa.id],b=answers[qb.id];const av=!a||Number(a.selected)<0||a.unsure?0:a.correct?2:1,bv=!b||Number(b.selected)<0||b.unsure?0:b.correct?2:1;return av-bv});
  const correctionCards=ordered.map(q=>{const i=s.questions.findIndex(x=>x.id===q.id),a=answers[q.id],status=!a||Number(a.selected)<0||a.unsure?'Sans réponse':a.correct?'Correct':'Incorrect',cls=status==='Correct'?'good':status==='Incorrect'?'bad':'warn';return '<div class="card correction-card '+cls+'"><div class="card-row"><span class="pill '+cls+'">Q'+(i+1)+' · '+status+'</span><span class="eyebrow">'+esc(q.domain)+'</span></div><h3 style="margin-top:10px">'+esc(q.prompt)+'</h3>'+(a&&Number(a.selected)>=0?'<p>Ta réponse : <b>'+esc(q.choices[Number(a.selected)]||'')+'</b></p>':'<p>Ta réponse : <b>Je ne sais pas</b></p>')+'<p>Bonne réponse : <b>'+esc(q.choices[q.answer])+'</b><br>'+esc(q.explanation||'')+'</p></div>'}).join('');
  qs('#viewHost').innerHTML='<div class="focus-workspace result-workspace"><header class="focus-topbar"><button class="btn ghost small" id="resultHome">← Quitter</button><div class="focus-title"><span class="eyebrow">SESSION TERMINÉE</span><b>Correction complète</b></div><div class="focus-meta"><span class="pill good">Résultat enregistré</span></div></header><main class="result-scroll"><section class="result-hero"><div><span class="eyebrow">SCORE</span><h2>'+pct(s.score)+'</h2><p>'+(bad+blank?num(bad+blank)+' point(s) à reprendre avant le prochain test.':'Aucune erreur sur cette série.')+'</p></div><div class="result-actions">'+(returnLabel?'<button class="btn good" id="resultReturn">'+esc(returnLabel)+'</button>':'')+'<button class="btn secondary" id="resultErrors">Mes erreurs programmées</button><button class="btn ghost" id="resultNew">Nouvelle série</button></div></section><div class="metric-grid">'+metric(good,'correctes')+metric(bad,'incorrectes')+metric(blank,'sans réponse')+metric(avg+' s','temps moyen')+metric(s.total,'questions')+'</div><section class="section"><div class="section-head"><div><h3>Correction de la série</h3><p>Les erreurs et absences de réponse sont placées en premier ; elles alimentent automatiquement les révisions.</p></div><span class="pill '+((bad+blank)===0?'good':'warn')+'">'+num(bad+blank)+' à revoir</span></div><div class="grid">'+correctionCards+'</div></section></main></div>';
  const leave=()=>{state.session=null;state.sessionReturn=null;exitImmersive();go('home','today')};
  qs('#resultHome').onclick=leave;qs('#resultNew').onclick=()=>{state.session=null;state.sessionReturn=null;exitImmersive();go('train','adaptive')};qs('#resultErrors').onclick=()=>{state.session=null;state.sessionReturn=null;exitImmersive();go('train','errors')};
  qs('#resultReturn')?.addEventListener('click',async()=>{const r=state.sessionReturn;state.session=null;state.sessionReturn=null;exitImmersive();if(r?.type==='lesson')return openLesson(r.module,r.id,r.return_target||null);if(r?.type==='day'&&r.complete_on_return&&state.day){await updateDay('complete_block',Number(r.block_index??state.day.current_index));return}go('home','day')})
}
function openCommands(){
  const p=qs('#commandPalette');p.classList.add('open');p.setAttribute('aria-hidden','false');qs('#commandInput').value='';drawCommands('');setTimeout(()=>qs('#commandInput').focus(),20)
}
function closeCommands(){qs('#commandPalette').classList.remove('open');qs('#commandPalette').setAttribute('aria-hidden','true')}
function commands(){
  const base=[
    ['Accueil','Vue du jour','home','today'],['Journée d’étude','Plan 2 à 8 h','home','day'],['Apprendre','Parcours et modules','learn','path'],['Fiches','Lire les notions','learn','cards'],['Entraînement adaptatif','Lancer une série','train','adaptive'],['Banque de questions','Explorer le corpus','train','bank'],['Mes erreurs','Corriger les lacunes','train','errors'],['Révisions','Rappels espacés','review','due'],['Examen blanc','Culture générale','exam','mock'],['Progression','Statistiques','progress','overview']
  ];if(state.me?.admin_available||state.me?.role==='ADMIN')base.push(['Administration',state.me?.role==='ADMIN'?'Accès et système':'Code requis','admin','access'],['Mise à jour','Updater autonome','admin','updates'],['Paramètres','Interface et données','admin','settings']);return base
}
function drawCommands(q){q=q.toLowerCase();const arr=commands().filter(x=>(x[0]+' '+x[1]).toLowerCase().includes(q));qs('#commandResults').innerHTML=arr.map((x,i)=>'<button class="command-item" data-command="'+i+'"><span><b>'+esc(x[0])+'</b><small> · '+esc(x[1])+'</small></span><small>Entrée</small></button>').join('');qsa('[data-command]').forEach((b,i)=>b.onclick=()=>{const x=arr[i];closeCommands();go(x[2],x[3])})}

function openOfflineModule(id){
  const pack=state.offlinePack,m=(pack?.modules||[]).find(x=>Number(x.id)===Number(id)),items=pack?.lessons?.[String(id)]||[];
  const html='<div class="eyebrow">CACHE LOCAL</div><p class="teaching-lead">'+esc(m?.description||'Cours disponibles hors ligne.')+'</p><div class="grid" style="margin-top:14px">'+(items.map(x=>'<button class="card flat" data-offline-lesson="'+esc(x.id)+'" style="text-align:left"><div class="eyebrow">'+esc(x.chapter||'LEÇON')+' · '+num(x.minutes)+' MIN</div><h3>'+esc(x.title)+'</h3><p>'+esc(x.summary||'')+'</p></button>').join('')||empty('◫','Aucune leçon en cache','Reconnecte le serveur pour mettre à jour le pack.'))+'</div>';
  openDrawer('MODULE '+id,m?.short||m?.title||'Cours hors ligne',html);
  qsa('[data-offline-lesson]').forEach(b=>b.onclick=()=>{closeDrawer();openLesson(id,b.dataset.offlineLesson,{type:'offline'})})
}
function renderOfflineSpace(){
  const pack=state.offlinePack;
  setInspector('');
  if(state.space==='learn'){
    qs('#viewHost').innerHTML='<section class="hero"><div class="eyebrow">BIBLIOTHÈQUE HORS LIGNE</div><h2>Continuer à apprendre sans le serveur.</h2><p>Les leçons et repères du dernier pack validé restent consultables. Les nouveaux mini-tests attendent la reconnexion pour conserver une correction fiable.</p><div class="hero-actions"><button class="btn secondary" id="offlineRetry">Réessayer la connexion</button></div></section><section class="section"><div class="module-grid">'+(pack?.modules||[]).filter(m=>Number(m.id)!==8).map(m=>'<article class="module-card"><div class="module-icon">'+m.id+'</div><div class="module-copy"><h3>'+esc(m.short||m.title)+'</h3><p>'+esc(m.description||'')+'</p></div><div class="module-meta"><b>'+num((pack?.lessons?.[String(m.id)]||[]).length)+' leçons</b><button class="btn ghost small" data-offline-module="'+m.id+'">Ouvrir</button></div></article>').join('')+'</div></section>';
    qsa('[data-offline-module]').forEach(b=>b.onclick=()=>openOfflineModule(Number(b.dataset.offlineModule)));qs('#offlineRetry').onclick=()=>location.reload();return
  }
  if(state.space==='home'){
    qs('#viewHost').innerHTML='<section class="hero"><div class="eyebrow">MODE HORS LIGNE</div><h2>Le travail local reste disponible.</h2><p>Le serveur n’est pas joignable. Tu peux relire les cours mis en cache et toute session déjà commencée reste sauvegardée localement.</p><div class="hero-actions"><button class="btn good" id="offlineLearn">Ouvrir les cours hors ligne</button><button class="btn secondary" id="offlineRetry">Réessayer la connexion</button></div></section><div class="metric-grid">'+metric(num(pack?.questions?.length||0),'questions en cache')+metric(num(new Set((pack?.questions||[]).map(x=>x.knowledge_id)).size),'notions en cache')+metric(num(Object.values(pack?.lessons||{}).flat().length),'leçons en cache')+metric(state.offline.length,'écritures en attente')+metric(esc(pack?.generated_at?date(pack.generated_at):'—'),'pack local')+'</div><section class="section">'+empty('↯','Serveur temporairement indisponible','Aucune réponse non synchronisée ne sera comptée fausse. La synchronisation reprendra automatiquement dès le retour du serveur.')+'</section>';
    qs('#offlineLearn').onclick=()=>go('learn','modules');qs('#offlineRetry').onclick=()=>location.reload();return
  }
  qs('#viewHost').innerHTML=empty('↯','Fonction disponible après reconnexion','Les cours restent consultables hors ligne, mais cette zone a besoin du moteur local pour garantir des données fiables.','<button class="btn" id="offlineGoLearn">Ouvrir les cours</button><button class="btn secondary" id="offlineRetry">Réessayer</button>');
  qs('#offlineGoLearn').onclick=()=>go('learn','modules');qs('#offlineRetry').onclick=()=>location.reload()
}

function startBuildWatcher(){
  if(window.__excBuildWatcher)return;
  const check=async()=>{
    if(document.visibilityState==='hidden')return;
    try{
      const r=await fetch('/api/status?build_watch='+Date.now(),{cache:'no-store'});
      if(!r.ok)return;
      const live=await r.json(),current=String(state.status?.build||'');
      if(!current||!live?.build||live.build===current)return;
      localStorage.setItem('exc2_pending_build',String(live.build));
      if(window.__excReloading)return;
      persistSession();persistDay();
      toast('Mise à jour appliquée','Reprise automatique de la session après actualisation.','build-update');
      window.__excReloading=true;
      location.reload()
    }catch{}
  };
  window.__excBuildWatcher=setInterval(check,45000);
  document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')check()});
  setTimeout(check,2500)
}
async function initPwa(){
  if(!('serviceWorker' in navigator))return;
  try{
    navigator.serviceWorker.addEventListener('controllerchange',()=>{
      if(window.__excReloading)return;
      if(window.__excReloading)return;
      persistSession();persistDay();window.__excReloading=true;location.reload()
    });
    const reg=await navigator.serviceWorker.register('./sw.js',{scope:'./'});
    await navigator.serviceWorker.ready;
    const target=reg.active||reg.waiting||reg.installing;
    target?.postMessage({type:'WARM_OFFLINE'});
    localStorage.setItem('exc2_pwa_ready','1');
  }catch(e){localStorage.setItem('exc2_pwa_ready','0')}
}

function bindRailScrollbar(){
  const scroller=qs('#railScroll'),bar=qs('#railScrollbar'),track=qs('#railScrollTrack'),thumb=qs('#railScrollThumb');
  const up=qs('#railScrollUp'),down=qs('#railScrollDown');
  if(!scroller||!bar||!track||!thumb||!up||!down)return;
  let drag=null,holdTimer=null;
  const overflow=()=>Math.max(0,scroller.scrollHeight-scroller.clientHeight);
  const measure=()=>{
    const ov=overflow(),trackH=Math.max(1,track.clientHeight-2);
    const ratio=scroller.scrollHeight?Math.min(1,scroller.clientHeight/scroller.scrollHeight):1;
    const thumbH=Math.min(trackH,Math.max(52,Math.round(trackH*ratio)));
    const maxTop=Math.max(0,trackH-thumbH);
    const top=ov?Math.round((scroller.scrollTop/ov)*maxTop):0;
    thumb.style.height=thumbH+'px';thumb.style.transform='translateY('+top+'px)';
    const pct=ov?Math.round(scroller.scrollTop/ov*100):0;
    bar.classList.toggle('no-overflow',ov<=1);
    up.disabled=ov<=1||scroller.scrollTop<=1;down.disabled=ov<=1||scroller.scrollTop>=ov-1;
    bar.dataset.scrollPercent=String(pct);bar.setAttribute('aria-valuenow',String(pct));
  };
  const step=(dir,smooth=true)=>scroller.scrollBy({top:dir*Math.max(96,Math.round(scroller.clientHeight*.55)),behavior:smooth?'smooth':'auto'});
  const startHold=dir=>{step(dir);clearInterval(holdTimer);holdTimer=setInterval(()=>step(dir,false),180)};
  const stopHold=()=>{if(holdTimer){clearInterval(holdTimer);holdTimer=null}};
  for(const [btn,dir] of [[up,-1],[down,1]]){
    btn.addEventListener('click',()=>step(dir));
    btn.addEventListener('pointerdown',()=>startHold(dir));
    btn.addEventListener('pointerup',stopHold);btn.addEventListener('pointercancel',stopHold);btn.addEventListener('pointerleave',stopHold);
  }
  bar.addEventListener('wheel',e=>{e.preventDefault();scroller.scrollBy({top:e.deltaY,behavior:'auto'})},{passive:false});
  track.addEventListener('pointerdown',e=>{
    if(e.target===thumb)return;
    const r=track.getBoundingClientRect(),ov=overflow();if(!ov)return;
    const ratio=Math.max(0,Math.min(1,(e.clientY-r.top)/Math.max(1,r.height)));
    scroller.scrollTo({top:ratio*ov,behavior:'smooth'});
  });
  thumb.addEventListener('pointerdown',e=>{e.preventDefault();thumb.setPointerCapture?.(e.pointerId);thumb.classList.add('dragging');drag={pointerId:e.pointerId,startY:e.clientY,startScroll:scroller.scrollTop}});
  thumb.addEventListener('pointermove',e=>{
    if(!drag||drag.pointerId!==e.pointerId)return;
    const ov=overflow(),trackH=Math.max(1,track.clientHeight-2),maxTop=Math.max(1,trackH-thumb.offsetHeight);
    scroller.scrollTop=drag.startScroll+((e.clientY-drag.startY)/maxTop)*ov
  });
  const stop=e=>{if(!drag)return;try{thumb.releasePointerCapture?.(drag.pointerId)}catch{}drag=null;thumb.classList.remove('dragging');measure()};
  thumb.addEventListener('pointerup',stop);thumb.addEventListener('pointercancel',stop);
  const key=e=>{
    if(e.key==='ArrowUp'){e.preventDefault();scroller.scrollBy({top:-72,behavior:'smooth'})}
    if(e.key==='ArrowDown'){e.preventDefault();scroller.scrollBy({top:72,behavior:'smooth'})}
    if(e.key==='PageUp'){e.preventDefault();step(-1)}
    if(e.key==='PageDown'){e.preventDefault();step(1)}
    if(e.key==='Home'){e.preventDefault();scroller.scrollTo({top:0,behavior:'smooth'})}
    if(e.key==='End'){e.preventDefault();scroller.scrollTo({top:scroller.scrollHeight,behavior:'smooth'})}
  };
  scroller.addEventListener('keydown',key);bar.addEventListener('keydown',key);
  scroller.addEventListener('scroll',measure,{passive:true});
  const revealActive=()=>{const active=scroller.querySelector('button.active');if(active)active.scrollIntoView({block:'nearest',behavior:'smooth'})};
  window.__excRevealRailActive=revealActive;
  if('ResizeObserver' in window)new ResizeObserver(()=>{measure();revealActive()}).observe(scroller);
  if('MutationObserver' in window)new MutationObserver(()=>{measure();revealActive()}).observe(scroller,{childList:true,subtree:true,attributes:true,attributeFilter:['class']});
  requestAnimationFrame(()=>{measure();revealActive()});setTimeout(()=>{measure();revealActive()},180)
}

function bindShell(){
  bindRailScrollbar();
  qsa('[data-space]').forEach(b=>b.onclick=()=>go(b.dataset.space,firstTab(b.dataset.space)));
  qs('#mobileMenu').onclick=()=>{qs('#rail').classList.add('open');qs('#overlay').classList.add('open')};
  qs('#overlay').onclick=closeMobile;qs('[data-action="more"]').onclick=()=>{qs('#mobileSheet').classList.toggle('open');qs('#overlay').classList.toggle('open')};
  qs('#themeToggle').onclick=()=>{state.theme=state.theme==='dark'?'light':'dark';localStorage.setItem('exc2_theme',state.theme);applyTheme()};
  qs('#collapseRail').onclick=()=>{state.railCollapsed=!state.railCollapsed;localStorage.setItem('exc2_rail',state.railCollapsed?'1':'0');applyTheme()};
  qs('#refreshButton').onclick=async()=>{state.status=null;state.stats=null;await loadBase(true);render();toast('Actualisé')};
  qs('#commandButton').onclick=openCommands;qs('#commandPalette').onclick=e=>{if(e.target===qs('#commandPalette'))closeCommands()};qs('#commandInput').oninput=e=>drawCommands(e.target.value);
  document.addEventListener('keydown',e=>{if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='k'){e.preventDefault();openCommands()}if(e.key==='Escape'){closeCommands();closeDrawer();closeMobile()}});
  qs('#drawerClose').onclick=closeDrawer;qs('#drawerBackdrop').onclick=e=>{if(e.target===qs('#drawerBackdrop'))closeDrawer()}
}
window.addEventListener('popstate',()=>{const p=new URLSearchParams(location.search);go(p.get('space')||'home',p.get('tab')||firstTab(p.get('space')||'home'))});
async function init(){
  applyTheme();bindShell();initPwa();
  if(continuityToken()){clearInterval(state.mobileHeartbeat);state.mobileHeartbeat=setInterval(continuityHeartbeat,3000);setTimeout(continuityHeartbeat,1800)}
  try{
    await loadBase();startBuildWatcher();await flushOffline();if(await restoreActiveSession())return;
    if(effectiveRole()!=='ADMIN'&&state.space==='admin'){state.space='home';state.tab='today'}
    renderChrome();go(state.space,validTab(state.space,state.tab)?state.tab:firstTab(state.space))
  }catch(e){
    setNetwork(false);state.offlineMode=true;state.me={role:'STUDENT',device:'LOCAL_CACHE',admin_available:false,admin_locked:true};
    if(state.session&&['ACTIVE','PAUSED'].includes(state.session.state)){
      toast('Session locale restaurée','Le serveur est hors ligne ; les réponses restent en file locale.','offline-resume');renderSession();return
    }
    try{
      const pack=await getOfflinePack();state.status=offlineStatus(pack);state.modules=pack.modules||[];state.space=['home','learn'].includes(state.space)?state.space:'home';state.tab=firstTab(state.space);renderChrome();renderOfflineSpace()
    }catch{
      renderChrome();qs('#viewHost').innerHTML=empty('↯','Mode hors ligne indisponible','Le shell est chargé, mais aucun pack d’étude n’a encore été mis en cache sur cet appareil. Reconnecte une fois le serveur pour préparer l’usage hors ligne.','<button class="btn" id="offlineRetry">Réessayer</button>');qs('#offlineRetry').onclick=()=>location.reload()
    }
  }
}
init();
})();