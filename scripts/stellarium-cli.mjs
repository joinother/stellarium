#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import process from 'node:process';

const DEFAULT_BUNDLE = 'com.joinother.skyinstrument';
const DEFAULT_ABILITY = 'QAbility';
const DEFAULT_HDC = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc';
const RESPONSE_MARKER = '[cli-response]';

function usage(exitCode = 0) {
  console.log(`用法：
  stellarium-cli.mjs --command <命令> [--payload <字符串>] [选项]

选项：
  --device <设备ID>       hdc 设备标识；不填时使用当前唯一设备
  --bundle <包名>         默认 ${DEFAULT_BUNDLE}
  --ability <名称>        默认 ${DEFAULT_ABILITY}
  --hdc <路径>            默认 DevEco 自带 hdc
  --timeout <毫秒>        默认 12000
  --json                  只输出响应 JSON
  --help                  显示帮助

示例：
  node scripts/stellarium-cli.mjs --command getAppState
  node scripts/stellarium-cli.mjs --command searchObject --payload M31
  node scripts/stellarium-cli.mjs --command setFOV --payload 60 --json
  node scripts/stellarium-cli.mjs --command getSkyCultureList --device 7LZBB26323200303

命令名直接复用 StellariumOhos_command；payload 是该命令原有的字符串参数。`);
  process.exit(exitCode);
}

function parseArgs(argv) {
  const options = { bundle: DEFAULT_BUNDLE, ability: DEFAULT_ABILITY, hdc: DEFAULT_HDC,
    timeout: 12000, json: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') usage(0);
    if (arg === '--json') { options.json = true; continue; }
    const key = { '--device': 'device', '--bundle': 'bundle', '--ability': 'ability',
      '--hdc': 'hdc', '--timeout': 'timeout', '--command': 'command', '--payload': 'payload' }[arg];
    if (key === undefined || i + 1 >= argv.length) {
      throw new Error(`未知或缺少参数：${arg}`);
    }
    options[key] = argv[++i];
  }
  if (!options.command) throw new Error('必须提供 --command');
  if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(options.command)) throw new Error('命令名包含非法字符');
  options.timeout = Number(options.timeout);
  if (!Number.isFinite(options.timeout) || options.timeout < 500) throw new Error('--timeout 至少为 500');
  return options;
}

function shell(options, args) {
  return execFileSync(options.hdc, ['-t', options.device, 'shell', ...args],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

function findDevice(options) {
  if (options.device) return;
  const output = execFileSync(options.hdc, ['list', 'targets'], { encoding: 'utf8' });
  const devices = output.split(/\r?\n/).map((line) => line.trim())
    .filter((line) => line && !line.startsWith('['));
  if (devices.length !== 1) throw new Error(`请使用 --device 指定设备，当前发现 ${devices.length} 台`);
  options.device = devices[0];
}

function sleep(milliseconds) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds);
}

function readResponse(options, requestId, deadline) {
  while (Date.now() < deadline) {
    let log = '';
    // Filter on the device before returning logs. A busy Qt UI can make the
    // complete hilog dump exceed the host-side buffer and hide the response.
    try {
      log = shell(options, ['sh', '-c', `hilog -x | grep -F '${requestId}'`]);
    } catch (error) { log = ''; }
    const lines = log.split(/\r?\n/).filter((line) => line.includes(RESPONSE_MARKER) && line.includes(`requestId=${requestId}`));
    if (lines.length > 0) {
      const line = lines[lines.length - 1];
      const marker = ' response=';
      const index = line.indexOf(marker);
      if (index >= 0) {
        const raw = line.slice(index + marker.length).trim();
        try { return JSON.parse(raw); } catch (error) { return { ok: false, error: '无法解析设备响应', raw }; }
      }
    }
    sleep(120);
  }
  throw new Error('等待设备响应超时；若是首次启动，请先在设备上完成隐私政策确认');
}

try {
  const options = parseArgs(process.argv.slice(2));
  findDevice(options);
  const requestId = `cli-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const args = ['aa', 'start', '-b', options.bundle, '-a', options.ability,
    '--ps', 'skyinstrument.cli.command', options.command,
    '--ps', 'skyinstrument.cli.requestId', requestId];
  if (options.payload !== undefined) {
    // aa --ps rejects values beginning with '-'. The Ability removes this
    // prefix after receipt, so negative coordinates and offsets remain intact.
    args.push('--ps', 'skyinstrument.cli.payload', `__STEL_CLI_PAYLOAD__${options.payload}`);
  }
  if (!options.json) console.error(`设备 ${options.device}：执行 ${options.command}（${requestId}）`);
  const launchResult = shell(options, args);
  if (!options.json && launchResult.trim()) console.error(launchResult.trim());
  const response = readResponse(options, requestId, Date.now() + options.timeout);
  console.log(JSON.stringify(response));
  process.exit(response.ok === false ? 1 : 0);
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(2);
}
