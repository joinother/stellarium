import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import hilog from '@ohos.hilog';
import i18n from '@ohos.i18n';
import { setEnv } from 'libentry.so';
import { LOG_DOMAIN, LOG_TAG } from '../common/QtAppConstants';

const RAW_ROOT = 'stellarium';
const MARKER = 'stars/hip_gaia3/defaultStarsConfig.json';
const MULTILINGUAL_SEARCH_INDEX = 'data/search/multilingual-sky-aliases.tsv';
const CATALOG_MANIFEST = 'data/ohos/catalog-manifest.json';
const SKYCULTURE_ART_COMPAT_MARKER = 'data/ohos/.skyculture_art_rgba_v1';
const DEEP_STAR_CATALOG = 'stars/hip_gaia3/stars_4_1v0_6.cat';
const DEEP_STAR_CATALOG_BYTES = 55759776;
const RAW_NEBULAE_ROOT = `${RAW_ROOT}/nebulae/default`;
// The old completion marker was created before the optional image collection
// became upgradeable. Use a new marker and verify the two prominent images so
// an existing filesDir cannot permanently hide an incomplete collection.
const DEEP_SKY_INSTALL_MARKER = '.ohos_complete_v2';
const DEEP_SKY_SENTINELS: Array<string> = ['m31.png', 'n2244.png'];
const DEEP_SKY_PRIORITY_IMAGES: Array<string> = [
  'm31.png', 'm42.png', 'm51-vasey.png', 'm1dumont.png', 'm13.png',
  'pleiades.png', 'n2244.png', 'm8.png', 'm20.png', 'm57dumont.png',
];
const DEEP_SKY_INDEX_FILES: Array<string> = [
  'catalog.dat',
  'names.dat',
  'outlines.dat',
  'discovery.dat',
  'textures.json',
];
const DEEP_SKY_IMAGE_FILE = /^[a-z][a-z0-9_-]*\.png$/i;
const DETAIL_MEDIA_TEXTURE_PATH = /^textures\/[a-z0-9_.-]+\.(?:png|jpe?g|webp)$/i;
const DETAIL_MEDIA_NEBULA_PATH = /^nebulae\/default\/[a-z][a-z0-9_-]*\.png$/i;
const DETAIL_MEDIA_IMAGE_EXTENSION = /\.(?:png|jpe?g|webp)$/i;
const TEXTURE_COMPAT_MARKER = '.ohos_texture_compat_v1';
const TEXTURE_COMPAT_FILES: Array<string> = ['charon.png', 'neptune.png', 'sedna.png', 'uranus.png'];
const DETAIL_MODEL_TEXTURE_MARKER = '.ohos_detail_model_rgba_v2';
const DETAIL_MODEL_TEXTURE_FILES: Array<string> = [
  'sun.png', 'mercury.png', 'venus.png', 'earth_cmap.png', 'moon.png', 'mars.png', 'jupiter.png', 'saturn.png',
  'uranus.png', 'neptune.png', 'pluto.png', 'charon.png', 'ceres.png', 'vesta.png', 'eros.png', 'bennu.png',
  'gaspra.png', 'ida.png', 'sedna.png', 'eris.png', 'haumea.png', 'dysnomia.png', '2007OR10.png', 'phobos.png',
  'deimos.png', 'io.png', 'europa.png', 'ganymede.png', 'callisto.png', 'amalthea.png', 'mimas.png', 'enceladus.png',
  'tethys.png', 'dione.png', 'rhea.png', 'titan.png', 'hyperion.png', 'iapetus.png', 'phoebe.png', 'janus.png',
  'epimetheus.png', 'prometheus.png', 'ariel.png', 'umbriel.png', 'titania.png', 'oberon.png', 'miranda.png',
  'triton.png', 'nereid.png', 'proteus.png',
];
const DETAIL_MODEL_RING_TEXTURE_FILES: Array<string> = [
  'saturn_rings_radial.png', 'uranus_rings.png', 'neptune_rings.png'
];

export interface DeepSkyWarmupStatus {
  state: string
  installed: number
  total: number
  pending: number
  failed: number
  copied: number
  existing: number
  current: string
  foreground: boolean
}

let deepSkyExtractionStarted = false;
let deepSkyExtractionForeground = true;
let deepSkyExtractionTotal = 0;
let deepSkyExtractionFailed = 0;
let deepSkyExtractionCopied = 0;
let deepSkyExtractionExisting = 0;
let deepSkyExtractionCurrent = '';
let deepSkyPackagedTotal = 0;
const detailAssetJobs: Map<string, Promise<string>> = new Map();
const detailAssetPreparationFailures: Set<string> = new Set<string>();
let deepSkyImageNameCache: Array<string> = [];
let deepSkyImageNameCacheReady = false;

function isDeferredStartupAsset(rawPath: string): boolean {
  return rawPath === `${RAW_ROOT}/${DEEP_STAR_CATALOG}`;
}

