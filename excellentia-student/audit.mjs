import fs from 'node:fs';
import path from 'node:path';

const root='excellentia-student';
const data=path.join(root,'data');
const gm=JSON.parse(fs.readFileSync(path.join(data,'gateway-manifest.json'),'utf8'));
const files=gm.question_files||[];
let all=[];
for(const f of files){
  const p=path.join(data,f);
  if(!fs.existsSync(p)) throw new Error('MISSING '+f);
  const a=JSON.parse(fs.readFileSync(p,'utf8'));
  if(!Array.isArray(a)) throw new Error('NOT_ARRAY '+f);
  all.push(...a);
}
const ids=new Set(), kids=new Set();
let bad=0, duplicateIds=0;
for(const q of all){
  if(!q||typeof q.id!=='string'||!Array.isArray(q.choices)||q.choices.length<4||!Number.isInteger(q.answer)||q.answer<0||q.answer>=q.choices.length) bad++;
  if(ids.has(q.id)) duplicateIds++; else ids.add(q.id);
  if(q.knowledge_id) kids.add(q.knowledge_id);
}
const must=[
  path.join(root,'index.html'),
  path.join(root,'style.css'),
  path.join(root,'app.js'),
  path.join(root,'sw.js'),
  path.join(root,'manifest.webmanifest'),
  path.join(data,'modules.json'),
  path.join(data,'lessons.json'),
  path.join(data,'release.json')
];
for(const p of must) if(!fs.existsSync(p)) throw new Error('MISSING '+p);
const result={
  question_files:files.length,
  questions:all.length,
  unique_ids:ids.size,
  knowledge_units:kids.size,
  bad_questions:bad,
  duplicate_ids:duplicateIds,
  expected_questions:gm.expected_questions,
  expected_knowledge_units:gm.expected_knowledge_units,
  timer_seconds:gm.timer_seconds
};
console.log(JSON.stringify(result,null,2));
if(all.length!==gm.expected_questions) throw new Error('QUESTION_COUNT_MISMATCH');
if(kids.size!==gm.expected_knowledge_units) throw new Error('KNOWLEDGE_COUNT_MISMATCH');
if(duplicateIds||bad) throw new Error('QUESTION_VALIDATION_FAILED');
if(gm.timer_seconds!==40) throw new Error('TIMER_NOT_40');
const app=fs.readFileSync(path.join(root,'app.js'),'utf8');
if(!app.includes("remaining_ms:40000")||!app.includes("deadline:Date.now()+40000")) throw new Error('APP_TIMER_NOT_40');
console.log('GATEWAY_AUDIT_OK');
