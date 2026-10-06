const CACHE='excellentia-student-v303-20261006';
const CORE=['./','./index.html','./style.css?v=303','./app.js?v=303','./manifest.webmanifest','./data/gateway-manifest.json','./data/modules.json','./data/lessons.json','./data/release.json'];

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(CORE)).then(()=>self.skipWaiting()));
});

self.addEventListener('activate',event=>{
  event.waitUntil(
    caches.keys()
      .then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k))))
      .then(()=>self.clients.claim())
  );
});

self.addEventListener('message',event=>{
  if(event.data&&event.data.type==='SKIP_WAITING')self.skipWaiting();
});

self.addEventListener('fetch',event=>{
  if(event.request.method!=='GET')return;
  const req=event.request;
  const url=new URL(req.url);
  const isShell=req.mode==='navigate'||/\/(index\.html|style\.css|app\.js|sw\.js)$/.test(url.pathname);
  if(isShell){
    event.respondWith(
      fetch(req,{cache:'no-store'})
        .then(res=>{const cp=res.clone();caches.open(CACHE).then(c=>c.put(req,cp));return res})
        .catch(()=>caches.match(req).then(r=>r||caches.match('./index.html')))
    );
    return;
  }
  event.respondWith(
    caches.match(req).then(hit=>hit||fetch(req).then(res=>{
      const cp=res.clone();caches.open(CACHE).then(c=>c.put(req,cp));return res;
    }))
  );
});
