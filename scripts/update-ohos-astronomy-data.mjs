#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { mkdir, readFile, rename, stat, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { getSource, loadOhosSourceRegistry, resolveSource } from './ohos-data-sources.mjs';

const root = resolve(new URL('..', import.meta.url).pathname);
const cataloguePath = resolve(root, 'plugins/Satellites/resources/satellites.json');
const manifestPath = resolve(root, 'data/ohos/catalog-manifest.json');
const celestrakSourceIds = [
  'satellites.tle.stations',
  'satellites.tle.visual',
  'satellites.tle.active',
];
const satelliteFallbackSourceId = 'satellites.tle.satnogs';
const bundledCatalogSourceIds = [
  'catalog.exoplanets',
  'catalog.meteor-showers',
  'catalog.novae',
  'catalog.supernovae',
  'catalog.pulsars',
  'catalog.quasars',
];

function usage(exitCode = 0) {
  console.log(`用法：
  node scripts/update-ohos-astronomy-data.mjs --check [--max-age-days 14]
  node scripts/update-ohos-astronomy-data.mjs --update-satellites
  node scripts/update-ohos-astronomy-data.mjs --update-catalogs
  node scripts/update-ohos-astronomy-data.mjs --update-stars
  node scripts/update-ohos-astronomy-data.mjs --all

选项：
  --offline                    禁止网络访问，仅检查本地资源
  --source-mode <模式>         local、mirror 或 upstream；默认 upstream
  --mirror-base-url <URL>      mirror 模式使用的镜像根地址，也可用 OHOS_MIRROR_BASE_URL
  --source-root <目录>         local 模式的源根目录，默认当前仓库
  --verify-only                校验目录和清单，不写入文件
  --max-age-days <天数>        数据时效阈值，默认 14
  --allow-large-star-download  明确允许后才可下载数百 MiB 以上的星表（当前只记录许可，不自动下载）

该脚本只供开发/构建机使用。HarmonyOS 应用运行时不会调用它，也不会联网。`);
  process.exit(exitCode);
}

function parseArgs(args) {
  const result = { check: false, updateSatellites: false, updateCatalogs: false, updateStars: false, offline: false, verifyOnly: false, maxAgeDays: 14, allowLargeStarDownload: false, sourceMode: 'upstream', mirrorBaseUrl: process.env.OHOS_MIRROR_BASE_URL ?? '', sourceRoot: root };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--help' || arg === '-h') usage();
    if (arg === '--check') result.check = true;
    else if (arg === '--update-satellites') result.updateSatellites = true;
    else if (arg === '--update-catalogs') result.updateCatalogs = true;
    else if (arg === '--update-stars') result.updateStars = true;
    else if (arg === '--all') { result.updateSatellites = true; result.updateCatalogs = true; result.updateStars = true; }
    else if (arg === '--offline') result.offline = true;
    else if (arg === '--source-mode' && args[index + 1]) result.sourceMode = args[++index];
    else if (arg === '--mirror-base-url' && args[index + 1]) result.mirrorBaseUrl = args[++index];
    else if (arg === '--source-root' && args[index + 1]) result.sourceRoot = resolve(args[++index]);
    else if (arg === '--verify-only') result.verifyOnly = true;
    else if (arg === '--allow-large-star-download') result.allowLargeStarDownload = true;
    else if (arg === '--max-age-days' && args[index + 1]) result.maxAgeDays = Number(args[++index]);
    else throw new Error(`未知或不完整的参数：${arg}`);
  }
  if (!result.check && !result.updateSatellites && !result.updateCatalogs && !result.updateStars && !result.verifyOnly) result.check = true;
  if (!Number.isFinite(result.maxAgeDays) || result.maxAgeDays < 1) throw new Error('--max-age-days 必须是不小于 1 的数字');
  if (!['local', 'mirror', 'upstream'].includes(result.sourceMode)) throw new Error('--source-mode 必须是 local、mirror 或 upstream');
  if (result.sourceMode === 'mirror' && !result.mirrorBaseUrl) throw new Error('mirror 模式必须提供 --mirror-base-url 或 OHOS_MIRROR_BASE_URL');
  if (result.mirrorBaseUrl) {
    let mirrorUrl;
    try { mirrorUrl = new URL(result.mirrorBaseUrl); }
    catch { throw new Error('--mirror-base-url 必须是有效的 HTTP(S) URL'); }
    if (!['http:', 'https:'].includes(mirrorUrl.protocol)) throw new Error('--mirror-base-url 必须使用 HTTP(S)');
  }
  if (result.offline && result.sourceMode !== 'local' && (result.updateSatellites || result.updateCatalogs || result.updateStars)) throw new Error('--offline 更新只能配合 --source-mode local，避免意外联网');
  return result;
}

