#!/usr/bin/env node
// Static dynamic astronomy calendar feed builder for https://skyinstrument.cn/v1/calendar/
// Zero external dependencies. Produces SHA-256 verified manifest.json + feed-<generation>.json.
//
// Usage:
//   node deploy/calendar-feed/build-calendar-feed.mjs --input deploy/calendar-feed/curated-events.json --out /tmp/calendar-out
//   node deploy/calendar-feed/build-calendar-feed.mjs --with-noaa --mpc-comets /srv/tle-mirror/v1/catalogs/mpc/comets.txt --out /srv/tle-mirror/v1/calendar
//   node deploy/calendar-feed/build-calendar-feed.mjs --validate-only --input deploy/calendar-feed/curated-events.json

import { createHash } from 'node:crypto';
import { mkdir, readdir, readFile, rename, unlink, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const NOAA_KP_FORECAST_URL = 'https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json';
const VALID_ID_RE = /^[a-zA-Z0-9][a-zA-Z0-9:._-]{1,127}$/;
const VALID_ACTIONS = new Set(['upsert', 'enrich', 'retract']);
const MAX_ENTRIES = 200;
const DAY_MS = 86400000;

function parseArgs(argv) {
  const opts = {
    input: resolve(dirname(new URL(import.meta.url).pathname), 'curated-events.json'),
    out: '',
    withNoaa: false,
    mpcComets: '',
    validateOnly: false,
    dryRun: false,
    nowMs: Date.now()
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--input' && argv[i + 1]) opts.input = resolve(argv[++i]);
    else if (arg === '--out' && argv[i + 1]) opts.out = resolve(argv[++i]);
    else if (arg === '--with-noaa') opts.withNoaa = true;
    else if (arg === '--mpc-comets' && argv[i + 1]) opts.mpcComets = argv[++i];
    else if (arg === '--validate-only') opts.validateOnly = true;
    else if (arg === '--dry-run') opts.dryRun = true;
    else if (arg === '--now' && argv[i + 1]) opts.nowMs = Number(argv[++i]);
  }
  return opts;
}

export function kpStormMetadata(kp) {
  if (kp >= 9) return { scale: 'G5', minLat: 30, labelZh: 'G5 极强地磁暴', labelEn: 'G5 Extreme Storm' };
  if (kp >= 8) return { scale: 'G4', minLat: 35, labelZh: 'G4 强地磁暴', labelEn: 'G4 Severe Storm' };
  if (kp >= 7) return { scale: 'G3', minLat: 40, labelZh: 'G3 强地磁暴', labelEn: 'G3 Strong Storm' };
  if (kp >= 6) return { scale: 'G2', minLat: 46, labelZh: 'G2 中等地磁暴', labelEn: 'G2 Moderate Storm' };
  return { scale: 'G1', minLat: 52, labelZh: 'G1 轻度地磁暴', labelEn: 'G1 Minor Storm' };
}

export function buildNoaaAuroraEntries(rows, nowMs = Date.now()) {
  if (!Array.isArray(rows) || rows.length < 2) return [];
  const windows = [];
  for (let i = 1; i < rows.length; i++) {
    const row = rows[i];
    if (!Array.isArray(row) || row.length < 2) continue;
    const rawTime = String(row[0] ?? '').trim();
    const kp = Number(row[1]);
    if (!Number.isFinite(kp) || kp < 5) continue;
    const iso = rawTime.includes('T') ? rawTime : rawTime.replace(' ', 'T') + 'Z';
    const ts = Date.parse(iso);
    if (!Number.isFinite(ts) || ts + 3 * 3600000 <= nowMs) continue;
    windows.push({ ts, kp });
  }
  if (windows.length === 0) return [];
  windows.sort((a, b) => a.ts - b.ts);

  // Merge contiguous 3-hour storm slots (<= 6h gap) into one clean alert per storm peak.
  const groups = [];
  for (const w of windows) {
    const last = groups[groups.length - 1];
    if (last && w.ts - last.endAt <= 6 * 3600000) {
      last.endAt = Math.max(last.endAt, w.ts + 3 * 3600000);
      if (w.kp > last.maxKp) {
        last.maxKp = w.kp;
        last.peakAt = w.ts;
      }
    } else {
      groups.push({ startAt: w.ts, peakAt: w.ts, endAt: w.ts + 3 * 3600000, maxKp: w.kp });
    }
  }

  return groups.map(g => {
    const meta = kpStormMetadata(g.maxKp);
    const dayTag = new Date(g.peakAt).toISOString().slice(0, 10);
    const kpStr = g.maxKp.toFixed(1).replace(/\.0$/, '');
    return {
      id: `remote:aurora:${dayTag}-${meta.scale.toLowerCase()}`,
      revision: Math.max(1, Math.round(g.maxKp * 10)),
      action: 'upsert',
      kind: 'aurora-alert',
      title: `${meta.labelZh}极光预警（Kp ${kpStr}）`,
      titleEn: `${meta.labelEn} Aurora Alert (Kp ${kpStr})`,
      body: `NOAA 空间天气预报峰值 Kp ${kpStr}（${meta.scale} 级）。北纬 ${meta.minLat}° 及以上地区夜间面向北方低空地平线有望观测或拍摄到极光，请避开城市光害并关注实时云量。`,
      bodyEn: `NOAA SWPC forecasts peak Kp ${kpStr} (${meta.scale}). Observers above ${meta.minLat}°N may spot or photograph aurora low on the northern horizon after dark under clear skies.`,
      at: g.peakAt,
      endAt: g.endAt,
      target: 'North',
      panel: 'calendar',
      observerPlanet: 'Earth',
      badge: `${meta.scale} 极光预警`,
      badgeEn: `${meta.scale} Aurora`,
      highlight: g.maxKp >= 6,
      regionFilter: { minLat: meta.minLat, maxLat: 90 },
      expiresAt: g.endAt + 6 * 3600000
    };
  });
}

// Parse standard MPC 1-line comet orbital elements (Soft00Cmt / comets.txt).
// Fixed columns: 14..18 year, 19..21 month, 22..29 day, 30..39 q(AU), 91..95 H, 96..100 G, 102..158 name.
export function parseMpcCometsText(text) {
  if (typeof text !== 'string' || !text.trim()) return [];
  const comets = [];
  for (const line of text.split(/\r?\n/)) {
    if (line.length < 105) continue;
    const year = Number(line.slice(14, 18).trim());
    const month = Number(line.slice(19, 21).trim());
    const dayFloat = Number(line.slice(22, 29).trim());
    const q = Number(line.slice(30, 39).trim());
    const absMag = Number(line.slice(91, 95).trim());
    const slope = Number(line.slice(96, 100).trim());
    const rawName = line.slice(102, 158).trim();
    if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(dayFloat) ||
        !Number.isFinite(q) || !Number.isFinite(absMag) || !rawName) {
      continue;
    }
    if (month < 1 || month > 12 || dayFloat < 1 || dayFloat >= 32 || q <= 0.01) continue;
    const wholeDay = Math.floor(dayFloat);
    const fracDayMs = Math.round((dayFloat - wholeDay) * DAY_MS);
    const perihelionMs = Date.UTC(year, month - 1, wholeDay) + fracDayMs;
    if (!Number.isFinite(perihelionMs)) continue;
    const safeSlope = Number.isFinite(slope) && slope > 0 ? slope : 4.0;
    comets.push({
      packedId: line.slice(0, 12).trim(),
      name: rawName,
      perihelionMs,
      q,
      absMag,
      slope: safeSlope
    });
  }
  return comets;
}

