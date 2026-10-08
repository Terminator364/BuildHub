import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync, mkdirSync, writeFileSync, rmSync, existsSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import net from 'node:net';

const here=dirname(fileURLToPath(import.meta.url));
const lab=resolve(here,'../pc-command/web-lab');
const server=join(lab,'server.mjs');
const pause=ms=>new Promise(done=>setTimeout(done,ms));
function fixture(root,p,value){
  const full=join(root,p);
  mkdirSync(dirname(full),{recursive:true});
  writeFileSync(full,JSON.stringify(value,null,2));
}
async function openPort(){
  return await new Promise((done,reject)=>{
    const s=net.createServer();
    s.once('error',reject);
    s.listen(0,'127.0.0.1',()=>{const port=s.address().port;s.close(()=>done(port));});
  });
}
async function waitFor(fn,timeout=15000){
  const end=Date.now()+timeout;
  let error;
  while(Date.now()<end){
    try{const x=await fn();if(x)return x;}catch(e){error=e;}
    await pause(120);
  }
  throw new Error('Wait timed out'+(error?' | '+error.message:''));
}
function edgePath(){
  const locations=[
    join(process.env['ProgramFiles(x86)']||'C:\\Program Files (x86)','Microsoft','Edge','Application','msedge.exe'),
    join(process.env.ProgramFiles||'C:\\Program Files','Microsoft','Edge','Application','msedge.exe'),
    join(process.env.LOCALAPPDATA||'', 'Microsoft','Edge','Application','msedge.exe')
  ];
  return locations.find(existsSync);
}
function connectCdp(url){
  return new Promise((done,reject)=>{
    const ws=new WebSocket(url);
    let seq=0;
    const pending=new Map();
    const fail=new Error('Chrome DevTools socket closed');
    ws.onopen=()=>{
      ws.onmessage=e=>{
        const msg=JSON.parse(e.data);
        if(!msg.id)return;
        const cb=pending.get(msg.id);
        if(cb){pending.delete(msg.id);msg.error?cb.reject(new Error(msg.error.message)):cb.resolve(msg.result);}
      };
      ws.onclose=()=>{for(const cb of pending.values())cb.reject(fail);pending.clear();};
      done({
        call(method,params={}){
          return new Promise((resolveCall,rejectCall)=>{
            const id=++seq;
            pending.set(id,{resolve:resolveCall,reject:rejectCall});
            ws.send(JSON.stringify({id,method,params}));
          });
        },
        close(){ws.close();}
      });
    };
    ws.onerror=()=>reject(new Error('CDP websocket connection failed'));
  });
}

