import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import http from 'node:http';
import net from 'node:net';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
const lab = resolve(here, '../pc-command/web-lab');
const serverPath = join(lab, 'server.mjs');
const html = readFileSync(join(lab, 'public/index.html'), 'utf8');

function writeJson(root, relative, value) {
  const path = join(root, relative);
  mkdirSync(dirname(path), {recursive:true});
  writeFileSync(path, JSON.stringify(value, null, 2));
}

function freePort() {
  return new Promise((resolvePort, reject) => {
    const s = net.createServer();
    s.once('error', reject);
    s.listen(0, '127.0.0.1', () => {
      const port = s.address().port;
      s.close(() => resolvePort(port));
    });
  });
}

function request(port, path, headers={}, method='GET') {
  return new Promise((resolveRequest,reject) => {
    const req = http.request({
      host:'127.0.0.1',port,path,method,
      headers: {Host:'127.0.0.1:'+port,...headers},
      timeout: 2000
    }, res => {
      let body='';
      res.setEncoding('utf8');
      res.on('data', b => {body+=b;});
      res.on('end', () => resolveRequest({
        status:res.statusCode,
        headers:res.headers,
        text:body,
        json:() => JSON.parse(body)
      }));
    });
    req.on('error',reject);
    req.on('timeout', () => req.destroy(new Error('request timeout')));
    req.end();
  });
}

test('PC_COMMAND_WEB_LAB_027_SECURITY_EVIDENCE_OK', {timeout:25000}, async () => {
  const root = mkdtempSync(join(tmpdir(),'pc-command-web-lab-test-'));
  const oldSignal='2020-01-01T00:00:00Z';
  writeJson(root,'app/manifest.json',{version:'1.0.5',channel:'stable'});
  writeJson(root,'app/config.default.json',{version:'1.0.5',product:{stage:'stable'},limits:{ram_budget_mb:150,max_conversations:10}});
  writeJson(root,'app/powershell-sources.json',{entries:[{repo:'pester/Pester',class:'CORE'}]});
  writeJson(root,'app/dependency-lock.json',{runtime_dependencies:[]});
  writeJson(root,'config/update-status.json',{state:'SUCCESS'});
  writeJson(root,'data/cache/state-sync.json',{last_success:oldSignal,last_error:null});
  writeJson(root,'state-repo/pc-command/overview.json',{conversations:[{
    id:'asquota-pccommand-20260926',
    label:'PC Command',
    progress_estimate:98,
    lifecycle:{state:'ASSISTANT_PROCESSING',last_signal_at:oldSignal}
  }]});
  writeJson(root,'state-repo/pc-command/channels/asquota-pccommand-20260926/state.json',{
    conversation_id:'asquota-pccommand-20260926',label:'PC Command',
    macro_tasks:[],recent_events:[]
  });
  writeJson(root,'state-repo/pc-command/feedback/feedback-index.json',{total_feedbacks:2,last_feedback_id:'FB-002'});
  writeJson(root,'state-repo/pc-command/feedback/version-trace.json',{versions:[{version:'1.0.5',status:'stable-field-proven'}]});
  const ledgerPath=join(root,'state-repo/pc-command/feedback/feedback-ledger.jsonl');
  writeFileSync(ledgerPath,'{"feedback_id":"FB-001"}\n{"feedback_id":"FB-002"}\n');
  const originalLedger=readFileSync(ledgerPath,'utf8');
  const port=await freePort();
  let stderr='';
  const child=spawn(process.execPath,[serverPath],{
    cwd:lab,
    env:{...process.env,PC_COMMAND_ROOT:root,PC_COMMAND_WEB_PORT:String(port),PC_COMMAND_WEB_IDLE_MS:'9000'},
    stdio:['ignore','pipe','pipe']
  });
  child.stderr.on('data',chunk=>{stderr+=String(chunk)});
  try {
    let up=false;
    for(let i=0;i<70;i++){
      if(child.exitCode!==null) break;
      try{
        const ping=await request(port,'/api/ping');
        if(ping.status===200){up=true;break;}
      }catch {}
      await new Promise(ok=>setTimeout(ok,70));
    }
    assert.ok(up,'Node server started: '+stderr);

    const status=await request(port,'/api/status');
    assert.equal(status.status,200);
    const data=status.json();
    assert.equal(data.lab.version,'0.2.7');
    assert.equal(data.app.version,'1.0.5');
    assert.equal(data.evidence.conversationSignal.status,'STALE');
    assert.equal(data.evidence.conversationSignal.certifiedLive,false);
    assert.equal(data.evidence.syncSignal.status,'STALE');
    assert.equal(data.evidence.syncSignal.certifiedLive,false);

    const home=await request(port,'/');
    assert.equal(home.status,200);
    assert.match(home.text,/id="evidenceAlert"/);
    assert.match(home.text,/dernier checkpoint/i);
    assert.equal(home.headers['x-content-type-options'],'nosniff');

    const blockedHost=await request(port,'/api/status',{Host:'evil.example'});
    assert.equal(blockedHost.status,403);
    assert.doesNotMatch(blockedHost.text,/1\.0\.5/);

    const blockedOrigin=await request(port,'/api/status',{Origin:'https://evil.example'});
    assert.equal(blockedOrigin.status,403);

    const blockedCrossSite=await request(port,'/api/status',{'Sec-Fetch-Site':'cross-site'});
    assert.equal(blockedCrossSite.status,403);

    const blockedPost=await request(port,'/api/status',{},'POST');
    assert.equal(blockedPost.status,405);

    const blockedTraverse=await request(port,'/api/channel?id=..%2F..%2Fsecrets');
    assert.equal(blockedTraverse.status,404);

    const validChannel=await request(port,'/api/channel?id=asquota-pccommand-20260926');
    assert.equal(validChannel.status,200);
    assert.equal(validChannel.json().id,'asquota-pccommand-20260926');

    const feedback=await request(port,'/api/feedback?limit=500');
    assert.equal(feedback.status,200);
    assert.equal(feedback.json().items.length,2);

    assert.equal(readFileSync(ledgerPath,'utf8'),originalLedger,'canonical ledger untouched');
    const inline=html.match(/<script>([\s\S]*?)<\/script>/);
    assert.ok(inline,'web UI script exists');
    assert.doesNotThrow(()=>new vm.Script(inline[1]),'web UI JS is syntactically valid');
    assert.match(html,/sourceFilters/);
    assert.match(html,/A — Cahier/);
    assert.match(html,/dernier checkpoint/i);
    console.log('PC_COMMAND_WEB_LAB_027_SECURITY_EVIDENCE_OK');
  } finally {
    child.kill('SIGTERM');
    await new Promise(ok=>{if(child.exitCode!==null)return ok();child.once('exit',ok);setTimeout(ok,1500)});
    rmSync(root,{recursive:true,force:true});
  }
});