function isApprovedDetailMediaPath(relativePath: string): boolean {
  if (DETAIL_MEDIA_TEXTURE_PATH.test(relativePath) || DETAIL_MEDIA_NEBULA_PATH.test(relativePath)) {
    return true;
  }
  if (!relativePath.startsWith('skycultures/')) {
    return false;
  }
  const parts = relativePath.split('/');
  if (parts.length < 4 || parts[0] !== 'skycultures' || parts[2] !== 'illustrations') {
    return false;
  }
  // Official artwork contains spaces, '+', parentheses and other punctuation.
  // Reject traversal while preserving those bundled filenames exactly.
  for (const part of parts) {
    if (part.length === 0 || part === '.' || part === '..' || part.indexOf('\\') >= 0) {
      return false;
    }
  }
  return DETAIL_MEDIA_IMAGE_EXTENSION.test(parts[parts.length - 1]);
}

function stellariumSystemLocale(): string {
  let locale = 'zh_CN';
  try {
    locale = i18n.getSystemLocale();
  } catch (err) {
    hilog.warn(LOG_DOMAIN, LOG_TAG, `Unable to read system locale; using ${locale}: ${JSON.stringify(err)}`);
  }

  const normalized = locale.replace(/-/g, '_');
  const lower = normalized.toLowerCase();
  if (lower.startsWith('zh')) {
    if (lower.includes('hant') || lower.includes('_tw') || lower.includes('_hk') || lower.includes('_mo')) {
      return lower.includes('_hk') ? 'zh_HK' : 'zh_TW';
    }
    return 'zh_CN';
  }

  const parts = normalized.split('_');
  if (parts.length >= 2 && parts[0].length >= 2 && parts[1].length === 2) {
    return `${parts[0].toLowerCase()}_${parts[1].toUpperCase()}`;
  }
  return parts[0].toLowerCase() || 'zh_CN';
}

function exists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (_err) {
    return false;
  }
}

function fileSize(path: string): number {
  try {
    return fs.statSync(path).size;
  } catch (_err) {
    return 0;
  }
}

function deepSkyCollectionReady(imageRoot: string): boolean {
  if (!exists(`${imageRoot}/${DEEP_SKY_INSTALL_MARKER}`)) {
    return false;
  }
  for (const name of DEEP_SKY_SENTINELS) {
    if (fileSize(`${imageRoot}/${name}`) <= 0) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, `Deep-sky completion marker present but ${name} is missing`);
      return false;
    }
  }
  return true;
}

function ensureDir(path: string): void {
  if (exists(path)) {
    return;
  }
  try {
    fs.mkdirSync(path, true);
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to create directory ${path}: ${JSON.stringify(err)}`);
    throw new Error(`Failed to create directory: ${path}`);
  }
}

function parentDir(path: string): string {
  const index = path.lastIndexOf('/');
  return index > 0 ? path.substring(0, index) : path;
}

function writeRawFile(appContext: common.ApplicationContext, rawPath: string, outputPath: string): void {
  ensureDir(parentDir(outputPath));
  let file: fs.File | undefined = undefined;
  try {
    const content = appContext.resourceManager.getRawFileContentSync(rawPath);
    file = fs.openSync(outputPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    const data = content.buffer.slice(content.byteOffset, content.byteOffset + content.byteLength);
    fs.writeSync(file.fd, data);
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to write raw resource ${rawPath}: ${JSON.stringify(err)}`);
    throw new Error(`Failed to write raw resource: ${rawPath}`);
  } finally {
    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (err) {
        hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to close resource file ${outputPath}: ${JSON.stringify(err)}`);
      }
    }
  }
}

async function writeRawFileAsync(appContext: common.ApplicationContext, rawPath: string, outputPath: string): Promise<void> {
  ensureDir(parentDir(outputPath));
  const temporaryPath = `${outputPath}.part.${Date.now()}.${Math.floor(Math.random() * 100000)}`;
  let file: fs.File | undefined = undefined;
  try {
    const content = await appContext.resourceManager.getRawFileContent(rawPath);
    file = await fs.open(temporaryPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    const data = content.buffer.slice(content.byteOffset, content.byteOffset + content.byteLength) as ArrayBuffer;
    await fs.write(file.fd, data);
    await fs.close(file);
    file = undefined;
    await fs.rename(temporaryPath, outputPath);
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to asynchronously write raw resource ${rawPath}: ${JSON.stringify(err)}`);
    throw new Error(`Failed to write raw resource: ${rawPath}`);
  } finally {
    if (file !== undefined) {
      try {
        await fs.close(file);
      } catch (err) {
        hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to close resource file ${outputPath}: ${JSON.stringify(err)}`);
      }
    }
    try {
      if (exists(temporaryPath)) {
        fs.unlinkSync(temporaryPath);
      }
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, `Failed to remove temporary resource file ${temporaryPath}: ${JSON.stringify(err)}`);
    }
  }
}

function writeMarker(path: string): void {
  ensureDir(parentDir(path));
  let file: fs.File | undefined = undefined;
  try {
    file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to write resource marker ${path}: ${JSON.stringify(err)}`);
    throw new Error(`Failed to write resource marker: ${path}`);
  } finally {
    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (err) {
        hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to close resource marker ${path}: ${JSON.stringify(err)}`);
      }
    }
  }
}

function refreshTextureCompatibility(
  appContext: common.ApplicationContext,
  installRoot: string,
): void {
  const textureRoot = `${installRoot}/textures`;
  const markerPath = `${textureRoot}/${TEXTURE_COMPAT_MARKER}`;
  if (exists(markerPath)) {
    return;
  }
  const startedAt = Date.now();
  hilog.info(LOG_DOMAIN, LOG_TAG, `[startup] refreshing ${TEXTURE_COMPAT_FILES.length} normalized planet textures`);
  for (const name of TEXTURE_COMPAT_FILES) {
    writeRawFile(appContext, `${RAW_ROOT}/textures/${name}`, `${textureRoot}/${name}`);
  }
  writeMarker(markerPath);
  hilog.info(LOG_DOMAIN, LOG_TAG,
    `[startup] normalized planet textures ready in ${Date.now() - startedAt} ms`);
}

function refreshDetailModelTextures(
  appContext: common.ApplicationContext,
  installRoot: string,
): void {
  const textureRoot = `${installRoot}/textures`;
  const markerPath = `${textureRoot}/${DETAIL_MODEL_TEXTURE_MARKER}`;
  if (exists(markerPath)) {
    return;
  }
  const startedAt = Date.now();
  hilog.info(LOG_DOMAIN, LOG_TAG,
    `[startup] installing ${DETAIL_MODEL_TEXTURE_FILES.length} CPU-readable detail-model textures`);
  for (const name of DETAIL_MODEL_TEXTURE_FILES) {
    writeRawFile(appContext, `${RAW_ROOT}/textures/${name}.model.rgba`, `${textureRoot}/${name}.model.rgba`);
  }
  for (const name of DETAIL_MODEL_RING_TEXTURE_FILES) {
    writeRawFile(appContext, `${RAW_ROOT}/textures/${name}.model.rgba`, `${textureRoot}/${name}.model.rgba`);
  }
  writeMarker(markerPath);
  hilog.info(LOG_DOMAIN, LOG_TAG,
    `[startup] detail-model textures ready in ${Date.now() - startedAt} ms`);
}

function extractRawTree(appContext: common.ApplicationContext, rawDir: string, outputDir: string): void {
  ensureDir(outputDir);
  let entries: Array<string>;
  try {
    entries = appContext.resourceManager.getRawFileListSync(rawDir);
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to list raw resource directory ${rawDir}: ${JSON.stringify(err)}`);
    throw new Error(`Failed to list raw resource directory: ${rawDir}`);
  }
  for (const entry of entries) {
    // Deep-sky PNGs are intentionally copied after the first rendered frame.
    // Copying their 140 MiB tree here blocks the API 22 ability startup long
    // enough for the watchdog to terminate the process.
    if (rawDir === RAW_ROOT && entry === 'nebulae') {
      continue;
    }
    const rawPath = rawDir.length > 0 ? `${rawDir}/${entry}` : entry;
    const outputPath = `${outputDir}/${entry}`;
    if (isDeferredStartupAsset(rawPath)) {
      continue;
    }
    try {
      appContext.resourceManager.getRawFileListSync(rawPath);
      extractRawTree(appContext, rawPath, outputPath);
    } catch (_err) {
      writeRawFile(appContext, rawPath, outputPath);
    }
  }
}

