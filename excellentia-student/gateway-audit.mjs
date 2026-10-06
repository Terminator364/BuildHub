import fs from 'node:fs';
import path from 'node:path';

const root=path.resolve('excellentia-student');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'data/gateway-manifest.json'),'utf8'));
let all=[];
for(const f of manifest.question_files){
  const p=path.join(root,'data',f);
  if(!fs.existsSync(p)) throw new Error('Missing '+f);
  const a=JSON.parse(fs.readFileSync(p,'utf8'));
  if(!Array.isArray(a)) throw new Error('Not array '+f);
  all.push(...a);
}
const ids=new Set(), kids=new Set(), dup=[];
for(const q of all){
  if(!q.id||!q.knowledge_id||!Array.isArray(q.choices)||q.answer==null) throw new Error('Malformed '+JSON.stringify(q).slice(0,200));
  if(ids.has(q.id)) dup.push(q.id);
  ids.add(q.id); kids.add(q.knowledge_id);
  if(q.answer<0||q.answer>=q.choices.length) throw new Error('Bad answer '+q.id);
}
const expectedQ=Number(manifest.expected_questions), expectedK=Number(manifest.expected_knowledge_units);
console.log(JSON.stringify({questions:all.length,unique_ids:ids.size,knowledge_units:kids.size,duplicates:dup.length,files:manifest.question_files.length},null,2));
if(all.length!==expectedQ) throw new Error('Question count '+all.length+' != '+expectedQ);
if(ids.size!==all.length) throw new Error('Duplicate ids: '+dup.slice(0,20).join(','));
if(kids.size!==expectedK) throw new Error('Knowledge count '+kids.size+' != '+expectedK);
