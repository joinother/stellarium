#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import process from 'node:process';

const cliPath = new URL('./stellarium-cli.mjs', import.meta.url).pathname;
function readDevice(argv) {
  if (argv[0] === '--device' && argv[1]) return argv[1];
  if (argv[0]?.startsWith('--device=')) return argv[0].slice('--device='.length);
  return argv[0];
}

const device = readDevice(process.argv.slice(2));
if (!device) {
  console.error('用法：node scripts/smoke-test-ohos-cli.mjs <设备ID> 或 --device <设备ID>');
  process.exit(2);
}

function invoke(args) {
  const output = execFileSync(process.execPath, [cliPath, '--device', device, '--json', '--timeout', '20000', ...args], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe']
  });
  return JSON.parse(output);
}

function command(name, payload) {
  const args = ['--command', name];
  if (payload !== undefined) args.push('--payload', payload);
  return invoke(args);
}

function sleep(milliseconds) {
  const buffer = new SharedArrayBuffer(4);
  Atomics.wait(new Int32Array(buffer), 0, 0, milliseconds);
}

function waitForConstellationArt() {
  let latest = command('getConstellationArtStatus', 'Ori');
  for (let attempt = 0; attempt < 12; attempt += 1) {
    const item = latest.items?.[0];
    if (item?.state === 'ready' || item?.state === 'decodeFailed' || item?.state === 'noMatch') return latest;
    sleep(250);
    latest = command('getConstellationArtStatus', 'Ori');
  }
  return latest;
}

function setConstellationArt(enabled) {
  return command('setConstellationFlag', `art|${enabled ? 'true' : 'false'}`);
}

const checks = [];
function expect(name, condition, detail) {
  checks.push({ name, ok: condition, detail: condition ? '通过' : detail });
}

const catalog = invoke(['--list']);
const catalogNames = new Set((catalog.commands ?? []).map((item) => item.name));
expect('命令目录可读', catalog.ok === true && catalog.commands?.length >= 300, `commands=${catalog.commands?.length ?? 0}`);
expect('CLI 元命令留在目录中', catalogNames.has('getCommandSchema') && catalogNames.has('getCommandStatus'), '缺少 CLI 元命令');

const app = command('getAppState');
const state = command('getState');
const astro = command('getAstroCalcContext');
const health = command('getCatalogHealth');
const plugins = command('getPluginList');
const scripts = command('getScriptStatus');
const cultures = command('getSkyCultureList');
const constellationFlags = command('getConstellationFlags');
const artWasEnabled = constellationFlags.flags?.art === true;
if (!artWasEnabled) setConstellationArt(true);
const art = waitForConstellationArt();
if (!artWasEnabled) setConstellationArt(false);
const deepSky = command('getDeepSkyImageStatus');
const schema = invoke(['--describe', 'getTimeInfo']);
const metaStatus = command('getCommandStatus', 'getTimeInfo');

expect('应用状态查询', app.ok === true && typeof app.fps === 'number', JSON.stringify(app));
expect('全局状态查询', state.ok === true && state.meteorZhrMax >= 1000, JSON.stringify(state));
expect('天文计算上下文查询', astro.ok === true && typeof astro.jd === 'number', JSON.stringify(astro));
expect('目录健康查询', health.ok === true && health.manifestPresent === true, JSON.stringify(health));
expect('插件清单查询', plugins.ok === true && plugins.items?.length > 0, '插件清单为空');
expect('脚本状态查询', scripts.ok === true && scripts.running === false, JSON.stringify(scripts));
expect('星空文化查询', cultures.ok === true && cultures.items?.length > 0, '星空文化为空');
expect('星座绘图开关可读写', constellationFlags.ok === true && typeof artWasEnabled === 'boolean', JSON.stringify(constellationFlags));
expect('星座绘图状态有稳定状态字段', art.ok === true && art.items?.every((item) => typeof item.state === 'string'), JSON.stringify(art));
expect('星座绘图离线资源可完成加载', art.ok === true && art.items?.every((item) => !item.onDisk || item.state === 'ready'), JSON.stringify(art));
expect('深空资源无离线文件缺失', deepSky.ok === true && deepSky.missingCount === 0 && deepSky.referencedCount <= deepSky.onDiskCount, JSON.stringify(deepSky));
expect('CLI describe 使用元命令路径', schema.ok === true && schema.schema?.name === 'getTimeInfo', JSON.stringify(schema));
expect('CLI 命令状态可查询', metaStatus.ok === true && metaStatus.command === 'getTimeInfo', JSON.stringify(metaStatus));

const selection = command('searchObject', 'M31');
expect('搜索并选中深空天体', selection.ok === true && selection.found === true && selection.objectType === 'galaxy', JSON.stringify(selection));
const constellation = command('searchObject', 'Orion');
const model = command('getObjectDetailModel');
expect('搜索并选中星座', constellation.ok === true && constellation.found === true && constellation.objectType === 'constellation', JSON.stringify(constellation));
expect('星座详情模型契约可返回', model.ok === true && model.state === 'planned' && model.fallbackMediaPath?.length > 0, JSON.stringify(model));
const cleared = command('clearSelection');
expect('清理测试选择', cleared.ok === true, JSON.stringify(cleared));

const failed = checks.filter((item) => !item.ok);
for (const item of checks) console.log(`${item.ok ? 'PASS' : 'FAIL'} ${item.name}${item.detail ? `: ${item.detail}` : ''}`);
console.log(`CLI smoke summary: ${checks.length - failed.length}/${checks.length} passed`);
process.exit(failed.length === 0 ? 0 : 1);