async function extractRawTreeAsync(appContext: common.ApplicationContext, rawDir: string, outputDir: string): Promise<void> {
  ensureDir(outputDir);
  let entries: Array<string>;
  try {
    entries = await appContext.resourceManager.getRawFileList(rawDir);
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to list raw resource directory ${rawDir}: ${JSON.stringify(err)}`);
    throw new Error(`Failed to list raw resource directory: ${rawDir}`);
  }

  for (const entry of entries) {
    if (rawDir === RAW_ROOT && entry === 'nebulae') {
      continue;
    }
    const rawPath = rawDir.length > 0 ? `${rawDir}/${entry}` : entry;
    const outputPath = `${outputDir}/${entry}`;
    if (isDeferredStartupAsset(rawPath)) {
      continue;
    }
    try {
      await appContext.resourceManager.getRawFileList(rawPath);
      await extractRawTreeAsync(appContext, rawPath, outputPath);
    } catch (_err) {
      await writeRawFileAsync(appContext, rawPath, outputPath);
    }
  }
}

export async function prepareStellariumResourcesAsync(appContext: common.ApplicationContext): Promise<void> {
  const installRoot = `${appContext.filesDir}/stellarium`;
  const manifestPath = `${installRoot}/${CATALOG_MANIFEST}`;
  const deepStarPath = `${installRoot}/${DEEP_STAR_CATALOG}`;
  if (exists(`${installRoot}/${MARKER}`)) {
    await writeRawFileAsync(appContext, `${RAW_ROOT}/${CATALOG_MANIFEST}`, manifestPath);
    await writeRawFileAsync(appContext, `${RAW_ROOT}/translations/stellarium-scripts/zh_CN.qm`,
      `${installRoot}/translations/stellarium-scripts/zh_CN.qm`);
    hilog.info(LOG_DOMAIN, LOG_TAG, '[startup] refreshed bundled catalogue manifest and script translation');
    const indexPath = `${installRoot}/${MULTILINGUAL_SEARCH_INDEX}`;
    if (!exists(indexPath)) {
      await writeRawFileAsync(appContext, `${RAW_ROOT}/${MULTILINGUAL_SEARCH_INDEX}`, indexPath);
      hilog.info(LOG_DOMAIN, LOG_TAG, '[startup] installed multilingual search index for existing resources');
    }
    if (fileSize(deepStarPath) !== DEEP_STAR_CATALOG_BYTES) {
      const startedAt = Date.now();
      hilog.info(LOG_DOMAIN, LOG_TAG, '[startup] installing upgraded stars_4 catalogue asynchronously');
      await writeRawFileAsync(appContext, `${RAW_ROOT}/${DEEP_STAR_CATALOG}`, deepStarPath);
      if (fileSize(deepStarPath) !== DEEP_STAR_CATALOG_BYTES) {
        throw new Error(`Deep star catalogue size mismatch: ${fileSize(deepStarPath)}`);
      }
      hilog.info(LOG_DOMAIN, LOG_TAG,
        `[startup] installed upgraded stars_4 catalogue in ${Date.now() - startedAt} ms`);
    }
    return;
  }

  const startedAt = Date.now();
  hilog.info(LOG_DOMAIN, LOG_TAG, '[startup] asynchronous Stellarium resource extraction started');
  await extractRawTreeAsync(appContext, RAW_ROOT, installRoot);
  await writeRawFileAsync(appContext, `${RAW_ROOT}/${DEEP_STAR_CATALOG}`, deepStarPath);
  if (fileSize(deepStarPath) !== DEEP_STAR_CATALOG_BYTES) {
    throw new Error(`Deep star catalogue size mismatch: ${fileSize(deepStarPath)}`);
  }
  hilog.info(LOG_DOMAIN, LOG_TAG,
    `[startup] asynchronous Stellarium resource extraction completed in ${Date.now() - startedAt} ms`);
}

function copyDeepSkyIndexes(appContext: common.ApplicationContext, installRoot: string): void {
  for (const name of DEEP_SKY_INDEX_FILES) {
    writeRawFile(appContext, `${RAW_NEBULAE_ROOT}/${name}`, `${installRoot}/nebulae/default/${name}`);
  }
}

/**
 * Resource extraction is application work, so it must stop while the ability
 * is backgrounded. QAbility keeps this flag in sync with its lifecycle.
 */
export function setDeepSkyImageExtractionForeground(foreground: boolean): void {
  deepSkyExtractionForeground = foreground;
}

/**
 * Makes one verified detail image available immediately after the user selects
 * its object. This reads only the packaged rawfile and does not wait for the
 * optional background collection pass to reach the requested image.
 */
export async function ensureDeepSkyDetailImage(
  appContext: common.ApplicationContext,
  imageName: string,
): Promise<boolean> {
  if (!DEEP_SKY_IMAGE_FILE.test(imageName)) {
    hilog.warn(LOG_DOMAIN, LOG_TAG, `[detail-media] rejected invalid image name: ${imageName}`);
    return false;
  }
  return ensureStellariumDetailMediaAsset(appContext, `nebulae/default/${imageName}`);
}

function packagedDeepSkyImageNames(appContext: common.ApplicationContext): Array<string> {
  if (deepSkyImageNameCacheReady) {
    return deepSkyImageNameCache;
  }
  try {
    deepSkyImageNameCache = appContext.resourceManager.getRawFileListSync(RAW_NEBULAE_ROOT)
      .filter((name: string) => DEEP_SKY_IMAGE_FILE.test(name));
    deepSkyPackagedTotal = deepSkyImageNameCache.length;
    deepSkyImageNameCacheReady = true;
    hilog.info(LOG_DOMAIN, LOG_TAG, `[detail-media] indexed packaged deep-sky images=${deepSkyPackagedTotal}`);
    return deepSkyImageNameCache;
  } catch (err) {
    hilog.warn(LOG_DOMAIN, LOG_TAG, `[detail-media] unable to list packaged deep-sky images: ${JSON.stringify(err)}`);
    return [];
  }
}

export function getDeepSkyResourceWarmupStatus(appContext: common.ApplicationContext): DeepSkyWarmupStatus {
  const imageRoot = `${appContext.filesDir}/stellarium/nebulae/default`;
  let installed = 0;
  try {
    installed = fs.listFileSync(imageRoot).filter((name: string) =>
      DEEP_SKY_IMAGE_FILE.test(name) && fileSize(`${imageRoot}/${name}`) > 0).length;
  } catch (_err) {
    installed = 0;
  }
  if (deepSkyPackagedTotal === 0) {
    packagedDeepSkyImageNames(appContext);
  }
  const total = deepSkyExtractionTotal > 0
    ? deepSkyExtractionTotal
    : (deepSkyPackagedTotal > 0 ? deepSkyPackagedTotal : installed);
  const pending = Math.max(0, total - installed);
  return {
    state: deepSkyExtractionStarted ? 'warming' :
      (pending === 0 && total > 0 && deepSkyExtractionFailed === 0
        ? 'ready'
        : (deepSkyExtractionFailed > 0 ? 'failed' : 'partial')),
    installed: installed,
    total: total,
    pending: pending,
    failed: deepSkyExtractionFailed,
    copied: deepSkyExtractionCopied,
    existing: deepSkyExtractionExisting,
    current: deepSkyExtractionCurrent,
    foreground: deepSkyExtractionForeground,
  };
}

function resolvePackagedDeepSkyPath(
  appContext: common.ApplicationContext,
  relativePath: string,
): string {
  const prefix = 'nebulae/default/';
  if (!relativePath.startsWith(prefix)) {
    if (!DETAIL_MEDIA_TEXTURE_PATH.test(relativePath)) {
      return '';
    }
    try {
      appContext.resourceManager.getRawFileContentSync(`${RAW_ROOT}/${relativePath}`);
      return relativePath;
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        `[detail-media] packaged texture missing requested=${relativePath}: ${JSON.stringify(err)}`);
      return '';
    }
  }

  const requestedName = relativePath.substring(prefix.length);
  const requestedLower = requestedName.toLowerCase();
  const imageNames = packagedDeepSkyImageNames(appContext);
  if (imageNames.length === 0) {
    return '';
  }

  const exactName = imageNames.find((name: string) => name.toLowerCase() === requestedLower);
  if (exactName !== undefined) {
    return `${prefix}${exactName}`;
  }

  const requestedStem = requestedLower.substring(0, requestedLower.length - '.png'.length);
  const candidates = imageNames.filter((name: string) => {
    const lower = name.toLowerCase();
    const stem = lower.substring(0, lower.length - '.png'.length);
    if (!stem.startsWith(requestedStem) || stem.length === requestedStem.length) {
      return false;
    }
    const suffixFirst = stem.charAt(requestedStem.length);
    return suffixFirst < '0' || suffixFirst > '9';
  }).sort((left: string, right: string) => left.length - right.length || left.localeCompare(right));
  return candidates.length > 0 ? `${prefix}${candidates[0]}` : '';
}

/**
 * Resolves and installs one approved detail asset, returning the actual path.
 * Some bundled deep-sky filenames carry a source suffix (for example
 * m51-vasey.png), so callers must use this result instead of the requested
 * catalogue stem.
 */
export async function resolveStellariumDetailMediaAsset(
  appContext: common.ApplicationContext,
  relativePath: string,
): Promise<string> {
  if (!isApprovedDetailMediaPath(relativePath)) {
    hilog.warn(LOG_DOMAIN, LOG_TAG, `[detail-media] rejected invalid asset path: ${relativePath}`);
    return '';
  }
  const resolvedPath = resolvePackagedDeepSkyPath(appContext, relativePath);
  if (resolvedPath.length === 0) {
    hilog.warn(LOG_DOMAIN, LOG_TAG, `[detail-media] package missing requested=${relativePath}`);
    return '';
  }
  const jobKey = `${appContext.filesDir}/stellarium/${resolvedPath}`;
  const existingJob = detailAssetJobs.get(jobKey);
  if (existingJob !== undefined) {
    return existingJob;
  }
  const job = resolveStellariumDetailMediaAssetInternal(appContext, relativePath, resolvedPath);
  detailAssetJobs.set(jobKey, job);
  job.then(() => {
    detailAssetJobs.delete(jobKey);
  }, () => {
    detailAssetJobs.delete(jobKey);
  });
  return job;
}

async function resolveStellariumDetailMediaAssetInternal(
  appContext: common.ApplicationContext,
  relativePath: string,
  resolvedPath: string,
): Promise<string> {
  const outputPath = `${appContext.filesDir}/stellarium/${resolvedPath}`;
  const jobKey = outputPath;
  if (fileSize(outputPath) > 0) {
    detailAssetPreparationFailures.delete(jobKey);
    hilog.info(LOG_DOMAIN, LOG_TAG,
      `[detail-media] requested=${relativePath} resolved=${resolvedPath} source=filesDir`);
    return resolvedPath;
  }
  try {
    await writeRawFileAsync(appContext, `${RAW_ROOT}/${resolvedPath}`, outputPath);
    if (fileSize(outputPath) <= 0) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        `[detail-media] requested=${relativePath} resolved=${resolvedPath} source=package result=empty`);
      throw new Error(`Detail media file is empty: ${resolvedPath}`);
    }
    hilog.info(LOG_DOMAIN, LOG_TAG,
      `[detail-media] requested=${relativePath} resolved=${resolvedPath} source=package result=copied`);
    detailAssetPreparationFailures.delete(jobKey);
    return resolvedPath;
  } catch (err) {
    detailAssetPreparationFailures.add(jobKey);
    hilog.warn(LOG_DOMAIN, LOG_TAG,
      `[detail-media] requested=${relativePath} resolved=${resolvedPath} source=package result=unavailable: ${JSON.stringify(err)}`);
    throw new Error(`Failed to install detail media: ${resolvedPath}`);
  }
}

/**
 * Copies one approved object-detail asset from the package into filesDir. The
 * caller may only request deep-sky images or culture illustration paths; this
 * keeps UI-provided paths inside the read-only resource bundle.
 */
export async function ensureStellariumDetailMediaAsset(
  appContext: common.ApplicationContext,
  relativePath: string,
): Promise<boolean> {
  return (await resolveStellariumDetailMediaAsset(appContext, relativePath)).length > 0;
}

export function isStellariumDetailMediaPreparationFailed(
  appContext: common.ApplicationContext,
  relativePath: string,
): boolean {
  const resolvedPath = resolvePackagedDeepSkyPath(appContext, relativePath);
  return resolvedPath.length > 0 && detailAssetPreparationFailures.has(
    `${appContext.filesDir}/stellarium/${resolvedPath}`);
}

/**
 * Install the optional deep-sky image collection without delaying startup.
 * The catalogue indexes are already present when this runs. One image per
 * turn keeps the ArkUI thread responsive on API 22 and permits an interrupted
 * installation to resume on the next foreground session.
 */
export function scheduleDeepSkyImageExtraction(
  appContext: common.ApplicationContext,
  onComplete: () => void,
): void {
  const installRoot = `${appContext.filesDir}/stellarium`;
  const imageRoot = `${installRoot}/nebulae/default`;
  const completeMarker = `${imageRoot}/${DEEP_SKY_INSTALL_MARKER}`;
  if (deepSkyCollectionReady(imageRoot)) {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Deep-sky image collection already installed');
    return;
  }
  if (deepSkyExtractionStarted) {
    return;
  }

  let imageNames: Array<string>;
  try {
    const availableImageNames = packagedDeepSkyImageNames(appContext);
    const priorityNames: Array<string> = [];
    for (const priorityName of DEEP_SKY_PRIORITY_IMAGES) {
      const match = availableImageNames.find((name: string) => name.toLowerCase() === priorityName.toLowerCase());
      if (match !== undefined && !priorityNames.includes(match)) {
        priorityNames.push(match);
      }
    }
    imageNames = priorityNames.concat(
      availableImageNames.filter((name: string) => !priorityNames.includes(name)));
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Unable to list deep-sky images: ${JSON.stringify(err)}`);
    return;
  }
  if (imageNames.length === 0) {
    hilog.error(LOG_DOMAIN, LOG_TAG, 'Deep-sky image list is empty; collection will not be marked complete');
    deepSkyExtractionTotal = 0;
    deepSkyExtractionFailed = 1;
    return;
  }

  deepSkyExtractionTotal = imageNames.length;
  deepSkyExtractionFailed = 0;
  deepSkyExtractionCopied = 0;
  deepSkyExtractionExisting = 0;
  deepSkyExtractionCurrent = '';
  deepSkyExtractionStarted = true;
  ensureDir(imageRoot);
  let nextIndex = 0;
  let copiedCount = 0;
  let skippedCount = 0;
  let failedCount = 0;
  let priorityReloadRequested = false;
  const priorityCount = Math.min(DEEP_SKY_PRIORITY_IMAGES.length, imageNames.length);
  const copyNext = async (): Promise<void> => {
    if (!deepSkyExtractionForeground) {
      setTimeout(copyNext, 1000);
      return;
    }
    if (nextIndex >= imageNames.length) {
      deepSkyExtractionStarted = false;
      deepSkyExtractionCurrent = '';
      deepSkyExtractionFailed = failedCount;
      if (failedCount === 0) {
        writeMarker(completeMarker);
      }
      hilog.info(LOG_DOMAIN, LOG_TAG,
        `[deep-sky-warmup] finished copied=${copiedCount}, existing=${skippedCount}, ` +
        `failed=${failedCount}, total=${imageNames.length}`);
      onComplete();
      return;
    }

    const name = imageNames[nextIndex++];
    deepSkyExtractionCurrent = name;
    const outputPath = `${imageRoot}/${name}`;
    try {
      if (fileSize(outputPath) > 0) {
        skippedCount++;
        deepSkyExtractionExisting = skippedCount;
        hilog.info(LOG_DOMAIN, LOG_TAG,
          `[deep-sky-warmup] file=${name} result=existing index=${nextIndex}/${imageNames.length}`);
      } else {
        const installed = await ensureStellariumDetailMediaAsset(
          appContext, `nebulae/default/${name}`);
        if (!installed) {
          throw new Error(`Deep-sky image was not installed: ${name}`);
        }
        copiedCount++;
        deepSkyExtractionCopied = copiedCount;
        hilog.info(LOG_DOMAIN, LOG_TAG,
          `[deep-sky-warmup] file=${name} result=success index=${nextIndex}/${imageNames.length}`);
      }
    } catch (err) {
      // Keep processing the collection: one corrupt/missing optional image
      // should not make catalogue browsing or the rest of the sky unusable.
      failedCount++;
      deepSkyExtractionFailed = failedCount;
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        `[deep-sky-warmup] file=${name} result=failure index=${nextIndex}/${imageNames.length}: ${JSON.stringify(err)}`);
    }
    if ((nextIndex % 25) === 0 || nextIndex === imageNames.length) {
      hilog.info(LOG_DOMAIN, LOG_TAG,
        `Deep-sky image extraction progress ${nextIndex}/${imageNames.length}`);
    }
    if (!priorityReloadRequested && nextIndex >= priorityCount) {
      priorityReloadRequested = true;
      hilog.info(LOG_DOMAIN, LOG_TAG,
        `Priority deep-sky images ready: ${priorityCount}; requesting an early texture reload`);
      onComplete();
    }
    setTimeout(() => { void copyNext(); }, 16);
  };

  hilog.info(LOG_DOMAIN, LOG_TAG, `Scheduling ${imageNames.length} deep-sky images after first frame`);
  setTimeout(() => { void copyNext(); }, 250);
}

