'use strict';
/**
 * 今夜星 天气代理服务
 *  - 和风 Key 只在服务端，客户端拿不到
 *  - 单点 /v1/wx，多点 /v1/grid（客户端一次拿全网格，不再逐点请求）
 *  - 上游按 0.5° 取整去重 + 30 分钟缓存
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

const PORT = Number(process.env.NW_PORT || 8090);
const QW_HOST = process.env.QW_HOST || 'mn6hf38tay.re.qweatherapi.com';
const QW_KEY = process.env.QW_KEY || '';
const TTL_MS = Number(process.env.NW_TTL_MS || 30 * 60 * 1000);
const MAX_KEYS = 800;
const CACHE_FILE = process.env.NW_CACHE_FILE || '/var/lib/nightwindow/wx-cache.json';
const CACHE_VERSION = 1;


// 世界主要城市/暗夜地（世界视图用；点太密会烧配额，75 个足够铺出格局）
const WORLD_CITIES = [
  ['温哥华', 49.28, -123.12], ['西雅图', 47.61, -122.33], ['旧金山', 37.77, -122.42],
  ['洛杉矶', 34.05, -118.24], ['丹佛', 39.74, -104.99], ['凤凰城', 33.45, -112.07],
  ['芝加哥', 41.88, -87.63], ['多伦多', 43.65, -79.38], ['纽约', 40.71, -74.01],
  ['迈阿密', 25.76, -80.19], ['墨西哥城', 19.43, -99.13], ['波哥大', 4.71, -74.07],
  ['利马', -12.05, -77.04], ['圣地亚哥', -33.45, -70.67], ['布宜诺斯艾利斯', -34.60, -58.38],
  ['圣保罗', -23.55, -46.63], ['马瑙斯', -3.12, -60.02], ['雷克雅未克', 64.15, -21.94],
  ['都柏林', 53.35, -6.26], ['伦敦', 51.51, -0.13], ['巴黎', 48.86, 2.35],
  ['马德里', 40.42, -3.70], ['里斯本', 38.72, -9.14], ['罗马', 41.90, 12.50],
  ['柏林', 52.52, 13.40], ['斯德哥尔摩', 59.33, 18.07], ['奥斯陆', 59.91, 10.75],
  ['赫尔辛基', 60.17, 24.94], ['华沙', 52.23, 21.01], ['基辅', 50.45, 30.52],
  ['莫斯科', 55.76, 37.62], ['伊斯坦布尔', 41.01, 28.98], ['雅典', 37.98, 23.73],
  ['开罗', 30.04, 31.24], ['卡萨布兰卡', 33.57, -7.59], ['达喀尔', 14.72, -17.47],
  ['拉各斯', 6.52, 3.38], ['内罗毕', -1.29, 36.82], ['开普敦', -33.92, 18.42],
  ['约翰内斯堡', -26.20, 28.05], ['迪拜', 25.20, 55.27], ['利雅得', 24.71, 46.68],
  ['德黑兰', 35.69, 51.39], ['卡拉奇', 24.86, 67.01], ['孟买', 19.08, 72.88],
  ['新德里', 28.61, 77.21], ['加德满都', 27.72, 85.32], ['拉萨', 29.65, 91.14],
  ['达卡', 23.81, 90.41], ['曼谷', 13.76, 100.50], ['河内', 21.03, 105.85],
  ['西贡', 10.82, 106.63], ['新加坡', 1.35, 103.82], ['吉隆坡', 3.14, 101.69],
  ['雅加达', -6.21, 106.85], ['马尼拉', 14.60, 120.98], ['香港', 22.32, 114.17],
  ['台北', 25.03, 121.57], ['上海', 31.23, 121.47], ['北京', 39.90, 116.41],
  ['成都', 30.67, 104.06], ['乌鲁木齐', 43.83, 87.62], ['首尔', 37.57, 126.98],
  ['东京', 35.68, 139.69], ['札幌', 43.06, 141.35], ['悉尼', -33.87, 151.21],
  ['墨尔本', -37.81, 144.96], ['珀斯', -31.95, 115.86], ['奥克兰', -36.85, 174.76],
  ['檀香山', 21.31, -157.86], ['阿塔卡马', -24.63, -70.40], ['莫纳克亚', 19.82, -155.47],
  ['加那利', 28.30, -16.51], ['夏威夷', 19.60, -155.50], ['南极中山站', -69.37, 76.37]
];

const cache = new Map(); // key -> {ts, hours}
const negCache = new Map(); // key -> ts（失败点短期不再重试）
const weekCache = new Map(); // key -> {ts, hours}  7 天逐时，TTL 更长
const WEEK_TTL = 3 * 60 * 60 * 1000;
const WEEK_MAX = 60;
const NEG_TTL = 10 * 60 * 1000;
const ipHits = new Map(); // ip -> {ts, count}

/** 启动时把上次落盘的缓存读回来，重启不再冷启动 */
function loadCache() {
  try {
    const obj = JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8'));
    if (obj.v !== CACHE_VERSION || typeof obj.items !== 'object') return;
    const now = Date.now();
    let n = 0;
    for (const k of Object.keys(obj.items)) {
      const v = obj.items[k];
      const ttl = k.startsWith('w:') ? WEEK_TTL : TTL_MS;
      if (v && typeof v.ts === 'number' && Array.isArray(v.hours) && now - v.ts < ttl) {
        (k.startsWith('w:') ? weekCache : cache).set(k, { ts: v.ts, hours: v.hours });
        n++;
      }
    }
    if (n > 0) log('cache restored', n, 'keys');
  } catch (e) {
    // 首次运行或文件损坏，按空缓存启动
  }
}

