#!/usr/bin/env node

import { readFile, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { basename, resolve } from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname);
const registryPath = resolve(root, 'data/ohos/network-sources.json');
const registry = JSON.parse(await readFile(registryPath, 'utf8'));
const bundled = (registry.sources ?? []).filter((source) => source.runtimeDefault === 'bundled');
const errors = [];

function sha256(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

for (const source of bundled) {
  if (!source.bundledResource) {
    errors.push(`${source.id}: 缺少 bundledResource`);
    continue;
  }
  const resourcePath = resolve(root, source.bundledResource);
  try {
    const resource = await readFile(resourcePath);
    if (resource.length === 0) {
      errors.push(`${source.id}: 内置资源为空`);
      continue;
    }
    if (source.format === 'json') {
      try {
        JSON.parse(resource);
      } catch (error) {
        errors.push(`${source.id}: 内置 JSON 无法解析：${error.message}`);
      }
    }
    if (!source.bundledQrc) {
      errors.push(`${source.id}: 缺少 bundledQrc`);
      continue;
    }
    const qrcPath = resolve(root, source.bundledQrc);
    let qrc;
    try {
      qrc = await readFile(qrcPath, 'utf8');
    } catch {
      errors.push(`${source.id}: 缺少同目录 QRC：${qrcPath}`);
      continue;
    }
    if (!new RegExp(`<file>\\s*${basename(resourcePath)}\\s*</file>`).test(qrc)) {
      errors.push(`${source.id}: QRC 未登记 ${basename(resourcePath)}`);
    }
    const metadata = await stat(resourcePath);
    console.log(`${source.id}: bundled=${source.bundledResource}, bytes=${metadata.size}, sha256=${sha256(resource)}`);
  } catch {
    errors.push(`${source.id}: 找不到内置资源 ${source.bundledResource}`);
  }
}

if (errors.length > 0) {
  console.error(errors.map((error) => `失败：${error}`).join('\n'));
  process.exit(1);
}

console.log(`HarmonyOS 离线目录通过：${bundled.length} 项均有可解析的 QRC 内置资源。`);
