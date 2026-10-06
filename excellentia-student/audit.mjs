import fs from 'node:fs';
import path from 'node:path';

const root='excellentia-student',data=path.join(root,'data');
const gm=JSON.parse(fs.readFileSync(path.join(data,'gateway-manifest.json'),'utf8'));
let all=[];
for(const f of gm.question_files||[]){
  const p=path.join(data,f);if(!fs.existsSync(p))throw new Error('MISSING '+f);
  const a=JSON.parse(fs.readFileSync(p,'utf8'));if(!Array.isArray(a))throw new Error('NOT_ARRAY '+f);all.push(...a);
}
const ids=new Set(),kids=new Set(),bad=[];
for(const q of all){
  if(!q?.id||!q?.knowledge_id||!Array.isArray(q.choices)||q.choices.length<4||!Number.isInteger(q.answer)||q.answer<0||q.answer>=q.choices.length)bad.push(q?.id||'?');
  if(ids.has(q.id))throw new Error('DUPLICATE_ID '+q.id);ids.add(q.id);kids.add(q.knowledge_id);
}
for(const f of ['index.html','style.css','app.js','gateway-adapter.js','sw.js','manifest.webmanifest','vendor/qrcode.min.js'])if(!fs.existsSync(path.join(root,f)))throw new Error('MISSING '+f);
if(all.length!==4174||gm.expected_questions!==4174)throw new Error('QUESTION_COUNT '+all.length);
if(kids.size!==2667||gm.expected_knowledge_units!==2667)throw new Error('KNOWLEDGE_COUNT '+kids.size);
if(gm.timer_seconds!==40)throw new Error('TIMER_POLICY');
if(bad.length)throw new Error('BAD_QUESTIONS '+bad.slice(0,20).join(','));

const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
const app=fs.readFileSync(path.join(root,'app.js'),'utf8');
const adapter=fs.readFileSync(path.join(root,'gateway-adapter.js'),'utf8');
const sw=fs.readFileSync(path.join(root,'sw.js'),'utf8');
for(const marker of ['data-space="home"','data-space="learn"','data-space="train"','data-space="review"','data-space="exam"','data-space="progress"','gateway-adapter.js'])if(!html.includes(marker))throw new Error('SHELL_MARKER '+marker);
for(const marker of ["const QUESTION_LIMIT_SECONDS=40","SPACES={","renderHome","renderLearn","renderTrain","renderReview","renderExam","renderProgress"])if(!app.includes(marker))throw new Error('APP_MARKER '+marker);
for(const marker of ["/api/status","/api/session/start","/api/stats","/api/coach","/api/lessons","/api/reviews","/api/exetat/coverage","PUBLIC_GATEWAY","40000"])if(!adapter.includes(marker))throw new Error('ADAPTER_MARKER '+marker);
if(!sw.includes('WARM_OFFLINE')||!sw.includes('gateway-manifest.json'))throw new Error('SW_WARM_OFFLINE');
console.log(JSON.stringify({ok:true,questions:all.length,knowledge_units:kids.size,question_files:gm.question_files.length,shell:'official-v2.3.0',adapter:'local-api',timer_seconds:40},null,2));
