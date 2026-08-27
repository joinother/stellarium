#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname);
const path = resolve(root, 'data/ohos/network-sources.json');
const registry = JSON.parse(await readFile(path, 'utf8'));
const errors = [];
const ids = new Set();
const modes = new Set(registry.policy?.allowedBuildSources ?? []);

if (registry.schema !== 1) errors.push('schema 必须为 1');
if (registry.policy?.runtime !== 'local-only') errors.push('runtime policy 必须为 local-only');
if (registry.policy?.networkPermissionRequiredAtRuntime !== false) errors.push('运行时网络权限策略必须为 false');
if (!modes.has('local') || !modes.has('mirror') || !modes.has('upstream')) errors.push('必须声明 local、mirror、upstream 三种构建源模式');

for (const source of registry.sources ?? []) {
  if (!source.id || ids.has(source.id)) errors.push(`数据源 ID 重复或为空：${source.id}`);
  ids.add(source.id);
  if (!source.kind || !source.format) errors.push(`${source.id}: 缺少 kind/format`);
  if (!source.upstreamUrl || !/^https?:\/\//.test(source.upstreamUrl)) errors.push(`${source.id}: upstreamUrl 无效`);
  if (!source.mirrorPath?.startsWith('/')) errors.push(`${source.id}: mirrorPath 必须是绝对 API 路径`);
  if (!source.localPath || source.localPath.startsWith('/')) errors.push(`${source.id}: localPath 必须是仓库相对路径`);
  if (!Array.isArray(source.outboundFields)) errors.push(`${source.id}: outboundFields 必须是数组`);
  if (source.runtimeDefault === 'bundled' && source.outboundFields.length > 0) errors.push(`${source.id}: bundled 数据源不能声明外发字段`);
}

if (errors.length) {
  console.error(errors.map((error) => `失败：${error}`).join('\n'));
  process.exit(1);
}

console.log(`HarmonyOS 数据源注册表通过：${registry.sources.length} 项，支持 local/mirror/upstream 构建模式，运行时 local-only。`);