function cometSlug(name) {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 64) || 'comet';
}

// Select genuinely notable bright comets passing perihelion within [-45d, +60d] of nowMs.
// Emits `comet-alert` entries which also trigger the HarmonyOS app's automatic silent MPC comet sync.
export function buildMpcBrightCometEntries(text, nowMs = Date.now(), maxCount = 3) {
  const comets = parseMpcCometsText(text);
  const candidates = [];
  for (const c of comets) {
    const deltaDays = (c.perihelionMs - nowMs) / DAY_MS;
    if (deltaDays < -45 || deltaDays > 60) continue;
    if (c.q > 2.4) continue;
    // Conservative perihelion apparent magnitude estimate: m ≈ H + 5*log10(Delta_est) + 2.5*G*log10(q).
    const deltaEstAu = Math.max(0.4, Math.abs(c.q - 1.0) + 0.35);
    const peakMag = c.absMag + 5 * Math.log10(deltaEstAu) + 2.5 * c.slope * Math.log10(Math.max(0.05, c.q));
    if (!Number.isFinite(peakMag) || peakMag > 10.5) continue;
    candidates.push({ ...c, peakMag });
  }
  candidates.sort((a, b) => a.peakMag - b.peakMag);
  return candidates.slice(0, Math.max(1, maxCount)).map(c => {
    const dateStr = new Date(c.perihelionMs).toISOString().slice(0, 10);
    const magStr = c.peakMag.toFixed(1);
    const qStr = c.q.toFixed(2);
    const gearZh = c.peakMag <= 5.5
      ? '暗夜下有望肉眼可见，双筒望远镜观测更佳'
      : (c.peakMag <= 8.5 ? '建议使用双筒望远镜在暗夜低光害处寻觅' : '建议使用小型天文望远镜或深空摄影观测');
    const gearEn = c.peakMag <= 5.5
      ? 'Potentially visible to the unaided eye under dark skies, and striking in binoculars'
      : (c.peakMag <= 8.5 ? 'Best observed with binoculars under dark skies' : 'Best observed with a small telescope or astrophotography');
    const slug = cometSlug(c.name);
    return {
      id: `remote:comet:${slug}-${dateStr.slice(0, 4)}`,
      revision: Math.max(1, Math.round((15 - Math.max(-2, Math.min(14, c.peakMag))) * 10)),
      action: 'upsert',
      kind: 'comet-alert',
      title: `亮彗星过近日点：${c.name}`,
      titleEn: `Bright Comet Perihelion: ${c.name}`,
      body: `根据 MPC 最新轨道数据，彗星 ${c.name} 于 ${dateStr}（UTC）过近日点（近日距 ${qStr} AU），峰值估算约 ${magStr} 等。${gearZh}。应用已自动校验并同步最新彗星轨道。`,
      bodyEn: `Per latest MPC orbital elements, comet ${c.name} reaches perihelion on ${dateStr} UTC (q = ${qStr} AU) with estimated peak mag ~${magStr}. ${gearEn}.`,
      at: c.perihelionMs,
      endAt: c.perihelionMs + 14 * DAY_MS,
      target: c.name,
      panel: 'calendar',
      observerPlanet: 'Earth',
      badge: c.peakMag <= 6.0 ? '亮彗星' : '彗星观测',
      badgeEn: c.peakMag <= 6.0 ? 'Bright Comet' : 'Comet Watch',
      highlight: c.peakMag <= 6.5,
      expiresAt: c.perihelionMs + 45 * DAY_MS
    };
  });
}