function sha256(value) { return createHash('sha256').update(value).digest('hex'); }

async function hashFile(path, algorithm) {
  const hash = createHash(algorithm);
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}

function parseTle(text) {
  const lines = text.replaceAll('\r', '').split('\n');
  const entries = new Map();
  for (let index = 0; index + 2 < lines.length; index += 1) {
    const title = lines[index].trim();
    const line1 = lines[index + 1]?.trim();
    const line2 = lines[index + 2]?.trim();
    if (!line1?.startsWith('1 ') || !line2?.startsWith('2 ')) continue;
    const id = line1.slice(2, 7).trim().replace(/^0+/, '') || '0';
    if (!/^\d+$/.test(id) || line1.length < 64 || line2.length < 64) continue;
    entries.set(id, { title, line1, line2 });
    index += 2;
  }
  return entries;
}

function parseSatnogsTle(text) {
  const payload = JSON.parse(text);
  if (!Array.isArray(payload)) throw new Error('SatNOGS 响应不是 JSON 数组');
  const entries = new Map();
  for (const record of payload) {
    const line1 = typeof record?.tle1 === 'string' ? record.tle1.trim() : '';
    const line2 = typeof record?.tle2 === 'string' ? record.tle2.trim() : '';
    const id = String(record?.norad_cat_id ?? line1.slice(2, 7)).trim().replace(/^0+/, '') || '0';
    if (!/^\d+$/.test(id) || !line1.startsWith('1 ') || !line2.startsWith('2 ') || line1.length < 64 || line2.length < 64) continue;
    const title = typeof record?.tle0 === 'string' ? record.tle0.replace(/^0\s+/, '').trim() : id;
    entries.set(id, { title, line1, line2 });
  }
  return entries;
}

async function downloadText(source) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 120000);
  try {
    const response = await fetch(source.url, { signal: controller.signal, headers: { 'User-Agent': 'SkyInstrument-offline-catalog-builder/1.0' } });
    if (!response.ok) throw new Error(`${source.id}: HTTP ${response.status}`);
    const text = await response.text();
    if (text.length < 100) throw new Error(`${source.id}: 响应为空或过短`);
    return text;
  } finally { clearTimeout(timeout); }
}

async function readResolvedText(source) {
  if (source.resolvedMode === 'local') {
    const text = await readFile(source.localFile, 'utf8');
    if (text.length < 100) throw new Error(`${source.id}: 本地文件为空或过短：${source.localFile}`);
    return text;
  }
  return downloadText({ id: source.id, url: source.url });
}

function sourceEndpoint(source) {
  return source.resolvedMode === 'local' ? source.localPath : source.url;
}

function validateCatalogue(catalogue) {
  const satellites = catalogue?.satellites;
  if (!satellites || typeof satellites !== 'object') throw new Error('satellites.json 缺少 satellites 对象');
  const ids = Object.keys(satellites);
  if (ids.length < 100) throw new Error(`卫星目录条目异常：${ids.length}`);
  let validTleCount = 0;
  for (const [id, record] of Object.entries(satellites)) {
    if (!/^\d+$/.test(id)) throw new Error(`卫星目录包含无效 NORAD 编号：${id}`);
    if (typeof record?.tle1 === 'string' && typeof record?.tle2 === 'string' && record.tle1.startsWith('1 ') && record.tle2.startsWith('2 ')) validTleCount += 1;
  }
  if (validTleCount < 100) throw new Error(`有效 TLE 条目异常：${validTleCount}`);
  return { entries: ids.length, validTleCount };
}

async function loadManifest() {
  try { return JSON.parse(await readFile(manifestPath, 'utf8')); }
  catch { return { schema: 1, catalogs: {} }; }
}

