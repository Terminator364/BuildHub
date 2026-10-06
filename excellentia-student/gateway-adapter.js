(function(){
'use strict';
const nativeFetch=window.fetch.bind(window);
const ROOT=new URL('./',document.currentScript.src);
const DATA=f=>new URL('data/'+f,ROOT).href;
const STORE_KEY='excellentia_gateway_engine_v230';
let DBP=null;

const nowIso=()=>new Date().toISOString();
const clone=x=>JSON.parse(JSON.stringify(x));
const clamp=(v,a,b)=>Math.max(a,Math.min(b,Number(v||0)));
const shuffle=a=>{a=[...a];for(let i=a.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[a[i],a[j]]=[a[j],a[i]]}return a};
function loadStore(){try{return JSON.parse(localStorage.getItem(STORE_KEY)||'{}')}catch{return {}}}
function saveStore(s){localStorage.setItem(STORE_KEY,JSON.stringify(s))}
function ensureStore(){
  const s=loadStore();
  s.schema=2;s.sessions=s.sessions||{};s.history=s.history||[];s.progress=s.progress||{};s.day=s.day||null;s.created_at=s.created_at||nowIso();
  saveStore(s);return s;
}
async function jf(url){const r=await nativeFetch(url,{cache:'no-cache'});if(!r.ok)throw new Error('DATA_'+r.status);return r.json()}
function laneOf(q){
  const e=String(q.exam_lane||'').toLowerCase();if(['civics','geography','history','philosophy'].includes(e))return e;
  const t=(String(q.domain||'')+' '+String(q.subdomain||'')).toLowerCase();
  if(/civ|institution|constitution|droit|organisation|onu|union africaine|politique/.test(t))return 'civics';
  if(/philo|logique|syllog|socr|aristote|éthique|metaph|épist/.test(t))return 'philosophy';
  if(/histoire|histor|empire|guerre|colon|indépend|royaume|révolution/.test(t))return 'history';
  return 'geography';
}
function publicQ(q){return {id:q.id,knowledge_id:q.knowledge_id,module:Number(q.module||0),domain:q.domain||'',subdomain:q.subdomain||'',exam_lane:laneOf(q),prompt:q.prompt||'',choices:q.choices||[],difficulty:Number(q.difficulty||1),stability:q.stability||'STABLE',origin_year:q.origin_year||null}}
async function db(){
  if(DBP)return DBP;
  DBP=(async()=>{
    const gm=await jf(DATA('gateway-manifest.json'));
    const [modules,lessons,release,prep,sources,observed]=await Promise.all([
      jf(DATA('modules.json')),jf(DATA('lessons.json')),jf(DATA('release.json')),
      jf(DATA('excellentia-prep.json')).catch(()=>({subjects:[],transversal:null})),
      jf(DATA('exetat-source-registry.json')).catch(()=>({sources:[]})),
      jf(DATA('exetat-observed-items.json')).catch(()=>({items:[]}))
    ]);
    let all=[];
    for(let i=0;i<gm.question_files.length;i+=5){
      const parts=await Promise.all(gm.question_files.slice(i,i+5).map(f=>jf(DATA(f))));
      parts.forEach(x=>all.push(...(Array.isArray(x)?x:[])));
    }
    const seen=new Set(),questions=[];
    for(const q of all){if(!q?.id||!Array.isArray(q.choices)||q.answer==null||seen.has(q.id))continue;seen.add(q.id);questions.push(q)}
    const byId=new Map(questions.map(q=>[String(q.id),q]));
    const byKid=new Map();
    for(const q of questions){const k=String(q.knowledge_id||q.id);if(!byKid.has(k))byKid.set(k,[]);byKid.get(k).push(q)}
    const mods=modules.map(m=>({...m,question_count:Number(m.id)===8?questions.length:questions.filter(q=>Number(q.module)===Number(m.id)).length}));
    return {gm,modules:mods,lessons,release,prep,sources,observed,questions,byId,byKid};
  })();
  return DBP;
}
function json(data,status=200){return new Response(JSON.stringify(data),{status,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store'}})}
async function bodyOf(input,init){try{if(init?.body)return JSON.parse(init.body);if(input instanceof Request){const t=await input.clone().text();return t?JSON.parse(t):{}}}catch{}return {}}
function progressMeta(store,kid){
  return store.progress[String(kid)]||{attempts:0,correct:0,total_ms:0,last_at:null,lapses:0,streak:0,due_at:null};
}
function updateReview(store,q,ans){
  const k=String(q.knowledge_id||q.id),p=progressMeta(store,k);
  p.attempts++;if(ans.correct)p.correct++;p.total_ms+=Number(ans.elapsed_ms||0);p.last_at=ans.answered_at||nowIso();
  let days=1;
  if(ans.correct&&!ans.unsure){p.streak=(p.streak||0)+1;days=p.streak===1?3:p.streak===2?7:Math.min(60,Math.round(Number(p.interval_days||7)*1.8))}
  else{p.streak=0;p.lapses=(p.lapses||0)+1;days=1}
  p.interval_days=days;p.due_at=new Date(Date.now()+days*86400000).toISOString();
  store.progress[k]=p;
}
function masteryItem(meta,p){
  const attempts=Number(p.attempts||0),correct=Number(p.correct||0),acc=attempts?Math.round(correct/attempts*100):0,avg=attempts?Math.round(Number(p.total_ms||0)/attempts):0;
  const due=Boolean(p.due_at&&Date.parse(p.due_at)<=Date.now()),exposure=Math.min(1,attempts/4);
  const speed=avg<=0?50:avg<=15000?100:avg<=30000?85:avg<=40000?70:45,retention=attempts===0?0:due?40:Math.min(100,68+Number(p.streak||0)*7);
  let score=attempts===0?0:Math.round(acc*.62+exposure*15+speed*.13+retention*.10-Math.min(12,Number(p.lapses||0)*2));
  const cap=attempts===0?0:attempts===1?58:attempts===2?72:attempts===3?86:100;score=clamp(score,0,cap);
  const stage=attempts===0?'NEW':score<45?'FRAGILE':score<68?'LEARNING':score<85?'CONSOLIDATING':'MASTERED';
  return {...meta,attempts,correct,accuracy:acc,avg_ms:avg,last_at:p.last_at||null,due_at:p.due_at||null,due,lapses:Number(p.lapses||0),streak:Number(p.streak||0),mastery:score,stage}
}
async function knowledgeItems(moduleId=0,domain=''){
  const d=await db(),arr=[];
  for(const [kid,qs] of d.byKid){const q=qs[0];if(moduleId&&Number(q.module)!==Number(moduleId))continue;if(domain&&q.domain!==domain)continue;arr.push({knowledge_id:kid,id:kid,module:Number(q.module||0),domain:q.domain||'',subdomain:q.subdomain||'',stability:q.stability||'STABLE',source:q.source||'',question_count:qs.length,updated_at:q.verified_at||null})}
  return arr;
}
async function mastery(limit=5000){
  const store=ensureStore(),meta=await knowledgeItems(),items=meta.map(x=>masteryItem(x,progressMeta(store,x.knowledge_id)));
  items.sort((a,b)=>(a.stage==='NEW')-(b.stage==='NEW')||a.mastery-b.mastery||b.attempts-a.attempts);
  const buckets={NEW:0,FRAGILE:0,LEARNING:0,CONSOLIDATING:0,MASTERED:0};let seen=0,sum=0;items.forEach(x=>{buckets[x.stage]++;if(x.attempts){seen++;sum+=x.mastery}});
  return {summary:{total:items.length,seen,unseen:items.length-seen,coverage_pct:items.length?Math.round(seen/items.length*100):0,average_mastery:seen?Math.round(sum/seen):0,buckets},items:items.slice(0,Number(limit||5000))};
}
async function stats(){
  const d=await db(),store=ensureStore(),finished=Object.values(store.sessions).filter(s=>s.state==='FINISHED'),domains=new Map(),times=[];
  for(const s of finished)for(const [qid,a] of Object.entries(s.answers||{})){const q=d.byId.get(qid);if(!q)continue;const g=domains.get(q.domain)||{domain:q.domain,attempts:0,correct:0,total_ms:0,timed:0,fast_30s:0,slow_60s:0,over_40s:0};g.attempts++;if(a.correct)g.correct++;if(Number(a.elapsed_ms)>0){g.total_ms+=Number(a.elapsed_ms);g.timed++;times.push(Number(a.elapsed_ms));if(a.elapsed_ms<=30000)g.fast_30s++;if(a.elapsed_ms>60000)g.slow_60s++;if(a.elapsed_ms>40000)g.over_40s++}domains.set(q.domain,g)}
  const rows=[...domains.values()].map(g=>({...g,pct:g.attempts?Math.round(g.correct/g.attempts*1000)/10:0,avg_ms:g.timed?Math.round(g.total_ms/g.timed):0})).sort((a,b)=>b.attempts-a.attempts);
  const recent=finished.sort((a,b)=>String(b.finished_at).localeCompare(String(a.finished_at))).slice(0,20).map(s=>({id:s.id,created_at:s.created_at,finished_at:s.finished_at,mode:s.mode,module:s.module,total:s.total,score:s.score}));
  return {domains:rows,recent,speed:{answers:times.length,timed:times.length,avg_ms:times.length?Math.round(times.reduce((a,b)=>a+b,0)/times.length):0,fast_30s:times.filter(x=>x<=30000).length,slow_60s:times.filter(x=>x>60000).length,over_40s:times.filter(x=>x>40000).length}};
}
async function errors(limit=100){
  const d=await db(),store=ensureStore(),map=new Map();
  for(const s of Object.values(store.sessions).filter(x=>x.state==='FINISHED'))for(const [qid,a] of Object.entries(s.answers||{})){if(a.correct)continue;const q=d.byId.get(qid);if(!q)continue;const g=map.get(qid)||{...publicQ(q),misses:0,last_miss:null};g.misses++;g.last_miss=a.answered_at||s.finished_at;map.set(qid,g)}
  return [...map.values()].sort((a,b)=>String(b.last_miss).localeCompare(String(a.last_miss))).slice(0,Number(limit||100));
}
async function notebook(limit=200){
  const d=await db(),store=ensureStore(),map=new Map();
  for(const s of Object.values(store.sessions).filter(x=>x.state==='FINISHED'))for(const [qid,a] of Object.entries(s.answers||{})){const q=d.byId.get(qid);if(!q)continue;const k=String(q.knowledge_id||q.id),g=map.get(k)||{knowledge_id:k,module:Number(q.module||0),domain:q.domain||'',subdomain:q.subdomain||'',attempts:0,correct:0,misses:0,last_miss:null,sample:q};g.attempts++;if(a.correct)g.correct++;else{g.misses++;g.last_miss=a.answered_at||s.finished_at}map.set(k,g)}
  return [...map.values()].filter(x=>x.misses).map(x=>{const p=progressMeta(store,x.knowledge_id),accuracy=x.attempts?Math.round(x.correct/x.attempts*100):0;return {knowledge_id:x.knowledge_id,module:x.module,domain:x.domain,subdomain:x.subdomain,attempts:x.attempts,correct:x.correct,misses:x.misses,accuracy,last_miss:x.last_miss,due:Boolean(p.due_at&&Date.parse(p.due_at)<=Date.now()),action:x.misses>=3||accuracy<50?'RELEARN':'DRILL',sample:{id:x.sample.id,prompt:x.sample.prompt,answer:x.sample.choices[x.sample.answer]||'',explanation:x.sample.explanation||''},lesson:null}}).sort((a,b)=>b.misses-a.misses).slice(0,Number(limit||200));
}
async function coach(){
  const d=await db(),st=await stats(),ms=await mastery(),nb=await notebook(30),store=ensureStore();
  const attempts=Object.values(store.progress).reduce((n,p)=>n+Number(p.attempts||0),0),correct=Object.values(store.progress).reduce((n,p)=>n+Number(p.correct||0),0);
  const accuracy=attempts?Math.round(correct/attempts*100):0,coverage=ms.summary.coverage_pct||0,avg=st.speed.avg_ms||0,speed=avg<=0?0:avg<=18000?100:avg<=30000?85:avg<=40000?68:50;
  const reviews=Object.values(store.progress).filter(p=>p.due_at&&Date.parse(p.due_at)<=Date.now()).length,seen=Math.max(1,ms.summary.seen||0),retention=attempts?Math.max(0,Math.round(100-Math.min(80,reviews/seen*130))):0;
  const seven=Object.values(store.sessions).filter(s=>s.state==='FINISHED'&&Date.parse(s.finished_at)>=Date.now()-7*86400000).length,consistency=Math.min(100,seven*20),idx=Math.round(accuracy*.30+coverage*.30+retention*.18+speed*.12+consistency*.10);
  const label=idx<30?'DÉMARRAGE':idx<50?'CONSTRUCTION':idx<70?'PROGRESSION':idx<85?'CONSOLIDATION':'PRÊT À SIMULER',mission=[];
  const active=Object.values(store.sessions).find(s=>['ACTIVE','PAUSED'].includes(s.state));if(active)mission.push({kind:'RESUME',title:'Reprendre la session active',reason:'Une session est ouverte.',space:'home',tab:'today'});
  if(reviews)mission.push({kind:'REVIEW',title:'Éteindre la dette de mémoire',reason:reviews+' rappel(s) à échéance.',space:'review',tab:'due',minutes:15});
  if(nb.length)mission.push({kind:'REPAIR',title:'Réparer '+(nb[0].subdomain||nb[0].domain),reason:nb[0].misses+' erreur(s) sur cette notion.',space:'review',tab:'notebook',minutes:20});
  mission.push({kind:'SPRINT',title:'Sprint adaptatif',reason:'Consolider vitesse et rappel.',space:'train',tab:'sprint',minutes:10});
  return {generated_at:nowIso(),training_index:idx,label,disclaimer:"Indice interne d'entraînement, pas un score officiel.",components:{accuracy,coverage,retention,speed,consistency},streak_days:0,sessions_7d:seven,avg_ms:avg,reviews_due:reviews,mastery:ms.summary,error_notebook_count:nb.length,mission:mission.slice(0,4),subjects:d.prep.subjects||[],transversal:d.prep.transversal||null};
}
function activeSession(store){return Object.values(store.sessions).find(s=>['ACTIVE','PAUSED'].includes(s.state))||null}
function sessionPublic(s,reveal=false){
  const out=clone(s);out.questions=(s.question_ids||[]).map(id=>{const q=s._qmap?.[id];return q}).filter(Boolean);
  delete out._qmap;delete out.question_ids;
  if(!reveal&&s.mode==='mock')for(const a of Object.values(out.answers||{})){delete a.correct;delete a.correct_index;delete a.explanation;delete a.answer}
  return out;
}
async function makeSession(body){
  const d=await db(),store=ensureStore(),existing=activeSession(store);if(existing&&!body.force_new)return {...sessionPublic(existing,false),resumed:true};
  let pool=d.questions.filter(q=>Number(q.module||0)!==8);const moduleId=Number(body.module||0);if(moduleId>0&&moduleId!==8)pool=pool.filter(q=>Number(q.module)===moduleId);
  if(Array.isArray(body.knowledge_ids)&&body.knowledge_ids.length){const ks=new Set(body.knowledge_ids.map(String));pool=pool.filter(q=>ks.has(String(q.knowledge_id)))}
  const count=Math.max(1,Math.min(Number(body.count||30),100)),mode=String(body.mode||'module');
  let chosen=[];
  const uniqueByKid=arr=>{const seen=new Set(),out=[];for(const q of shuffle(arr)){const k=String(q.knowledge_id||q.id);if(seen.has(k))continue;seen.add(k);out.push(q)}return out};
  if(mode==='mock'){
    const quotas={civics:Math.round(count*.10),geography:Math.round(count*.30),history:Math.round(count*.30)};quotas.philosophy=count-quotas.civics-quotas.geography-quotas.history;
    for(const [lane,n] of Object.entries(quotas))chosen.push(...uniqueByKid(pool.filter(q=>laneOf(q)===lane)).slice(0,n));
  }else if(mode==='review'){
    const dueKids=new Set(Object.entries(store.progress).filter(([,p])=>p.due_at&&Date.parse(p.due_at)<=Date.now()).map(([k])=>k));
    chosen=uniqueByKid(pool.filter(q=>dueKids.has(String(q.knowledge_id)))).slice(0,count);
  }else{
    const m=await mastery();const score=new Map(m.items.map(x=>[String(x.knowledge_id),Number(x.mastery||0)]));
    chosen=uniqueByKid(pool).sort((a,b)=>(score.get(String(a.knowledge_id))||0)-(score.get(String(b.knowledge_id))||0)+Math.random()-.5).slice(0,count);
  }
  if(chosen.length<count){const have=new Set(chosen.map(q=>q.id));chosen.push(...uniqueByKid(pool.filter(q=>!have.has(q.id))).slice(0,count-chosen.length))}
  const id='G-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,8),t=Date.now(),qmap={};chosen.forEach(q=>qmap[q.id]=publicQ(q));
  const s={id,state:'ACTIVE',mode,module:moduleId,total:chosen.length,position:0,duration_seconds:chosen.length*40,remaining_seconds:chosen.length*40,question_time_limit_seconds:40,question_started_at_ms:t,question_deadline_ms:t+40000,question_remaining_ms:40000,created_at:nowIso(),updated_at:nowIso(),finished_at:null,score:null,answers:{},question_ids:chosen.map(q=>q.id),_qmap:qmap};
  store.sessions[id]=s;saveStore(store);return sessionPublic(s,false);
}
function fullQ(d,q){return {...publicQ(q),answer:Number(q.answer),explanation:q.explanation||''}}
async function answerSession(id,body){
  const d=await db(),store=ensureStore(),s=store.sessions[id];if(!s||!['ACTIVE','PAUSED'].includes(s.state))return {error:'SESSION_NOT_ACTIVE',_status:409};
  const q=d.byId.get(String(body.question_id));if(!q)return {error:'QUESTION_NOT_FOUND',_status:409};
  const elapsed=clamp(body.elapsed_ms,0,40000),timed=Boolean(body.timed_out)||elapsed>=40000,selected=timed?-1:Number(body.selected),correct=!timed&&selected===Number(q.answer);
  const a={selected,unsure:selected<0||Boolean(body.unsure),marked:Boolean(body.marked),confidence:clamp(body.confidence,0,3),elapsed_ms:timed?40000:elapsed,correct,correct_index:Number(q.answer),explanation:q.explanation||'',answer:q.choices[Number(q.answer)]||'',answered_at:nowIso()};
  s.answers[q.id]=a;s.updated_at=nowIso();s.question_deadline_ms=0;s.question_remaining_ms=0;saveStore(store);
  return {ok:true,question_id:q.id,saved:true,feedback:s.mode==='mock'?null:{correct,correct_index:Number(q.answer),explanation:q.explanation||'',answer:q.choices[Number(q.answer)]||''}};
}
async function progressSession(id,body){
  const store=ensureStore(),s=store.sessions[id];if(!s||!['ACTIVE','PAUSED'].includes(s.state))return {error:'SESSION_NOT_ACTIVE',_status:409};
  const old=Number(s.position||0),next=clamp(body.position??old,0,Math.max(0,s.total-1)),qid=s.question_ids[old];
  if(next!==old&&qid&&!s.answers[qid])return {error:'QUESTION_NOT_ANSWERED',_status:409};
  s.position=next;s.remaining_seconds=Number(body.remaining_seconds??s.remaining_seconds);s.state=['ACTIVE','PAUSED'].includes(body.state)?body.state:s.state;s.updated_at=nowIso();
  const t=Date.now(),answered=s.answers[s.question_ids[next]];s.question_started_at_ms=answered?0:t;s.question_remaining_ms=answered?0:40000;s.question_deadline_ms=answered||s.state==='PAUSED'?0:t+40000;saveStore(store);
  return {ok:true,question_time_limit_seconds:40,question_started_at_ms:s.question_started_at_ms,question_deadline_ms:s.question_deadline_ms,question_remaining_ms:s.question_remaining_ms};
}
async function finishSession(id,body){
  const d=await db(),store=ensureStore(),s=store.sessions[id];if(!s)return {error:'SESSION_NOT_FOUND',_status:404};
  for(const x of (body.answers_snapshot||[]))if(!s.answers[x.question_id])await answerSession(id,x);
  const missing=s.question_ids.filter(qid=>!s.answers[qid]);if(missing.length)return {error:'INCOMPLETE_SYNC',missing_count:missing.length,total:s.total,received:s.total-missing.length,missing_question_ids:missing,_status:409};
  let good=0;for(const qid of s.question_ids){const q=d.byId.get(qid),a=s.answers[qid];if(a.correct)good++;updateReview(store,q,a)}
  s.state='FINISHED';s.score=s.total?Math.round(good/s.total*1000)/10:0;s.remaining_seconds=0;s.finished_at=nowIso();s.updated_at=s.finished_at;
  s._qmap={};s.question_ids.forEach(id=>s._qmap[id]=fullQ(d,d.byId.get(id)));saveStore(store);return sessionPublic(s,true);
}
function dayTemplate(hours,startModule,d){
  const target=[2,4,6,8].includes(Number(hours))?Number(hours):4,total=Math.round(target*60),mods=[startModule,Math.min(7,startModule+1),Math.min(7,startModule+2)].filter((x,i,a)=>a.indexOf(x)===i);
  const lessons=d.lessons.modules||{},pos={},out=[];let remaining=total,seq=1,turn=0,phase=1;
  const next=()=>{const m=mods[turn++%mods.length]||2;pos[m]=pos[m]||0;const l=(lessons[String(m)]||[])[pos[m]++%(lessons[String(m)]||[null]).length]||null;return {m,l}};
  const add=(kind,title,min,m=0,l=null)=>{if(remaining<5)return;min=Math.max(5,Math.min(min,remaining));out.push({id:'B'+seq++,kind,title,minutes:min,module:m,lesson_id:l?.id||null,state:'PENDING',started_at:null,completed_at:null,phase,phase_label:'Bloc focus '+phase,sequence_label:kind==='lesson'?'Fiche':kind==='mixed'?'Test général':'Pause',score:null,validation_score:null,correct:null,wrong:null,blank:null,session_id:null});remaining-=min};
  while(remaining>=5){const focus=Math.min(55,remaining),br=remaining>55&&remaining-55>=10,act=br?55:focus;if(act<15){add('review','Révision finale',act);break}const test=Math.max(9,Math.round(act*.27)),teach=act-test,a=next(),b=next();add('lesson','Fiche · '+(a.l?.title||('Module '+a.m)),Math.floor(teach/2),a.m,a.l);add('lesson','Fiche · '+(b.l?.title||('Module '+b.m)),teach-Math.floor(teach/2),b.m,b.l);add('mixed','Test de consolidation · Bloc '+phase,test);if(br&&remaining>=10)add('break','Pause récupération',10);phase++}return out
}
async function workspace(module,id){
  const d=await db(),lesson=(d.lessons.modules?.[String(module)]||[]).find(x=>String(x.id)===String(id));if(!lesson)return null;
  let facts=[],kids=(lesson.knowledge_cards||[]).map(x=>String(x.knowledge_id||'')).filter(Boolean);
  if(kids.length){for(const k of kids){const q=d.byKid.get(k)?.[0];if(q)facts.push(q);if(facts.length>=12)break}}
  if(facts.length<5){const tokens=(String(lesson.title||'')+' '+String(lesson.summary||'')+' '+(lesson.covers||[]).join(' ')).toLowerCase().split(/[^a-zà-ÿ0-9]+/).filter(x=>x.length>4);const ranked=d.questions.filter(q=>Number(q.module)===Number(module)).map(q=>({q,score:tokens.reduce((n,t)=>n+((q.prompt+' '+q.domain+' '+q.subdomain).toLowerCase().includes(t)?1:0),0)})).filter(x=>x.score).sort((a,b)=>b.score-a.score).map(x=>x.q);for(const q of ranked){if(!facts.some(x=>x.knowledge_id===q.knowledge_id))facts.push(q);if(facts.length>=12)break}}
  return {...lesson,module:Number(module),teaching_facts:facts.slice(0,12).map(q=>({question_id:q.id,knowledge_id:q.knowledge_id,domain:q.domain,subdomain:q.subdomain,prompt:q.prompt,answer:q.choices[q.answer]||'',explanation:q.explanation||'',source:q.source||'',source_url:q.source_url||'',verified_at:q.verified_at||'',review_by:q.review_by||'',stability:q.stability||'STABLE',difficulty:Number(q.difficulty||1),alignment_score:100,distractors:q.choices.filter((_,i)=>i!==Number(q.answer))})),sources:[...new Set(facts.map(q=>q.source).filter(Boolean))],teaching_override:null,pedagogy:{kind:'KNOWLEDGE',aligned_facts:facts.length,recall_count:(lesson.recall_prompts||[]).length,objectives_count:(lesson.objectives||[]).length,status:facts.length>=5?'TEACHING_READY':'TEACHING_PARTIAL'}};
}
async function handler(path,method,body,u){
  const d=await db(),store=ensureStore();
  if(path==='/api/health')return {ok:true,build:'2026.10.06-v2.3.0-public',mode:'PUBLIC_GATEWAY'};
  if(path==='/api/me')return {ok:true,role:'STUDENT',device:'PUBLIC_GATEWAY',admin_available:false,admin_locked:true};
  if(path==='/api/mobile/ping')return {ok:true,build:'2026.10.06-v2.3.0-public',device:'PUBLIC_GATEWAY',server_time:nowIso(),session:null};
  if(path==='/api/status'){const ms=await mastery(),active=activeSession(store),reviews=Object.values(store.progress).filter(p=>p.due_at&&Date.parse(p.due_at)<=Date.now()).length,best=Math.max(0,...Object.values(store.sessions).filter(s=>s.state==='FINISHED').map(s=>Number(s.score||0)));return {service:'Excellentia Study Hub · Gateway',build:'2026.10.06-v2.3.0-public',started_at:store.created_at,question_time_limit_seconds:40,questions_loaded:d.questions.length,knowledge_units_loaded:d.byKid.size,question_capacity_target:4000,answers_saved:Object.values(store.progress).reduce((n,p)=>n+Number(p.attempts||0),0),sessions_finished:Object.values(store.sessions).filter(s=>s.state==='FINISHED').length,reviews_due:reviews,best_score:best,active_session_id:active?.id||null,modules:d.modules,resources:{total_mb:0,free_mb:0,rss_mb:0}}}
  if(path==='/api/modules')return {items:d.modules};
  if(path==='/api/stats')return stats();
  if(path==='/api/coach')return coach();
  if(path==='/api/prep')return d.prep;
  if(path==='/api/mastery'){const x=await mastery(Number(u.searchParams.get('limit')||5000));return x}
  if(path==='/api/error-notebook')return {items:await notebook(Number(u.searchParams.get('limit')||200))};
  if(path==='/api/errors')return {items:await errors(Number(u.searchParams.get('limit')||100))};
  if(path==='/api/reviews'){const due=Object.entries(store.progress).filter(([,p])=>p.due_at&&Date.parse(p.due_at)<=Date.now()).sort((a,b)=>Date.parse(a[1].due_at)-Date.parse(b[1].due_at)).slice(0,Number(u.searchParams.get('limit')||100));return {items:due.map(([kid,p])=>{const q=d.byKid.get(kid)?.[0];return q?{id:q.id,module:q.module,domain:q.domain,subdomain:q.subdomain,prompt:q.prompt,due_at:p.due_at,streak:p.streak||0,lapses:p.lapses||0,interval_days:p.interval_days||1}:null}).filter(Boolean)}}
  if(path==='/api/knowledge'){return {items:await knowledgeItems(Number(u.searchParams.get('module')||0),u.searchParams.get('domain')||'')}}
  if(path==='/api/bank'){let rows=d.questions;const q=(u.searchParams.get('q')||'').toLowerCase(),m=Number(u.searchParams.get('module')||0),domain=u.searchParams.get('domain')||'';if(m)rows=rows.filter(x=>Number(x.module)===m);if(domain)rows=rows.filter(x=>x.domain===domain);if(q)rows=rows.filter(x=>(x.prompt+' '+x.subdomain+' '+x.knowledge_id).toLowerCase().includes(q));return {items:rows.slice(0,Number(u.searchParams.get('limit')||100)).map(publicQ)}}
  if(path==='/api/microcards'){let rows=[...d.byKid.values()].map(x=>x[0]);const m=Number(u.searchParams.get('module')||0);if(m)rows=rows.filter(q=>Number(q.module)===m);return {items:rows.slice(0,Number(u.searchParams.get('limit')||200)).map(q=>({knowledge_id:q.knowledge_id,module:q.module,domain:q.domain,subdomain:q.subdomain,front:q.prompt,answer:q.choices[q.answer]||'',explanation:q.explanation||'',source:q.source||'',stability:q.stability||'STABLE',variants:d.byKid.get(String(q.knowledge_id))?.length||1}))}}
  if(path==='/api/lessons'){return {items:d.lessons.modules?.[String(Number(u.searchParams.get('module')||0))]||[]}}
  if(path==='/api/lessons/index'){const items=[];for(const [m,ls] of Object.entries(d.lessons.modules||{}))for(const l of ls)items.push({...l,module:Number(m)});return {items}}
  if(path==='/api/lesson/workspace'){const x=await workspace(Number(u.searchParams.get('module')||0),u.searchParams.get('id')||'');return x||{error:'LESSON_NOT_FOUND',_status:404}}
  if(path==='/api/offline-pack')return {schema:2,build:'2026.10.06-v2.3.0-public',generated_at:nowIso(),modules:d.modules,lessons:d.lessons.modules||{},prep:d.prep,lesson_overrides:{lessons:{}},questions:d.questions.map(q=>fullQ(d,q))};
  if(path==='/api/day/current')return {day:store.day&&['ACTIVE','PAUSED'].includes(store.day.state)?store.day:null};
  if(path==='/api/day/start'&&method==='POST'){const hours=[2,4,6,8].includes(Number(body.hours))?Number(body.hours):4,id='D-'+Date.now().toString(36);store.day={id,state:'ACTIVE',duration_hours:hours,current_index:0,created_at:nowIso(),updated_at:nowIso(),finished_at:null,blocks:dayTemplate(hours,clamp(body.start_module||2,1,8),d)};saveStore(store);return clone(store.day)}
  let m=path.match(/^\/api\/day\/([^/]+)\/update$/);if(m&&method==='POST'){const day=store.day;if(!day||day.id!==m[1])return {error:'STUDY_DAY_NOT_FOUND',_status:404};const idx=clamp(body.current_index??day.current_index,0,day.blocks.length-1);day.current_index=idx;if(body.action==='pause')day.state='PAUSED';else if(body.action==='resume')day.state='ACTIVE';else if(body.action==='start_block'){day.state='ACTIVE';day.blocks[idx].state='ACTIVE';day.blocks[idx].started_at=day.blocks[idx].started_at||nowIso()}else if(body.action==='record_result'){Object.assign(day.blocks[idx],{score:Number(body.score||0),validation_score:Number(body.score||0),session_id:body.session_id||null,correct:Number(body.correct||0),wrong:Number(body.wrong||0),blank:Number(body.blank||0),last_result_at:nowIso()})}else if(body.action==='complete_block'){day.blocks[idx].state='DONE';day.blocks[idx].completed_at=nowIso();const n=day.blocks.findIndex((x,i)=>i>idx&&x.state!=='DONE');if(n>=0)day.current_index=n;else{day.state='FINISHED';day.finished_at=nowIso()}}day.updated_at=nowIso();saveStore(store);return clone(day)}
  if(path==='/api/session/start'&&method==='POST')return makeSession(body);
  m=path.match(/^\/api\/session\/([^/]+)$/);if(m&&method==='GET'){const s=store.sessions[m[1]];return s?sessionPublic(s,false):{error:'SESSION_NOT_FOUND',_status:404}}
  m=path.match(/^\/api\/session\/([^/]+)\/answer$/);if(m&&method==='POST')return answerSession(m[1],body);
  m=path.match(/^\/api\/session\/([^/]+)\/progress$/);if(m&&method==='POST')return progressSession(m[1],body);
  m=path.match(/^\/api\/session\/([^/]+)\/finish$/);if(m&&method==='POST')return finishSession(m[1],body);
  if(path==='/api/exetat/coverage'){const lanes=['civics','geography','history','philosophy'].map(id=>{const qs=d.questions.filter(q=>laneOf(q)===id),ks=new Set(qs.map(q=>q.knowledge_id));return {id,label:{civics:'Civisme',geography:'Géographie',history:'Histoire',philosophy:'Philosophie'}[id],weight:{civics:.1,geography:.3,history:.3,philosophy:.3}[id],target_per_20:{civics:2,geography:6,history:6,philosophy:6}[id],questions:qs.length,knowledge_units:ks.size,actual_questions:qs.filter(q=>q.origin_year).length,actual_knowledge_units:new Set(qs.filter(q=>q.origin_year).map(q=>q.knowledge_id)).size,archive_questions:qs.filter(q=>q.origin_year).length,archive_knowledge_units:new Set(qs.filter(q=>q.origin_year).map(q=>q.knowledge_id)).size,calibrated_questions:0,calibrated_knowledge_units:0,evidence_knowledge_units:new Set(qs.filter(q=>q.origin_year).map(q=>q.knowledge_id)).size,ready_for_50:true,archive_depth_ready:true,actual_depth_ready:true}});return {blueprint:{lanes:lanes.map(x=>({id:x.id,label:x.label,weight:x.weight,questions:x.target_per_20}))},lanes,unclassified:{questions:0,knowledge_units:0},sources:{count:d.sources.sources?.length||0,years:[...new Set((d.sources.sources||[]).map(x=>x.year))].sort((a,b)=>b-a)}}}
  if(path==='/api/exetat/sources')return d.sources;
  if(path==='/api/exetat/provenance'){const rows=d.questions.filter(q=>q.origin_year).map(q=>({id:q.id,knowledge_id:q.knowledge_id,year:Number(q.origin_year),lane:laneOf(q),origin_kind:q.origin_kind||q.source_kind||null,verification_status:q.verification_status||'ARCHIVE_ONLY',source_confidence:q.source_confidence??'',source_url:q.source_url||'',fact_check_url:q.fact_check_url||''})),by={};rows.forEach(x=>by[x.year]=(by[x.year]||0)+1);return {observed_total:d.observed.items?.length||0,observed_by_year:{},decisions:{},active_recovered_total:rows.length,active_recovered_by_year:by,verification:{ARCHIVE_ONLY:rows.length},active_recovered:rows.slice(0,500)}}
  if(path==='/api/interaction'&&method==='POST')return {ok:true};
  if(path==='/api/update/status')return {status:'PUBLIC_GATEWAY',active_version:'2.3.0',result:'AUTO_WEB',phase:'DONE',percent:100};
  if(path==='/api/system/update-safety')return {safe:true,reason:'PUBLIC_GATEWAY_AUTO_UPDATE'};
  return {error:'NOT_FOUND',_status:404};
}
window.fetch=async function(input,init={}){
  const url=typeof input==='string'?input:(input?.url||String(input)),u=new URL(url,location.origin),method=String(init.method||(input instanceof Request?input.method:'GET')||'GET').toUpperCase();
  if(u.pathname.startsWith('/api/')){
    const body=await bodyOf(input,init),data=await handler(u.pathname,method,body,u),status=Number(data?._status||200);if(data&&'_status'in data)delete data._status;return json(data,status)
  }
  return nativeFetch(input,init)
};
window.__EXCELLENTIA_GATEWAY__={ready:db,store:ensureStore,reset:()=>{localStorage.removeItem(STORE_KEY);location.reload()}};
})();