export function validateAndNormalizeEntries(entries, nowMs = Date.now()) {
  if (!Array.isArray(entries)) throw new Error('entries must be an array');
  if (entries.length > MAX_ENTRIES) throw new Error(`entries exceed max ${MAX_ENTRIES}`);
  const out = [];
  for (const raw of entries) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('invalid entry object');
    const id = String(raw.id ?? '').trim();
    if (!VALID_ID_RE.test(id)) throw new Error(`invalid entry id: ${id}`);
    const revision = Number(raw.revision);
    if (!Number.isSafeInteger(revision) || revision < 1) throw new Error(`invalid revision on ${id}`);
    const action = String(raw.action ?? '').trim();
    if (!VALID_ACTIONS.has(action)) throw new Error(`invalid action on ${id}: ${action}`);
    if (raw.expiresAt !== undefined) {
      const exp = Number(raw.expiresAt);
      if (!Number.isFinite(exp)) throw new Error(`invalid expiresAt on ${id}`);
      if (exp <= nowMs) continue;
    }
    if (action === 'upsert') {
      if (typeof raw.title !== 'string' || !raw.title.trim()) throw new Error(`missing title on ${id}`);
      if (!Number.isFinite(Number(raw.at)) || Number(raw.at) <= 0) throw new Error(`invalid at on ${id}`);
    }
    out.push({
      ...raw,
      id: action === 'upsert' && !id.startsWith('remote:') ? `remote:${id}` : id,
      revision,
      action
    });
  }
  return out;
}

export function buildCalendarFeedArtifacts(entries, nowMs = Date.now()) {
  const normalized = validateAndNormalizeEntries(entries, nowMs);
  const generation = Math.max(1, Math.floor(nowMs / 1000));
  const feedDoc = {
    schemaVersion: 1,
    generation,
    updatedAt: nowMs,
    entries: normalized
  };
  const feedJson = JSON.stringify(feedDoc, null, 2) + '\n';
  const feedBytes = Buffer.from(feedJson, 'utf8');
  const sha256 = createHash('sha256').update(feedBytes).digest('hex');
  const feedFileName = `feed-${generation}.json`;
  const manifestDoc = {
    schemaVersion: 1,
    generation,
    updatedAt: nowMs,
    feedPath: `/v1/calendar/${feedFileName}`,
    bytes: feedBytes.byteLength,
    sha256
  };
  const manifestJson = JSON.stringify(manifestDoc, null, 2) + '\n';
  return { feedDoc, feedJson, feedFileName, manifestDoc, manifestJson };
}

