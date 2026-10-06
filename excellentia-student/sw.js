const CACHE='excellentia-student-v230-shell-301';
const CORE=['./','./index.html','./style.css?v=301','./gateway-adapter.js?v=301','./app.js?v=301','./manifest.webmanifest','./vendor/qrcode.min.js','./data/gateway-manifest.json','./data/modules.json','./data/lessons.json','./data/release.json','./data/excellentia-prep.json'];
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(CORE)).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET')return;
  const u=new URL(e.request.url);
  if(u.origin!==location.origin)return;
  if(e.request.mode==='navigate'){
    e.respondWith(fetch(e.request).then(r=>{const cp=r.clone();caches.open(CACHE).then(c=>c.put('./index.html',cp));return r}).catch(()=>caches.match('./index.html')));
    return;
  }
  e.respondWith(fetch(e.request).then(r=>{if(r&&r.ok){const cp=r.clone();caches.open(CACHE).then(c=>c.put(e.request,cp))}return r}).catch(()=>caches.match(e.request)));
});
self.addEventListener('message',e=>{
  if(e.data?.type!=='WARM_OFFLINE')return;
  e.waitUntil((async()=>{
    try{
      const m=await (await fetch('./data/gateway-manifest.json',{cache:'no-cache'})).json();
      const urls=(m.question_files||[]).map(f=>'./data/'+f);
      const c=await caches.open(CACHE);
      for(let i=0;i<urls.length;i+=6)await Promise.all(urls.slice(i,i+6).map(async u=>{try{const r=await fetch(u);if(r.ok)await c.put(u,r.clone())}catch{}}));
    }catch{}
  })());
});