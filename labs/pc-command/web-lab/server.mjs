import http from 'node:http';
import os from 'node:os';
import { existsSync, openSync, closeSync, readSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

const PORT = Number(process.env.PC_COMMAND_WEB_PORT || 8791);
const HOST = '127.0.0.1';
const PC_ROOT = resolve(process.env.PC_COMMAND_ROOT || join(process.env.LOCALAPPDATA || os.homedir(), 'PC_COMMAND'));
const LAB_ROOT = resolve(new URL('.', import.meta.url).pathname.replace(/^\/(?:[A-Za-z]:)/, m => m.slice(1)));
const PUBLIC = join(LAB_ROOT, 'public');
const IDLE_MS = Number(process.env.PC_COMMAND_WEB_IDLE_MS || 120000);
let lastRequestAt = Date.now();

const paths = {
  manifest: join(PC_ROOT, 'app', 'manifest.json'),
  appConfig: join(PC_ROOT, 'app', 'config.default.json'),
  sources: join(PC_ROOT, 'app', 'powershell-sources.json'),
  depLock: join(PC_ROOT, 'app', 'dependency-lock.json'),
  update: join(PC_ROOT, 'config', 'update-status.json'),
  sync: join(PC_ROOT, 'data', 'cache', 'state-sync.json'),
  overview: join(PC_ROOT, 'state-repo', 'pc-command', 'overview.json'),
  feedbackIndex: join(PC_ROOT, 'state-repo', 'pc-command', 'feedback', 'feedback-index.json'),
  feedbackLedger: join(PC_ROOT, 'state-repo', 'pc-command', 'feedback', 'feedback-ledger.jsonl'),
  versionTrace: join(PC_ROOT, 'state-repo', 'pc-command', 'feedback', 'version-trace.json'),
  channels: join(PC_ROOT, 'state-repo', 'pc-command', 'channels'),
  reports: join(PC_ROOT, 'reports')
};

function readJson(file, fallback=null) {
  try { return JSON.parse(readFileSync(file, 'utf8').replace(/^\uFEFF/, '')); }
  catch { return fallback; }
}

function tailJsonl(file, limit=12, maxBytes=262144) {
  try {
    const st = statSync(file);
    const size = Math.min(st.size, maxBytes);
    const fd = openSync(file, 'r');
    const buf = Buffer.alloc(size);
    readSync(fd, buf, 0, size, Math.max(0, st.size - size));
    closeSync(fd);
    const lines = buf.toString('utf8').split(/\r?\n/).filter(Boolean);
    const out = [];
    for (const line of lines) {
      try { out.push(JSON.parse(line)); } catch {}
    }
    return out.slice(-Math.max(1, Math.min(50, Number(limit)||12)));
  } catch { return []; }
}

function safeChannelId(id) {
  return /^[A-Za-z0-9._-]{1,100}$/.test(String(id||'')) ? String(id) : null;
}

function sourceSummary() {
  const catalog = readJson(paths.sources, { entries: [] });
  const entries = Array.isArray(catalog.entries) ? catalog.entries : [];
  const counts = {};
  for (const x of entries) counts[x.class || 'UNKNOWN'] = (counts[x.class || 'UNKNOWN'] || 0) + 1;
  return { total: entries.length, counts };
}

function statusSnapshot() {
  const overview = readJson(paths.overview, { conversations: [] });
  const versions = readJson(paths.versionTrace, { versions: [] });
  const feedback = readJson(paths.feedbackIndex, {});
  const manifest = readJson(paths.manifest, {});
  const update = readJson(paths.update, {});
  const sync = readJson(paths.sync, {});
  const config = readJson(paths.appConfig, {});
  const dep = readJson(paths.depLock, {});
  const convs = Array.isArray(overview.conversations) ? overview.conversations : [];
  return {
    lab: {
      version: '0.2.0',
      mode: 'READ_ONLY',
      serverPid: process.pid,
      serverRssMb: Math.round(process.memoryUsage().rss / 104857.6) / 10,
      boundTo: HOST + ':' + PORT,
      idleShutdownSeconds: Math.round(IDLE_MS/1000)
    },
    app: {
      version: manifest.version || config.version || '?',
      channel: manifest.channel || '?',
      stage: config.product?.stage || '?',
      ramBudgetMb: config.limits?.ram_budget_mb || 150,
      maxConversations: config.limits?.max_conversations || 10
    },
    update,
    sync,
    overview,
    feedback,
    versions: Array.isArray(versions.versions) ? versions.versions.slice(-8) : [],
    sources: sourceSummary(),
    dependencyLock: {
      runtimeDependencies: Array.isArray(dep.runtime_dependencies) ? dep.runtime_dependencies.length : 0,
      schema: dep.schema || null
    },
    now: new Date().toISOString(),
    stateRootExists: existsSync(join(PC_ROOT, 'state-repo'))
  };
}

function channelSummary(id) {
  const safe = safeChannelId(id);
  if (!safe) return null;
  const raw = readJson(join(paths.channels, safe, 'state.json'), null);
  if (!raw) return null;
  return {
    id: raw.conversation_id || safe,
    label: raw.label || safe,
    short_code: raw.short_code || '',
    version: raw.version || '',
    updated_at: raw.updated_at || '',
    lifecycle: raw.lifecycle || {},
    objective: raw.objective || '',
    constraints: raw.constraints || {},
    current_turn: raw.current_turn || null,
    macro_tasks: (Array.isArray(raw.macro_tasks) ? raw.macro_tasks : []).map(m => ({
      id: m.id, title: m.title, state: m.state, completion: m.completion,
      confidence: m.confidence, current_action: m.current_action,
      last_success: m.last_success, next_step: m.next_step, blocker: m.blocker,
      micro_tasks: (Array.isArray(m.micro_tasks) ? m.micro_tasks : []).slice(0,20)
    })),
    recent_events: (Array.isArray(raw.recent_events) ? raw.recent_events : []).slice(-20)
  };
}

function healthSnapshot() {
  const nets = [];
  const ifs = os.networkInterfaces();
  for (const [name, rows] of Object.entries(ifs)) {
    for (const x of rows || []) {
      if (x.internal || x.family !== 'IPv4') continue;
      nets.push({ name, address: x.address, netmask: x.netmask, cidr: x.cidr });
    }
  }
  const total = os.totalmem(), free = os.freemem();
  let reports = [];
  try {
    reports = readdirSync(paths.reports)
      .filter(n => /\.(pdf|html)$/i.test(n))
      .map(n => ({ name:n, mtime:statSync(join(paths.reports,n)).mtime.toISOString() }))
      .sort((a,b) => b.mtime.localeCompare(a.mtime)).slice(0,8);
  } catch {}
  return {
    hostname: os.hostname(),
    platform: os.platform() + ' ' + os.release(),
    uptimeHours: Math.round(os.uptime()/360)/10,
    ram: {
      totalMb: Math.round(total/104857.6)/10,
      freeMb: Math.round(free/104857.6)/10,
      usedPercent: Math.round((1-free/total)*1000)/10
    },
    network: nets,
    reports,
    server: { pid:process.pid, rssMb:Math.round(process.memoryUsage().rss/104857.6)/10 },
    readOnly: true
  };
}

function sendJson(res, code, body) {
  const data = JSON.stringify(body);
  res.writeHead(code, {
    'content-type':'application/json; charset=utf-8',
    'cache-control':'no-store',
    'x-content-type-options':'nosniff'
  });
  res.end(data);
}

function serveIndex(res) {
  try {
    const page = readFileSync(join(PUBLIC, 'index.html'), 'utf8');
    res.writeHead(200, {
      'content-type':'text/html; charset=utf-8',
      'cache-control':'no-store',
      'content-security-policy':"default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:"
    });
    res.end(page);
  } catch (e) {
    res.writeHead(500, {'content-type':'text/plain; charset=utf-8'});
    res.end('PC COMMAND WEB LAB: index.html absent\n' + e.message);
  }
}

if (process.argv.includes('--selftest')) {
  const s = statusSnapshot();
  const h = healthSnapshot();
  const ok = Boolean(s.app.version && s.overview && h.ram.totalMb > 0 && existsSync(join(PUBLIC,'index.html')));
  console.log(JSON.stringify({ok, pcRoot:PC_ROOT, version:s.app.version, conversations:s.overview.conversations?.length||0, sources:s.sources.total, readOnly:true}, null, 2));
  process.exit(ok ? 0 : 1);
}

const server = http.createServer((req,res) => {
  lastRequestAt = Date.now();
  const u = new URL(req.url || '/', 'http://' + HOST);
  try {
    if (u.pathname === '/api/ping') return sendJson(res,200,{ok:true,at:new Date().toISOString(),mode:'READ_ONLY'});
    if (u.pathname === '/api/status') return sendJson(res,200,statusSnapshot());
    if (u.pathname === '/api/health') return sendJson(res,200,healthSnapshot());
    if (u.pathname === '/api/channel') {
      const data = channelSummary(u.searchParams.get('id'));
      return data ? sendJson(res,200,data) : sendJson(res,404,{error:'CHANNEL_NOT_FOUND'});
    }
    if (u.pathname === '/api/feedback') {
      const limit = Math.max(1,Math.min(50,Number(u.searchParams.get('limit')||12)));
      return sendJson(res,200,{index:readJson(paths.feedbackIndex,{}),items:tailJsonl(paths.feedbackLedger,limit)});
    }
    if (u.pathname === '/api/versions') {
      const v = readJson(paths.versionTrace,{versions:[]});
      return sendJson(res,200,{items:(v.versions||[]).slice(-20).reverse()});
    }
    if (u.pathname === '/api/sources') {
      return sendJson(res,200,{catalog:readJson(paths.sources,{entries:[]}),dependencyLock:readJson(paths.depLock,{})});
    }
    if (u.pathname === '/' || u.pathname === '/index.html') return serveIndex(res);
    return sendJson(res,404,{error:'NOT_FOUND'});
  } catch (e) {
    return sendJson(res,500,{error:'WEB_LAB_ERROR',message:String(e.message||e).slice(0,500)});
  }
});

server.listen(PORT, HOST, () => {
  console.log('PC COMMAND WEB LAB: http://' + HOST + ':' + PORT);
  console.log('Mode: READ_ONLY | PC root: ' + PC_ROOT);
});

const idleTimer = setInterval(() => {
  if (Date.now() - lastRequestAt > IDLE_MS) {
    console.log('WEB LAB idle timeout: shutdown');
    clearInterval(idleTimer);
    server.close(() => process.exit(0));
  }
}, 15000);
idleTimer.unref();

process.on('SIGINT', () => server.close(() => process.exit(0)));
process.on('SIGTERM', () => server.close(() => process.exit(0)));
