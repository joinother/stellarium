#!/usr/bin/env node
// 护栏：内置星表字节与其 MD5 配置必须一致。
//
// 为什么需要：`stars/hip_gaia3/defaultStarsConfig.json` 的 `checksum` 是"该 fileName 的确切字节"的
// MD5，`StarMgr` 加载与 `downloadStarCatalog` 下载后都会比对。上游发布新的星表版本时会**同时**
// 改 `fileName` 与 `checksum`；如果我们只同步了配置却没重新下载内置 `.cat`（stars0–stars4），
// 校验就会失败、整级被拒。本脚本在提交前把这种漂移挡住。
//
// 校验：
//   1) 每个 `checked=true` 的级，内置文件必须存在；
//   2) 存在则其 MD5 必须等于 config 的 `checksum`；
//   3) 与 `data/ohos/catalog-manifest.json` 里同名列的 `md5` 也必须一致。
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const starsDir = resolve(root, 'stars/hip_gaia3');
const configPath = resolve(starsDir, 'defaultStarsConfig.json');
const manifestPath = resolve(root, 'data/ohos/catalog-manifest.json');

const config = JSON.parse(readFileSync(configPath, 'utf8'));
const catalogs = config.catalogs ?? [];

const manifestFiles = new Map();
try {
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  for (const entry of manifest.catalogs?.stars?.files ?? []) manifestFiles.set(entry.file, entry);
} catch (error) {
  console.error(`无法读取 catalog-manifest.json：${error.message}`);
  process.exit(1);
}

function md5(path) {
  return createHash('md5').update(readFileSync(path)).digest('hex');
}

const errors = [];
let bundledCount = 0;
for (const catalog of catalogs) {
  const path = resolve(starsDir, catalog.fileName);
  if (!existsSync(path)) {
    if (catalog.checked === true) {
      errors.push(`${catalog.id}: checked=true 但未找到内置文件 ${catalog.fileName}`);
    }
    continue;
  }
  bundledCount += 1;
  const actual = md5(path);
  if (actual !== catalog.checksum) {
    errors.push(`${catalog.id}: ${catalog.fileName} MD5 与 defaultStarsConfig.json 不一致（config=${catalog.checksum}, actual=${actual}）`);
  }
  const manifestEntry = manifestFiles.get(catalog.fileName);
  if (manifestEntry?.md5 && manifestEntry.md5 !== actual) {
    errors.push(`${catalog.id}: ${catalog.fileName} MD5 与 catalog-manifest.json 不一致（manifest=${manifestEntry.md5}, actual=${actual}）`);
  }
}

if (errors.length > 0) {
  console.error('星表 MD5 一致性检查失败：');
  console.error('上游星表更新后，需同步 fileName/checksum 并重新下载内置 .cat（见 docs/harmonyos/specs/STAR-CATALOG-EXTENSION.md §9）。');
  for (const error of errors) console.error('  ' + error);
  process.exit(1);
}
console.log(`星表 MD5 一致性检查通过：${catalogs.length} 级配置，${bundledCount} 个内置文件与 checksum 一致。`);