let saveTimer = null;

/** 15 秒合并写盘，避免每次上游返回都碰磁盘 */
function scheduleSave() {
  if (saveTimer) return;
  saveTimer = setTimeout(() => { saveTimer = null; saveNow(); }, 15000);
  if (typeof saveTimer.unref === 'function') saveTimer.unref();
}

/** 原子写：先写 .tmp 再 rename，进程被杀也不会留半个文件 */
function saveNow() {
  try {
    fs.mkdirSync(path.dirname(CACHE_FILE), { recursive: true });
    const items = {};
    const now = Date.now();
    for (const [k, v] of cache) {
      if (now - v.ts < TTL_MS) items[k] = { ts: v.ts, hours: v.hours };
    }
    for (const [k, v] of weekCache) {
      if (now - v.ts < WEEK_TTL) items[k] = { ts: v.ts, hours: v.hours };
    }
    const tmp = CACHE_FILE + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify({ v: CACHE_VERSION, saved: now, items }), 'utf8');
    fs.renameSync(tmp, CACHE_FILE);
  } catch (e) {
    log('cache save failed', e.message);
  }
}

function log(...a) { console.log(new Date().toISOString(), ...a); }

function clientIp(req) {
  const xf = req.headers['x-forwarded-for'];
  if (typeof xf === 'string' && xf.length) return xf.split(',')[0].trim();
  return req.socket.remoteAddress || 'unknown';
}

/** 简单限流：每 IP 每小时 120 次 */
function allow(ip) {
  const now = Date.now();
  let rec = ipHits.get(ip);
  if (!rec || now - rec.ts > 3600 * 1000) { rec = { ts: now, count: 0 }; ipHits.set(ip, rec); }
  rec.count++;
  return rec.count <= 120;
}

function round05(v) { return Math.round(v * 2) / 2; }

function simplify(h) {
  return {
    t: h.fxTime,
    c: Number(h.cloud),
    ws: Number(h.windSpeed),
    wd: Number(h.wind360),
    h: Number(h.humidity),
    p: Number(h.precip),
    pr: Number(h.pressure),
    tp: Number(h.temp),
    dw: Number(h.dew)
  };
}