async function writeJsonAtomically(path, value) {
  await mkdir(resolve(path, '..'), { recursive: true });
  const temporaryPath = `${path}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  await rename(temporaryPath, path);
}

async function updateSatellites(options, manifest, registry) {
  const originalText = await readFile(cataloguePath, 'utf8');
  const catalogue = JSON.parse(originalText);
  const originalSummary = validateCatalogue(catalogue);
  const primaryTle = new Map();
  const fallbackTle = new Map();
  const sourceManifest = [];
  const sourceErrors = [];
  const primaryErrors = [];
  const readSource = async (sourceId, role, destination) => {
    const source = resolveSource(getSource(registry, sourceId), options.sourceMode, { mirrorBaseUrl: options.mirrorBaseUrl, sourceRoot: options.sourceRoot });
    try {
      const text = await readResolvedText(source);
      const parsed = source.format === 'satnogs-json' ? parseSatnogsTle(text) : parseTle(text);
      if (parsed.size === 0) throw new Error('未找到完整的 TLE 轨道数据');
      for (const [id, entry] of parsed) destination.set(id, entry);
      sourceManifest.push({ sourceId: source.id, role, format: source.format, sourceMode: source.resolvedMode, resolvedEndpoint: sourceEndpoint(source), bytes: Buffer.byteLength(text), entries: parsed.size, sha256: sha256(text), ok: true });
      console.log(`已读取 ${source.id}（${source.resolvedMode}）：${parsed.size} 条 TLE`);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const failure = { sourceId: source.id, role, sourceMode: source.resolvedMode, resolvedEndpoint: sourceEndpoint(source), error: message };
      sourceErrors.push(failure);
      if (role === 'primary') primaryErrors.push(failure);
      console.warn(`跳过 ${source.id}（${source.resolvedMode}）：${message}`);
    }
  };
  for (const sourceId of celestrakSourceIds) {
    await readSource(sourceId, 'primary', primaryTle);
  }
  await readSource(satelliteFallbackSourceId, 'supplement', fallbackTle);

  const allTle = new Map(primaryTle);
  let supplementalAvailableEntries = 0;
  for (const [id, entry] of fallbackTle) {
    if (allTle.has(id)) continue;
    allTle.set(id, entry);
    supplementalAvailableEntries += 1;
  }
  if (allTle.size === 0) throw new Error('所有卫星数据源均失败；保留原目录');
  const generatedAt = new Date().toISOString();
  let updatedEntries = 0;
  let primaryRefreshedEntries = 0;
  let supplementalRefreshedEntries = 0;
  for (const [id, record] of Object.entries(catalogue.satellites)) {
    const tle = allTle.get(id);
    if (!tle) continue;
    record.tle1 = tle.line1;
    record.tle2 = tle.line2;
    record.lastUpdated = generatedAt;
    updatedEntries += 1;
    if (primaryTle.has(id)) primaryRefreshedEntries += 1;
    else supplementalRefreshedEntries += 1;
  }
  if (updatedEntries === 0) throw new Error('下载结果没有匹配到内置卫星；保留原目录');
  catalogue.offlineSnapshot = generatedAt;
  const summary = validateCatalogue(catalogue);
  const output = `${JSON.stringify(catalogue, null, 2)}\n`;
  const partial = primaryErrors.length > 0;
  const record = { source: 'CelesTrak GP 3LE with SatNOGS supplement', sourceMode: options.sourceMode, sources: sourceManifest, sourceErrors, fetchedAt: generatedAt, sha256: sha256(output), bytes: Buffer.byteLength(output), entries: summary.entries, validTleEntries: summary.validTleCount, refreshedEntries: updatedEntries, primaryRefreshedEntries, supplementalRefreshedEntries, supplementalAvailableEntries, verified: !partial, partial };
  manifest.schema = 1;
  manifest.generatedAt = generatedAt;
  manifest.catalogs = manifest.catalogs ?? {};
  manifest.catalogs.satellites = record;
  if (!options.verifyOnly) {
    await writeJsonAtomically(cataloguePath, catalogue);
    await writeJsonAtomically(manifestPath, manifest);
  }
  console.log(`${options.verifyOnly ? '已验证' : '已更新'}卫星目录：${updatedEntries}/${originalSummary.entries} 条，SHA-256 ${record.sha256}`);
}

async function auditStars(options, manifest) {
  const starDirectory = resolve(root, 'stars/hip_gaia3');
  const expectedFiles = [
    { file: 'stars_0_0v0_21.cat', bytes: 242320, md5: '0e8b8bb5d177c5caad433569140597e9' },
    { file: 'stars_1_0v0_16.cat', bytes: 1037728, md5: '3a7aac6aa540911418ca2c3358e4b489' },
    { file: 'stars_2_0v0_17.cat', bytes: 6804736, md5: '23d59734215dcbc539d9bf13eb4ed7f8' },
    { file: 'stars_3_0v0_10.cat', bytes: 20075344, md5: '39c82706afb12b1a3d08eee92ddef5e5' },
    { file: 'stars_4_1v0_6.cat', bytes: 55759776, md5: 'f5e57f400291d3d0c247ec669b1a4a07' },
  ];
  const files = [];
  for (const expected of expectedFiles) {
    const path = resolve(starDirectory, expected.file);
    try {
      const bytes = (await stat(path)).size;
      const md5 = bytes > 0 ? await hashFile(path, 'md5') : '';
      files.push({ file: expected.file, bytes, expectedBytes: expected.bytes, md5, expectedMd5: expected.md5, valid: bytes === expected.bytes && md5 === expected.md5 });
    } catch {
      files.push({ file: expected.file, bytes: 0, expectedBytes: expected.bytes, md5: '', expectedMd5: expected.md5, valid: false });
    }
  }
  const invalid = files.filter((entry) => !entry.valid).map((entry) => entry.file);
  manifest.catalogs = manifest.catalogs ?? {};
  manifest.catalogs.stars = { source: 'bundled hip_gaia3 catalogs 0-4', checkedAt: new Date().toISOString(), files, verified: invalid.length === 0, largeDownloadAllowed: options.allowLargeStarDownload, limitingMagnitude: 12, note: '内置 stars_0 至 stars_4，覆盖到约 12 等；stars_5 至 stars_8 合计约 4 GiB，不直接打入离线 HAP。' };
  if (!options.verifyOnly) await writeJsonAtomically(manifestPath, manifest);
  console.log(invalid.length === 0 ? `已核对内置星表：${files.length} 个文件，覆盖到约 12 等` : `星表缺失或校验失败：${invalid.join(', ')}`);
}

function catalogEntryCount(value, source) {
  const key = source.catalogKey;
  if (!key) throw new Error(`${source.id}: 注册表缺少 catalogKey`);
  const entries = value?.[key];
  if (!entries || typeof entries !== 'object' || Array.isArray(entries)) throw new Error(`${source.id}: JSON 缺少 ${key} 对象`);
  return Object.keys(entries).length;
}

async function updateBundledCatalogs(options, manifest, registry) {
  manifest.schema = 1;
  manifest.generatedAt = new Date().toISOString();
  manifest.catalogs = manifest.catalogs ?? {};
  const pendingWrites = [];
  for (const sourceId of bundledCatalogSourceIds) {
    const sourceDefinition = getSource(registry, sourceId);
    const source = resolveSource(sourceDefinition, options.sourceMode, { mirrorBaseUrl: options.mirrorBaseUrl, sourceRoot: options.sourceRoot });
    const text = await readResolvedText(source);
    let value;
    try {
      value = JSON.parse(text);
    } catch (error) {
      throw new Error(`${sourceId}: JSON 无法解析：${error.message}`);
    }
    const entries = catalogEntryCount(value, sourceDefinition);
    if (entries < (sourceDefinition.minEntries ?? 1)) throw new Error(`${sourceId}: 目录条数异常：${entries}`);
    const outputPath = resolve(root, sourceDefinition.bundledResource);
    const output = `${JSON.stringify(value, null, 2)}\n`;
    const generatedAt = new Date().toISOString();
    manifest.catalogs[sourceId] = {
      source: sourceId,
      sourceMode: source.resolvedMode,
      resolvedEndpoint: sourceEndpoint(source),
      fetchedAt: generatedAt,
      bytes: Buffer.byteLength(output),
      entries,
      version: value.version ?? null,
      sha256: sha256(output),
      verified: true,
    };
    if (!options.verifyOnly) pendingWrites.push({ outputPath, value });
    console.log(`${options.verifyOnly ? '已验证' : '已更新'} ${sourceId}（${source.resolvedMode}）：${entries} 条，SHA-256 ${sha256(output)}`);
  }
  if (!options.verifyOnly) {
    for (const { outputPath, value } of pendingWrites) await writeJsonAtomically(outputPath, value);
    await writeJsonAtomically(manifestPath, manifest);
  }
}

async function check(options, manifest) {
  const text = await readFile(cataloguePath, 'utf8');
  const summary = validateCatalogue(JSON.parse(text));
  const latest = manifest?.catalogs?.satellites?.fetchedAt;
  const ageDays = latest ? (Date.now() - Date.parse(latest)) / 86400000 : Number.POSITIVE_INFINITY;
  console.log(`卫星目录：${summary.entries} 条，${summary.validTleCount} 条有效 TLE，SHA-256 ${sha256(text)}`);
  if (!latest) console.log('卫星数据清单：尚未由构建机更新脚本生成。');
  else console.log(`卫星数据清单：${latest}，距今 ${ageDays.toFixed(1)} 天${ageDays > options.maxAgeDays ? '，建议在构建机更新' : ''}`);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const registry = await loadOhosSourceRegistry();
  let manifest = await loadManifest();
  if (options.updateSatellites) await updateSatellites(options, manifest, registry);
  if (options.updateSatellites && !options.verifyOnly) manifest = await loadManifest();
  if (options.updateCatalogs) await updateBundledCatalogs(options, manifest, registry);
  if (options.updateCatalogs && !options.verifyOnly) manifest = await loadManifest();
  if (options.updateStars) await auditStars(options, manifest);
  if (options.check || options.verifyOnly) await check(options, manifest);
}

main().catch((error) => { console.error(`失败：${error.message}`); process.exit(1); });