async function atomicWrite(targetPath, content) {
  const tmpPath = `${targetPath}.tmp-${process.pid}`;
  await writeFile(tmpPath, content, 'utf8');
  await rename(tmpPath, targetPath);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const curated = JSON.parse(await readFile(opts.input, 'utf8'));
  const combined = Array.isArray(curated.entries) ? curated.entries.slice() : [];
  const curatedIds = new Set(combined.map(e => String(e?.id ?? '').trim()));

  if (opts.withNoaa) {
    try {
      const resp = await fetch(NOAA_KP_FORECAST_URL, { signal: AbortSignal.timeout(15000) });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const rows = await resp.json();
      for (const entry of buildNoaaAuroraEntries(rows, opts.nowMs)) {
        if (!curatedIds.has(entry.id)) combined.push(entry);
      }
    } catch (err) {
      console.error(`[calendar-feed] NOAA fetch skipped: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  if (opts.mpcComets) {
    try {
      let mpcText = '';
      if (/^https?:\/\//i.test(opts.mpcComets)) {
        const resp = await fetch(opts.mpcComets, { signal: AbortSignal.timeout(15000) });
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
        mpcText = await resp.text();
      } else {
        mpcText = await readFile(resolve(opts.mpcComets), 'utf8');
      }
      for (const entry of buildMpcBrightCometEntries(mpcText, opts.nowMs)) {
        if (!curatedIds.has(entry.id)) combined.push(entry);
      }
    } catch (err) {
      console.error(`[calendar-feed] MPC comets skipped: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  const artifacts = buildCalendarFeedArtifacts(combined, opts.nowMs);
  if (opts.validateOnly || opts.dryRun || !opts.out) {
    console.log(JSON.stringify({
      ok: true,
      mode: opts.validateOnly ? 'validate-only' : 'dry-run',
      generation: artifacts.manifestDoc.generation,
      entryCount: artifacts.feedDoc.entries.length,
      bytes: artifacts.manifestDoc.bytes,
      sha256: artifacts.manifestDoc.sha256
    }, null, 2));
    return;
  }

  await mkdir(opts.out, { recursive: true });
  // Idempotent no-churn guard: if existing feed.json already holds identical entries and manifest.json
  // is valid, keep existing generation untouched so timers never trigger unnecessary client downloads
  // or accumulate redundant feed-<gen>.json files.
  try {
    const prevFeed = JSON.parse(await readFile(resolve(opts.out, 'feed.json'), 'utf8'));
    const prevManifest = JSON.parse(await readFile(resolve(opts.out, 'manifest.json'), 'utf8'));
    if (prevManifest && Number.isSafeInteger(prevManifest.generation) &&
        JSON.stringify(prevFeed?.entries ?? null) === JSON.stringify(artifacts.feedDoc.entries)) {
      console.log(`Calendar feed unchanged gen=${prevManifest.generation} entries=${artifacts.feedDoc.entries.length}`);
      return;
    }
  } catch {
    // First publish or corrupt previous files -> write fresh artifacts.
  }

  await atomicWrite(resolve(opts.out, artifacts.feedFileName), artifacts.feedJson);
  await atomicWrite(resolve(opts.out, 'feed.json'), artifacts.feedJson);
  await atomicWrite(resolve(opts.out, 'manifest.json'), artifacts.manifestJson);

  // Retain only the latest 3 immutable feed-<generation>.json generations.
  try {
    const names = (await readdir(opts.out))
      .filter(n => /^feed-\d+\.json$/.test(n))
      .sort();
    for (const stale of names.slice(0, Math.max(0, names.length - 3))) {
      await unlink(resolve(opts.out, stale));
    }
  } catch {
    // Non-fatal cleanup
  }
  console.log(`Published calendar feed gen=${artifacts.manifestDoc.generation} entries=${artifacts.feedDoc.entries.length} sha256=${artifacts.manifestDoc.sha256}`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch(err => {
    console.error(`[calendar-feed] ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  });
}
