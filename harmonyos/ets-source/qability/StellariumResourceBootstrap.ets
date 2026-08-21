import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import hilog from '@ohos.hilog';
import i18n from '@ohos.i18n';
import { setEnv } from 'libentry.so';
import { LOG_DOMAIN, LOG_TAG } from '../common/QtAppConstants';

const RAW_ROOT = 'stellarium';
const MARKER = 'stars/hip_gaia3/defaultStarsConfig.json';
const RAW_NEBULAE_ROOT = `${RAW_ROOT}/nebulae/default`;
const DEEP_SKY_INDEX_FILES: Array<string> = [
  'catalog.dat',
  'names.dat',
  'outlines.dat',
  'discovery.dat',
  'textures.json',
];

let deepSkyExtractionStarted = false;
let deepSkyExtractionForeground = true;

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
  let file: fs.File | undefined = undefined;
  try {
    const content = await appContext.resourceManager.getRawFileContent(rawPath);
    file = await fs.open(outputPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    const data = content.buffer.slice(content.byteOffset, content.byteOffset + content.byteLength) as ArrayBuffer;
    await fs.write(file.fd, data);
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
  if (exists(`${installRoot}/${MARKER}`)) {
    return;
  }

  const startedAt = Date.now();
  hilog.info(LOG_DOMAIN, LOG_TAG, '[startup] asynchronous Stellarium resource extraction started');
  await extractRawTreeAsync(appContext, RAW_ROOT, installRoot);
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
  const completeMarker = `${imageRoot}/.ohos_complete`;
  if (exists(completeMarker)) {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Deep-sky image collection already installed');
    return;
  }
  if (deepSkyExtractionStarted) {
    return;
  }

  let imageNames: Array<string>;
  try {
    imageNames = appContext.resourceManager.getRawFileListSync(RAW_NEBULAE_ROOT)
      .filter((name: string) => name.endsWith('.png'));
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Unable to list deep-sky images: ${JSON.stringify(err)}`);
    return;
  }
  if (imageNames.length === 0) {
    hilog.error(LOG_DOMAIN, LOG_TAG, 'Deep-sky image list is empty; collection will not be marked complete');
    return;
  }

  deepSkyExtractionStarted = true;
  ensureDir(imageRoot);
  let nextIndex = 0;
  let copiedCount = 0;
  let skippedCount = 0;
  let failedCount = 0;
  const copyNext = (): void => {
    if (!deepSkyExtractionForeground) {
      setTimeout(copyNext, 1000);
      return;
    }
    if (nextIndex >= imageNames.length) {
      deepSkyExtractionStarted = false;
      if (failedCount === 0) {
        writeMarker(completeMarker);
      }
      hilog.info(LOG_DOMAIN, LOG_TAG,
        `Deep-sky images installed: copied=${copiedCount}, existing=${skippedCount}, ` +
        `failed=${failedCount}, total=${imageNames.length}`);
      onComplete();
      return;
    }

    const name = imageNames[nextIndex++];
    const outputPath = `${imageRoot}/${name}`;
    try {
      if (fileSize(outputPath) > 0) {
        skippedCount++;
      } else {
        writeRawFile(appContext, `${RAW_NEBULAE_ROOT}/${name}`, outputPath);
        copiedCount++;
      }
    } catch (err) {
      // Keep processing the collection: one corrupt/missing optional image
      // should not make catalogue browsing or the rest of the sky unusable.
      failedCount++;
      hilog.warn(LOG_DOMAIN, LOG_TAG, `Unable to install deep-sky image ${name}: ${JSON.stringify(err)}`);
    }
    if ((nextIndex % 25) === 0 || nextIndex === imageNames.length) {
      hilog.info(LOG_DOMAIN, LOG_TAG,
        `Deep-sky image extraction progress ${nextIndex}/${imageNames.length}`);
    }
    setTimeout(copyNext, 16);
  };

  hilog.info(LOG_DOMAIN, LOG_TAG, `Scheduling ${imageNames.length} deep-sky images after first frame`);
  setTimeout(copyNext, 250);
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

  // Constellation lines / art are driven by skyculture data. If it was
  // missing from a previously extracted build, the toggles report success but
  // draw nothing — force a re-extract so the device actually has the data.
  const skycultureMarker = `${installRoot}/skycultures/modern/index.json`;
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
  if (!needExtract && (!exists(keyQmStellarium) || !exists(keyQmSky) || !exists(keyQmSkyCultures))) {
    hilog.warn(LOG_DOMAIN, LOG_TAG,
      `Marker present but translations incomplete ` +
      `(stellarium=${exists(keyQmStellarium)} sky=${exists(keyQmSky)} ` +
      `skycultures=${exists(keyQmSkyCultures)}); forcing re-extract`);
    needExtract = true;
  }
  if (!needExtract && !exists(skycultureMarker)) {
    hilog.warn(LOG_DOMAIN, LOG_TAG,
      `Marker present but skyculture data missing ` +
      `(${skycultureMarker}); forcing re-extract`);
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
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `Failed to refresh Moon resources: ${JSON.stringify(err)}`);
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
    `stellarium-skycultures/zh_CN.qm=${exists(keyQmSkyCultures)}`);

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