async function fetchPoint(lat, lon) {
  const key = round05(lat) + ',' + round05(lon);
  const hit = cache.get(key);
  const now = Date.now();
  if (hit && now - hit.ts < TTL_MS) {
    // LRU：命中就移到末尾，避免热门条目被冷门挤掉
    cache.delete(key);
    cache.set(key, hit);
    return { hours: hit.hours, ts: hit.ts };
  }
  const neg = negCache.get(key);
  if (neg && now - neg < NEG_TTL) return null;

  const loc = round05(lon).toFixed(2) + ',' + round05(lat).toFixed(2);
  const url = 'https://' + QW_HOST + '/v7/weather/24h?location=' + loc + '&key=' + QW_KEY;
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), 8000);
  try {
    const res = await fetch(url, { signal: ac.signal, headers: { 'Accept-Encoding': 'identity' } });
    if (!res.ok) {
      // 400 = 和风不支持该坐标（海面/境外），属正常，短期不再重试
      if (res.status === 400) negCache.set(key, Date.now());
      else log('upstream http', res.status, loc);
      return null;
    }
    const body = await res.json();
    if (body.code !== '200' || !Array.isArray(body.hourly)) {
      if (body.code === '204' || body.code === '404') negCache.set(key, Date.now());
      else log('upstream code', body.code, loc);
      return null;
    }
    const hours = body.hourly.map(simplify);
    // 超上限时循环淘汰最早插入的条目
    while (cache.size >= MAX_KEYS) {
      const oldest = cache.keys().next().value;
      if (oldest === undefined) break;
      cache.delete(oldest);
    }
    cache.set(key, { ts: now, hours });
    scheduleSave();
    return { hours, ts: now };
  } catch (e) {
    log('fetch fail', loc, e.message);
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/** 7 天逐时（168 小时）：一天更新几次就够，缓存 3 小时 */
async function fetchWeek(lat, lon) {
  const key = 'w:' + round05(lat) + ',' + round05(lon);
  const now = Date.now();
  const hit = weekCache.get(key);
  if (hit && now - hit.ts < WEEK_TTL) {
    weekCache.delete(key);
    weekCache.set(key, hit);
    return { hours: hit.hours, ts: hit.ts };
  }
  const loc = round05(lon).toFixed(2) + ',' + round05(lat).toFixed(2);
  const url = 'https://' + QW_HOST + '/v7/weather/168h?location=' + loc + '&key=' + QW_KEY;
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), 12000);
  try {
    const res = await fetch(url, { signal: ac.signal, headers: { 'Accept-Encoding': 'identity' } });
    if (!res.ok) { log('week http', res.status, loc); return null; }
    const body = await res.json();
    if (body.code !== '200' || !Array.isArray(body.hourly)) { log('week code', body.code, loc); return null; }
    const hours = body.hourly.map(simplify);
    while (weekCache.size >= WEEK_MAX) {
      const oldest = weekCache.keys().next().value;
      if (oldest === undefined) break;
      weekCache.delete(oldest);
    }
    weekCache.set(key, { ts: now, hours });
    scheduleSave();
    return { hours, ts: now };
  } catch (e) {
    log('week fail', loc, e.message);
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function handleWeek(u) {
  const lat = Number(u.searchParams.get('lat'));
  const lon = Number(u.searchParams.get('lon'));
  if (!isFinite(lat) || !isFinite(lon) || Math.abs(lat) > 85) throw new Error('bad lat/lon');
  const got = await fetchWeek(lat, lon);
  if (!got) return { ok: false, points: [] };
  const age = Math.max(0, Math.round((Date.now() - got.ts) / 1000));
  return { ok: true, age, hours: got.hours };
}

function buildGrid(lat, lon, spanKm, n) {
  // spanKm 是总跨度，不是步长：步长 = 跨度 /(n-1)
  const half = (n - 1) / 2;
  const dLat = spanKm / (n - 1) / 111.0;
  const dLon = spanKm / (n - 1) / (111.0 * Math.max(0.2, Math.cos(lat * Math.PI / 180)));
  const pts = [];
  for (let i = 0; i < n; i++) {
    for (let j = 0; j < n; j++) {
      pts.push({ lat: lat + (i - half) * dLat, lon: lon + (j - half) * dLon });
    }
  }
  return pts;
}

async function handleGrid(u) {
  const lat = Number(u.searchParams.get('lat'));
  const lon = Number(u.searchParams.get('lon'));
  const span = Math.min(5000, Math.max(100, Number(u.searchParams.get('span') || 150)));
  const n = Math.min(9, Math.max(3, Number(u.searchParams.get('n') || 7)));
  if (!isFinite(lat) || !isFinite(lon) || Math.abs(lat) > 85) throw new Error('bad lat/lon');

  const pts = buildGrid(lat, lon, span, n);
  // 去重：同一 0.5° 只取一次上游
  const uniq = new Map();
  for (const p of pts) uniq.set(round05(p.lat) + ',' + round05(p.lon), p);
  const keys = Array.from(uniq.keys());
  const out = new Map();

  const CONC = 6;
  for (let i = 0; i < keys.length; i += CONC) {
    const slice = keys.slice(i, i + CONC);
    await Promise.all(slice.map(async (k) => {
      const p = uniq.get(k);
      const got = await fetchPoint(p.lat, p.lon);
      if (got) out.set(k, got);
    }));
  }

  const nowMs = Date.now();
  let oldestSec = 0;
  const points = pts.map((p) => {
    const got = out.get(round05(p.lat) + ',' + round05(p.lon)) || null;
    const age = got ? Math.max(0, Math.round((nowMs - got.ts) / 1000)) : null;
    if (age !== null && age > oldestSec) oldestSec = age;
    return {
      lat: Number(p.lat.toFixed(4)),
      lon: Number(p.lon.toFixed(4)),
      age,
      hours: got ? got.hours : null
    };
  });
  const ok = points.filter((p) => p.hours).length;
  return { ok: ok > 0, okPoints: ok, total: points.length, span, n, oldestAge: oldestSec, points };
}

async function handleWorld() {
  const out = [];
  const CONC = 8;
  for (let i = 0; i < WORLD_CITIES.length; i += CONC) {
    const slice = WORLD_CITIES.slice(i, i + CONC);
    const rows = await Promise.all(slice.map(async ([name, lat, lon]) => {
      const got = await fetchPoint(lat, lon);
      const age = got ? Math.max(0, Math.round((Date.now() - got.ts) / 1000)) : null;
      return { name, lat, lon, age, hours: got ? got.hours : null };
    }));
    for (const r of rows) out.push(r);
  }
  const ok = out.filter((p) => p.hours).length;
  return { ok: ok > 0, okPoints: ok, total: out.length, points: out };
}

async function handleWx(u) {
  const lat = Number(u.searchParams.get('lat'));
  const lon = Number(u.searchParams.get('lon'));
  if (!isFinite(lat) || !isFinite(lon) || Math.abs(lat) > 85) throw new Error('bad lat/lon');
  const got = await fetchPoint(lat, lon);
  const age = got ? Math.max(0, Math.round((Date.now() - got.ts) / 1000)) : null;
  return { ok: !!got, oldestAge: age ?? 0, points: [{ lat, lon, age, hours: got ? got.hours : null }] };
}

const server = http.createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x');
  const ip = clientIp(req);
  const send = (code, obj) => {
    const s = JSON.stringify(obj);
    res.writeHead(code, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'Content-Length': Buffer.byteLength(s)
    });
    res.end(s);
  };

  if (u.pathname === '/healthz') return send(200, { ok: true, up: process.uptime() });
  if (!allow(ip)) return send(429, { ok: false, error: 'rate_limited' });

  try {
    if (u.pathname === '/v1/wx') return send(200, await handleWx(u));
    if (u.pathname === '/v1/grid') return send(200, await handleGrid(u));
    if (u.pathname === '/v1/world') return send(200, await handleWorld());
    if (u.pathname === '/v1/week') return send(200, await handleWeek(u));
    send(404, { ok: false, error: 'not_found' });
  } catch (e) {
    send(400, { ok: false, error: e.message });
  }
});

loadCache();

server.listen(PORT, '127.0.0.1', () => log('nightwindow-api listening on', PORT, 'cache keys', cache.size));

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    log('shutting down, flushing cache', sig);
    saveNow();
    process.exit(0);
  });
}