test('PC_COMMAND_WEB_LAB_028_REAL_EDGE_INTERACTION_OK',{timeout:90000},async()=>{
  if(process.platform!=='win32')throw new Error('Browser verification requires Windows runner');
  const edge=edgePath();
  assert.ok(edge,'Windows Microsoft Edge executable must exist for UI gate');
  const root=mkdtempSync(join(tmpdir(),'pcmd-ui-state-'));
  const profile=mkdtempSync(join(tmpdir(),'pcmd-ui-edge-'));
  let backend,chrome,cdp;
  const channelIds=Array.from({length:10},(_,i)=>'pc-command-conversation-'+(i+1));
  const conversations=channelIds.map((id,i)=>({
    id,label:'Conversation '+(i+1),short_code:'C'+(i+1),progress_estimate:30+i,
    lifecycle:{state:'ASSISTANT_PROCESSING',last_signal_at:'2020-01-01T00:00:00Z'},
    current_action:'Dernier checkpoint #'+(i+1),next_step:'Inspecter',last_success:'Checkpoint historique'
  }));
  const sourceEntries=[{repo:'pester/Pester',class:'CORE',role:'Quality test runner'}];
  for(let i=1;i<=30;i++)sourceEntries.push({repo:'example/core-'+i,class:'CORE',role:'Core primitive '+i});
  for(let i=1;i<=10;i++)sourceEntries.push({repo:'example/rejected-'+i,class:'REJECT',role:'Too heavy '+i});
  fixture(root,'app/manifest.json',{version:'1.0.5',channel:'stable'});
  fixture(root,'app/config.default.json',{version:'1.0.5',product:{stage:'stable'},limits:{ram_budget_mb:150,max_conversations:10}});
  fixture(root,'app/powershell-sources.json',{entries:sourceEntries});
  fixture(root,'app/dependency-lock.json',{runtime_dependencies:[]});
  fixture(root,'config/update-status.json',{state:'SUCCESS',message:'From fixture'});
  fixture(root,'data/cache/state-sync.json',{last_success:'2020-01-01T00:00:00Z',last_error:null});
  fixture(root,'state-repo/pc-command/overview.json',{conversations});
  for(const [i,id] of channelIds.entries()){
    fixture(root,'state-repo/pc-command/channels/'+id+'/state.json',{
      conversation_id:id,label:'Conversation '+(i+1),objective:'Testing a real UI',
      macro_tasks:[{id:'m1',title:'Macro interactive',state:'COMPLETED',completion:1,
      micro_tasks:[{id:'t1',title:'Sous-tache verifiee',completion:1}]}],recent_events:[]
    });
  }
  fixture(root,'state-repo/pc-command/feedback/feedback-index.json',{total_feedbacks:3,last_feedback_id:'FB-003'});
  fixture(root,'state-repo/pc-command/feedback/version-trace.json',{versions:[{version:'1.0.5',status:'stable-field-proven',intent:'Field-proof checkpoint'}]});
  const ledgerFile=join(root,'state-repo/pc-command/feedback/feedback-ledger.jsonl');
  writeFileSync(ledgerFile,[1,2,3].map(n=>JSON.stringify({feedback_id:'FB-00'+n,evidence:'Feedback '+n,abc:{A:'Need',B:'Research',C:'Field'}})).join('\n')+'\n');
  const initialLedger=readFileSync(ledgerFile,'utf8');
  const appPort=await openPort();
  try{
    backend=spawn(process.execPath,[server],{cwd:lab,env:{...process.env,PC_COMMAND_ROOT:root,PC_COMMAND_WEB_PORT:String(appPort),PC_COMMAND_WEB_IDLE_MS:'60000'},stdio:'ignore'});
    await waitFor(async()=>{const r=await fetch('http://127.0.0.1:'+appPort+'/api/ping');return r.ok;});
    chrome=spawn(edge,[
      '--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check',
      '--disable-background-mode','--no-sandbox',
      '--user-data-dir='+profile,'--remote-debugging-port=0','--remote-allow-origins=*',
      '--window-size=1365,900','http://127.0.0.1:'+appPort+'/'
    ],{stdio:'ignore'});
    const devFile=join(profile,'DevToolsActivePort');
    await waitFor(()=>existsSync(devFile));
    const devPort=Number(readFileSync(devFile,'utf8').split(/\r?\n/)[0]);
    assert.ok(devPort>0);
    const page=await waitFor(async()=>{
      const r=await fetch('http://127.0.0.1:'+devPort+'/json/list');
      const pages=await r.json();
      return pages.find(x=>x.type==='page'&&x.url.includes('127.0.0.1:'+appPort));
    });
    cdp=await connectCdp(page.webSocketDebuggerUrl);
    await cdp.call('Runtime.enable');
    async function run(expr){
      const result=await cdp.call('Runtime.evaluate',{expression:expr,returnByValue:true,awaitPromise:true});
      if(result.exceptionDetails)throw new Error('Browser JS: '+JSON.stringify(result.exceptionDetails));
      return result.result?.value;
    }
    try {
      await waitFor(()=>run("document.querySelector('#kSources')?.textContent==='41'"),8500);
    } catch(e) {
      const diag=await run(`(async()=>{let response='none';try{const r=await fetch('/api/status');response=r.status+':'+(await r.text()).slice(0,240)}catch(err){response='ERR:'+String(err)}return JSON.stringify({url:location.href,title:document.title,ready:document.readyState,sources:document.querySelector('#kSources')?.textContent,version:document.querySelector('#kVersion')?.textContent,body:document.body?.innerText.slice(0,320),refresh:typeof refresh,status:typeof STATUS==='undefined'?'undefined':STATUS?.sources?.total,api:response})})()`);
      console.error('PC_COMMAND_WEB_LAB_BROWSER_HYDRATION_DIAGNOSTIC '+diag);
      throw e;
    }
    assert.equal(await run("document.querySelector('#kVersion').textContent"),'1.0.5');
    assert.equal(await run("document.querySelectorAll('#conversationCards .conversation').length"),10);
    assert.equal(await run("document.querySelector('#evidenceAlert').classList.contains('visible')"),true);
    assert.match(await run("document.querySelector('#workState').textContent"),/ancien/i);
    const tabs=['conversations','health','local','sources','feedback','versions','technical','home'];
    for(const tab of tabs){
      const ok=await run("(()=>{document.querySelector('[data-view=\\\""+tab+"\\\"]').click();return document.querySelector('#"+tab+"').classList.contains('active')})()");
      assert.equal(ok,true,'Navigation '+tab);
    }
    await run("document.querySelector('[data-view=\\\"conversations\\\"]').click()");
    await run("document.querySelector('#conversationCards .conversation').click()");
    await waitFor(()=>run("document.querySelector('#conversationDetail')?.textContent.includes('Macro interactive')"));
    assert.equal(await run("document.querySelector('#conversationDetail').textContent.includes('Sous-tache verifiee')"),true);
    await run("document.querySelector('[data-view=\\\"sources\\\"]').click()");
    await waitFor(()=>run("document.querySelectorAll('#sourceCards .card').length===41"));
    await run("(()=>{const el=document.querySelector('#sourceSearch');el.value='Pester';el.dispatchEvent(new Event('input',{bubbles:true}))})()");
    assert.equal(await run("document.querySelectorAll('#sourceCards .card').length"),1);
    assert.match(await run("document.querySelector('#sourceCards').textContent"),/pester\/Pester/);
    await run("document.querySelector('#sourceClear').click()");
    assert.equal(await run("document.querySelectorAll('#sourceCards .card').length"),41);
    await run("document.querySelector('#sourceFilters button[data-class=\\\"REJECT\\\"]').click()");
    assert.equal(await run("document.querySelectorAll('#sourceCards .card').length"),10);
    await run("document.querySelector('[data-view=\\\"feedback\\\"]').click()");
    await waitFor(()=>run("document.querySelectorAll('#feedbackList details').length===3"));
    await run("document.querySelector('#feedbackList details summary').click()");
    await waitFor(()=>run("document.querySelector('#feedbackList details').open"),3000);
    await run("document.querySelector('#feedbackList details summary').click()");
    await waitFor(()=>run("document.querySelector('#feedbackList details').open===false"),3000);
    await run("document.querySelector('#feedbackList details summary').click()");
    await waitFor(()=>run("document.querySelector('#feedbackList details').open"),3000);
    assert.match(await run("document.querySelector('#feedbackList').textContent"),/A — Cahier/);
    await run("document.querySelector('[data-view=\\\"versions\\\"]').click()");
    await waitFor(()=>run("document.querySelector('#versionList').textContent.includes('1.0.5')"));
    await run("document.querySelector('[data-view=\\\"health\\\"]').click()");
    await waitFor(()=>run("document.querySelector('#hFree').textContent.includes('MB')"));
    await run("document.querySelector('[data-view=\\\"technical\\\"]').click()");
    assert.match(await run("document.querySelector('#rawStatus').textContent"),/READ_ONLY/);
    // Verify responsive narrow layout without horizontal overflow.
    await cdp.call('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
    await pause(200);
    const mobile=await run("({scrollWidth:document.documentElement.scrollWidth,clientWidth:document.documentElement.clientWidth})");
    assert.ok(mobile.scrollWidth<=mobile.clientWidth+2,'Mobile horizontal overflow '+JSON.stringify(mobile));
    await cdp.call('Emulation.clearDeviceMetricsOverride');

    // Exercise cache invalidation and graceful rendering for 0, 1, and 10 conversations.
    const overviewPath='state-repo/pc-command/overview.json';
    fixture(root,overviewPath,{conversations:[]});
    await pause(1200);await run("refresh()");
    assert.equal(await run("document.querySelector('#kConversations').textContent"),'0');
    assert.match(await run("document.querySelector('#conversationCards').textContent"),/Aucune conversation/);
    fixture(root,overviewPath,{conversations:conversations.slice(0,1)});
    await pause(1200);await run("refresh()");
    assert.equal(await run("document.querySelectorAll('#conversationCards .conversation').length"),1);
    fixture(root,overviewPath,{conversations});
    await pause(1200);await run("refresh()");
    assert.equal(await run("document.querySelectorAll('#conversationCards .conversation').length"),10);
    assert.equal(readFileSync(ledgerFile,'utf8'),initialLedger);
    console.log('PC_COMMAND_WEB_LAB_028_REAL_EDGE_INTERACTION_OK : 8 tabs, 0/1/10 conversations, 41 sources, search/filter, Feedback A+B+C, versions, health, mobile');
  }finally{
    cdp?.close();
    chrome?.kill();
    backend?.kill();
    await pause(800);
    try{rmSync(profile,{recursive:true,force:true})}catch{}
    try{rmSync(root,{recursive:true,force:true})}catch{}
  }
});
