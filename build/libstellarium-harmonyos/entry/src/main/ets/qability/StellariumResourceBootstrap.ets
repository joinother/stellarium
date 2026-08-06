import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import hilog from '@ohos.hilog';
import i18n from '@ohos.i18n';
import { setEnv } from 'libentry.so';
import { LOG_DOMAIN, LOG_TAG } from '../common/QtAppConstants';

const RAW_ROOT = 'stellarium';
const MARKER = 'stars/hip_gaia3/defaultStarsConfig.json';

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
