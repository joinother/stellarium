#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const registry = JSON.parse(await readFile(resolve(root, 'data/ohos/network-sources.json'), 'utf8'));
const matrix = JSON.parse(await readFile(resolve(root, 'data/ohos/network-localization.json'), 'utf8'));
const errors = [];
const sourceIds = new Set((registry.sources ?? []).map((source) => source.id));
const capabilityIds = new Set();
const allowedStates = new Set(['bundled-local', 'build-mirror', 'user-local', 'user-online-pending', 'local-device', 'platform-pending', 'not-localizable']);

if (matrix.schema !== 1) errors.push('network-localization.json schema 必须为 1');
if (matrix.policy?.onlineBuildMeans !== 'permission-and-code-path-only') errors.push('必须明确 online build 不等于全部服务已启用');

for (const capability of matrix.capabilities ?? []) {
  if (!capability.id || capabilityIds.has(capability.id)) errors.push(`能力 ID 重复或为空：${capability.id}`);
  capabilityIds.add(capability.id);
  if (!allowedStates.has(capability.state)) errors.push(`${capability.id}: 未知本地化状态 ${capability.state}`);
  if (!capability.name || !capability.localFallback || !capability.trigger || !capability.nextAction) errors.push(`${capability.id}: 缺少逐项检查字段`);
  if (!Array.isArray(capability.outboundFields)) errors.push(`${capability.id}: outboundFields 必须是数组`);
  if (capability.sourceId !== null && !sourceIds.has(capability.sourceId)) errors.push(`${capability.id}: sourceId 未在 network-sources.json 注册`);
  if (capability.state === 'bundled-local' && !capability.localFallback.includes('/')) errors.push(`${capability.id}: bundled-local 必须有随包资源回退`);
  if (capability.outboundFields.length > 0 && capability.state === 'bundled-local') errors.push(`${capability.id}: 随包资源不能声明运行时外发字段`);
}

for (const source of registry.sources ?? []) {
  const capability = (matrix.capabilities ?? []).find((item) => item.sourceId === source.id);
  if (!capability) errors.push(`${source.id}: 没有对应的本地化检查条目`);
  if (source.runtimeDefault === 'bundled' && capability?.state !== 'bundled-local') errors.push(`${source.id}: bundled 数据源必须保持 bundled-local 回退`);
}

const summary = {};
for (const capability of matrix.capabilities ?? []) summary[capability.state] = (summary[capability.state] ?? 0) + 1;
if (errors.length) {
  console.error(errors.map((error) => `失败：${error}`).join('\n'));
  process.exit(1);
}

console.log(`联网本地化逐项审计通过：${matrix.capabilities.length} 项能力，${registry.sources.length} 项注册数据源`);
for (const state of [...allowedStates]) if (summary[state]) console.log(`- ${state}: ${summary[state]}`);
for (const capability of matrix.capabilities) console.log(`${capability.id}\t${capability.state}\t${capability.localFallback}`);