export function prepareStellariumResources(appContext: common.ApplicationContext): string {
  const installRoot = `${appContext.filesDir}/stellarium`;
  const markerPath = `${installRoot}/${MARKER}`;
  const userDir = `${appContext.filesDir}/stellarium_userdir`;
  const userConfigPath = `${userDir}/config.ini`;
  const userStarsConfigPath = `${userDir}/stars/hip_gaia3/starsConfig.json`;
  const translationsDir = `${installRoot}/translations`;
  // Star/UI names live in these per-domain .qm files. The one-time extraction
  // is gated only by the marker file; if a previous run was interrupted, the
  // marker can exist while the translations tree is missing/partial. Without
  // this extra check, localization silently never works and no error is raised.
  const keyQmStellarium = `${translationsDir}/stellarium/zh_CN.qm`;
  const keyQmSky = `${translationsDir}/stellarium-sky/zh_CN.qm`;
  const keyQmSkyCultures = `${translationsDir}/stellarium-skycultures/zh_CN.qm`;
  const keyQmScripts = `${translationsDir}/stellarium-scripts/zh_CN.qm`;

  // Constellation lines / art are driven by skyculture data. If it was
  // missing from a previously extracted build, the toggles report success but
  // draw nothing — force a re-extract so the device actually has the data.
  const skycultureMarker = `${installRoot}/skycultures/modern/index.json`;
  const skycultureArtworkMarker = `${installRoot}/skycultures/modern/illustrations/andromeda.png`;
  const skycultureArtCompatibilityMarker = `${installRoot}/${SKYCULTURE_ART_COMPAT_MARKER}`;
  // Sky-tour scripts. Builds made before the scripts/ rawfile fix shipped zero
  // .ssc files, so an upgraded install would keep an empty Scripts panel forever
  // unless the missing directory itself forces a re-extract.
  const scriptMarker = `${installRoot}/scripts/constellations_tour.ssc`;
  // The deep-sky indexes are startup-critical because Browse Categories use
  // them immediately. The PNG collection is deliberately installed later.
  const nebulaeMarker = `${installRoot}/nebulae/default/catalog.dat`;
  // Qt creates the user config by copying this file during its own startup.
  // A HAP update preserves filesDir, so a previously interrupted extraction
  // can leave the generic marker behind while this mandatory source file is
  // missing. Qt treats that copy failure as fatal and aborts the process.
  const defaultConfigPath = `${installRoot}/data/default_cfg.ini`;

  let needExtract = !exists(markerPath);
  if (!needExtract && (!exists(keyQmStellarium) || !exists(keyQmSky) || !exists(keyQmSkyCultures) || !exists(keyQmScripts))) {
    hilog.warn(LOG_DOMAIN, LOG_TAG,
      `Marker present but translations incomplete ` +
      `(stellarium=${exists(keyQmStellarium)} sky=${exists(keyQmSky)} ` +
      `skycultures=${exists(keyQmSkyCultures)} scripts=${exists(keyQmScripts)}); forcing re-extract`);
    needExtract = true;
  }
  if (!needExtract && !exists(skycultureMarker)) {
    hilog.warn(LOG_DOMAIN, LOG_TAG,
      `Marker present but skyculture data missing ` +
      `(${skycultureMarker}); forcing re-extract`);
    needExtract = true;
  }
  if (!needExtract && !exists(skycultureArtworkMarker)) {
    hilog.warn(LOG_DOMAIN, LOG_TAG,
      `Marker present but skyculture artwork is missing (${skycultureArtworkMarker}); forcing re-extract`);
    needExtract = true;
  }
  if (!needExtract && !exists(skycultureArtCompatibilityMarker)) {
    hilog.warn(LOG_DOMAIN, LOG_TAG,
      `Marker present but skyculture artwork compatibility is outdated ` +
      `(${skycultureArtCompatibilityMarker}); forcing re-extract`);
    needExtract = true;
  }
  if (!needExtract && !exists(scriptMarker)) {
    hilog.warn(LOG_DOMAIN, LOG_TAG,
      `Marker present but sky-tour scripts missing ` +
      `(${scriptMarker}); forcing re-extract`);
    needExtract = true;
  }
  if (!needExtract && !exists(defaultConfigPath)) {
    hilog.warn(LOG_DOMAIN, LOG_TAG,
      `Marker present but default configuration is missing (${defaultConfigPath}); forcing re-extract`);
    needExtract = true;
  }

  if (needExtract) {
    hilog.info(LOG_DOMAIN, LOG_TAG, `Extracting Stellarium raw resources to ${installRoot}`);
    extractRawTree(appContext, RAW_ROOT, installRoot);
  }

  // HAP updates preserve filesDir. Refresh these small, mandatory records on
  // every start so upgraded installs can browse the restored categories even
  // while the optional image collection is still being installed.
  try {
    copyDeepSkyIndexes(appContext, installRoot);
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to refresh deep-sky indexes: ${JSON.stringify(err)}`);
  }
  hilog.info(LOG_DOMAIN, LOG_TAG,
    `Deep-sky catalogue on disk: ${nebulaeMarker}, size=${fileSize(nebulaeMarker)}`);

  // HAP updates preserve filesDir. Refresh startup-critical files even when
  // an older install passes the extraction marker. In particular Qt aborts if
  // default_cfg.ini is absent when it first creates the user configuration.
  try {
    writeRawFile(appContext, `${RAW_ROOT}/data/default_cfg.ini`, defaultConfigPath);
    writeRawFile(appContext, `${RAW_ROOT}/data/ssystem_major.ini`, `${installRoot}/data/ssystem_major.ini`);
    writeRawFile(appContext, `${RAW_ROOT}/textures/moon.png`, `${installRoot}/textures/moon.png`);
    writeRawFile(appContext, `${RAW_ROOT}/textures/moon_normals.png`, `${installRoot}/textures/moon_normals.png`);
    writeRawFile(appContext, `${RAW_ROOT}/textures/moon_horizon.png`, `${installRoot}/textures/moon_horizon.png`);
    writeRawFile(appContext, `${RAW_ROOT}/translations/stellarium-scripts/zh_CN.qm`, keyQmScripts);
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to refresh Moon resources: ${JSON.stringify(err)}`);
  }

  try {
    refreshTextureCompatibility(appContext, installRoot);
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to refresh normalized planet textures: ${JSON.stringify(err)}`);
  }

  try {
    refreshDetailModelTextures(appContext, installRoot);
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to refresh detail-model textures: ${JSON.stringify(err)}`);
  }

  // On API 24, Qt can locate default_cfg.ini but QFile::copy() fails when it
  // creates the first config.ini across the HarmonyOS sandbox file layer. Do
  // the one-time copy through ArkUI's file API before Qt starts instead.
  ensureDir(userDir);
  if (!exists(userConfigPath)) {
    writeRawFile(appContext, `${RAW_ROOT}/data/default_cfg.ini`, userConfigPath);
    hilog.info(LOG_DOMAIN, LOG_TAG, `Created initial user configuration at ${userConfigPath}`);
  }

  // StarMgr creates this writable configuration with QFile::copy() on its
  // first startup. That operation can silently fail on API 24, leaving the
  // primary star catalog empty and consequently disabling constellation and
  // named-star lookup. Create it through ArkUI before Qt initializes.
  if (!exists(userStarsConfigPath)) {
    writeRawFile(appContext, `${RAW_ROOT}/stars/hip_gaia3/defaultStarsConfig.json`, userStarsConfigPath);
    hilog.info(LOG_DOMAIN, LOG_TAG, `Created initial star catalog configuration at ${userStarsConfigPath}`);
  }

  // Observable proof that localization data is on disk, so "star names don't
  // translate" can be diagnosed from logs instead of being invisible.
  hilog.info(LOG_DOMAIN, LOG_TAG,
    `Translations on disk: dir=${exists(translationsDir)} ` +
    `stellarium/zh_CN.qm=${exists(keyQmStellarium)} ` +
    `stellarium-sky/zh_CN.qm=${exists(keyQmSky)} ` +
    `stellarium-skycultures/zh_CN.qm=${exists(keyQmSkyCultures)} ` +
    `stellarium-scripts/zh_CN.qm=${exists(keyQmScripts)}`);

  const envSet = setEnv('STELLARIUM_DATA_ROOT', installRoot);
  hilog.info(LOG_DOMAIN, LOG_TAG, `STELLARIUM_DATA_ROOT=${installRoot}, setEnv=${envSet}`);
  // Qt's default home directory is not a stable writable app-data location on
  // every HarmonyOS release. The star manager stores starsConfig.json there;
  // when that copy silently fails it starts with zero HIP stars and therefore
  // no constellations. Keep it in the app sandbox on every supported API.
  const userDirSet = setEnv('STEL_USERDIR', userDir);
  hilog.info(LOG_DOMAIN, LOG_TAG, `STEL_USERDIR=${userDir}, setEnv=${userDirSet}`);
  const frameDirSet = setEnv('STELLARIUM_OHOS_FRAME_DIR', appContext.filesDir);
  hilog.info(LOG_DOMAIN, LOG_TAG, `STELLARIUM_OHOS_FRAME_DIR=${appContext.filesDir}, setEnv=${frameDirSet}`);
  const locale = stellariumSystemLocale();
  const localeSet = setEnv('STELLARIUM_OHOS_LOCALE', locale);
  hilog.info(LOG_DOMAIN, LOG_TAG, `STELLARIUM_OHOS_LOCALE=${locale}, setEnv=${localeSet}`);
  const widgetsRhiSet = setEnv('QT_WIDGETS_RHI', '0');
  hilog.info(LOG_DOMAIN, LOG_TAG, `QT_WIDGETS_RHI=0, setEnv=${widgetsRhiSet}`);
  const childRhiSet = setEnv('QT_WIDGETS_NO_CHILD_RHI', '1');
  hilog.info(LOG_DOMAIN, LOG_TAG, `QT_WIDGETS_NO_CHILD_RHI=1, setEnv=${childRhiSet}`);
  const glBackingStoreSet = setEnv('io.qt.experimental.enableGlBackingStore', '1');
  hilog.info(LOG_DOMAIN, LOG_TAG, `io.qt.experimental.enableGlBackingStore=1, setEnv=${glBackingStoreSet}`);
  const vsyncSoftwareBackingStoreSet = setEnv('io.qt.experimental.enableVsyncOnSoftwareBackingStore', '1');
  hilog.info(LOG_DOMAIN, LOG_TAG, `io.qt.experimental.enableVsyncOnSoftwareBackingStore=1, setEnv=${vsyncSoftwareBackingStoreSet}`);
  const onscreenPaintSet = setEnv('QT_ONSCREEN_PAINT', '1');
  hilog.info(LOG_DOMAIN, LOG_TAG, `QT_ONSCREEN_PAINT=1, setEnv=${onscreenPaintSet}`);
  return installRoot;
}
