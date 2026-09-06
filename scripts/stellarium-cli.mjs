#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import readline from 'node:readline';
import process from 'node:process';

const DEFAULT_BUNDLE = 'com.joinother.skyinstrument';
const DEFAULT_ABILITY = 'QAbility';
const DEFAULT_MODULE = 'entry';
const DEFAULT_HDC = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc';
const RESPONSE_MARKER = '[cli-response]';

function usage(exitCode = 0) {
  console.log(`用法：
  stellarium-cli.mjs --command <命令> [--payload <字符串>] [选项]
  stellarium-cli.mjs --list [选项]
  stellarium-cli.mjs --describe <命令> [选项]
  stellarium-cli.mjs --batch <JSON文件> [选项]
  stellarium-cli.mjs --interactive [选项]

选项：
  --device <设备ID>       hdc 设备标识；不填时使用当前唯一设备
  --bundle <包名>         默认 ${DEFAULT_BUNDLE}
  --ability <名称>        默认 ${DEFAULT_ABILITY}
  --module <模块名>       默认 ${DEFAULT_MODULE}
  --hdc <路径>            默认 DevEco 自带 hdc
  --timeout <毫秒>        默认 30000
  --list                   输出设备上的机器可读命令目录
  --describe <命令>       输出一个命令的参数和权限描述
  --payload-json <JSON>   将 JSON 压缩后作为命令 payload 传入
  --batch <JSON文件>      顺序执行 JSON 数组中的命令
  --interactive            进入 JSONL 交互模式
  --json                  只输出响应 JSON
  --help                  显示帮助

示例：
  node scripts/stellarium-cli.mjs --command getAppState
  node scripts/stellarium-cli.mjs --command searchObject --payload M31
  node scripts/stellarium-cli.mjs --command setFOV --payload 60 --json
  node scripts/stellarium-cli.mjs --command getSkyCultureList --device 7LZBB26323200303

命令名直接复用 StellariumOhos_command；payload 是该命令原有的字符串参数。
批量文件格式：[{"command":"getTimeInfo"},{"command":"setFOV","payload":"45"}]。
复杂 payload 可写成 {"command":"getWutTargets","payloadJson":{"category":"planets"}}。`);
  process.exit(exitCode);
}

function parseArgs(argv) {
  const options = { bundle: DEFAULT_BUNDLE, ability: DEFAULT_ABILITY, module: DEFAULT_MODULE, hdc: DEFAULT_HDC,
    timeout: 30000, json: false, list: false, describe: undefined,
    batch: undefined, interactive: false, payloadJson: undefined };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') usage(0);
    if (arg === '--json') { options.json = true; continue; }
    if (arg === '--list') { options.list = true; continue; }
    if (arg === '--interactive') { options.interactive = true; continue; }
    const key = { '--device': 'device', '--bundle': 'bundle', '--ability': 'ability', '--module': 'module',
      '--hdc': 'hdc', '--timeout': 'timeout', '--command': 'command', '--payload': 'payload',
      '--describe': 'describe', '--payload-json': 'payloadJson', '--batch': 'batch' }[arg];
    if (key === undefined || i + 1 >= argv.length) {
      throw new Error(`未知或缺少参数：${arg}`);
    }
    options[key] = argv[++i];
  }
  const modes = Number(options.list) + Number(options.describe !== undefined) +
    Number(options.batch !== undefined) + Number(options.interactive);
  if (modes > 1 || (modes === 0 && !options.command)) throw new Error('必须提供 --command、--list、--describe、--batch 或 --interactive 之一');
  if (options.command && !/^[A-Za-z][A-Za-z0-9_]*$/.test(options.command)) throw new Error('命令名包含非法字符');
  if (options.describe !== undefined && !/^[A-Za-z][A-Za-z0-9_]*$/.test(options.describe)) throw new Error('命令名包含非法字符');
  if (options.payload !== undefined && options.payloadJson !== undefined) throw new Error('--payload 和 --payload-json 不能同时使用');
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

function readResponse(options, requestId, deadline, relaunch) {
  let requestSeen = false;
  let retriesRemaining = 2;
  let nextRetryAt = Date.now() + 900;
  const byIndex = new Map();
  while (Date.now() < deadline) {
    let log = '';
    // Filter on the device before returning logs. A busy Qt UI can make the
    // complete hilog dump exceed the host-side buffer and hide the response.
    try {
      log = shell(options, ['hilog', '-x', '-T', 'ohosQtTemplate', '-e', requestId]);
    } catch (error) { log = ''; }
    const requestLines = log.split(/\r?\n/).filter((line) => line.includes(requestId));
    if (requestLines.length > 0) requestSeen = true;
    const responseLines = requestLines.filter((line) => line.includes(RESPONSE_MARKER) && line.includes(`requestId=${requestId}`));
    const chunks = responseLines.map((line) => {
      const match = line.match(/chunkIndex=(\d+)\s+chunkCount=(\d+)\s+responseChunk=(.*)$/s);
      if (!match) return undefined;
      return { index: Number(match[1]), count: Number(match[2]), value: match[3] };
    }).filter((chunk) => chunk !== undefined);
    if (chunks.length > 0) {
      const expectedCount = chunks[0].count;
      for (const chunk of chunks) byIndex.set(chunk.index, chunk.value);
      if (byIndex.size >= expectedCount && Array.from({ length: expectedCount }, (_, index) => byIndex.has(index)).every(Boolean)) {
        const raw = Array.from({ length: expectedCount }, (_, index) => byIndex.get(index)).join('');
        try { return JSON.parse(raw); } catch (error) { return { ok: false, error: '无法解析设备响应', raw }; }
      }
    }
    const legacyLines = responseLines.filter((line) => line.includes(' response='));
    if (legacyLines.length > 0) {
      const line = legacyLines[legacyLines.length - 1];
      const marker = ' response=';
      const index = line.indexOf(marker);
      if (index >= 0) {
        const raw = line.slice(index + marker.length).trim();
        try { return JSON.parse(raw); } catch (error) { return { ok: false, error: '无法解析设备响应', raw }; }
      }
    }
    if (!requestSeen && retriesRemaining > 0 && Date.now() >= nextRetryAt) {
      relaunch();
      retriesRemaining -= 1;
      nextRetryAt = Date.now() + 1400;
    }
    sleep(120);
  }
  throw new Error('等待设备响应超时；若是首次启动，请先在设备上完成隐私政策确认');
}

function encodePayload(payload) {
  return `__STEL_CLI_PAYLOAD_URI__${encodeURIComponent(payload).replace(/[!'()*]/g,
    character => '%' + character.charCodeAt(0).toString(16).toUpperCase())}`;
}

function runCommand(options, command, payload, quiet = false) {
  const deadline = Date.now() + options.timeout;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const requestId = `cli-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const args = ['aa', 'start', '-b', options.bundle, '-m', options.module, '-a', options.ability,
      '-A', 'action.system.home', '-e', 'entity.system.home',
      '--ps', 'skyinstrument.cli.command', command,
      '--ps', 'skyinstrument.cli.requestId', requestId];
    if (payload !== undefined) {
      // hdc reconstructs the remote shell command and splits spaces even when
      // the host process supplied one argv item. Percent encoding keeps JSON,
      // translated names and punctuation in one aa --ps value.
      args.push('--ps', 'skyinstrument.cli.payload',
        encodePayload(payload));
    }
    if (!quiet && !options.json) console.error(`设备 ${options.device}：执行 ${command}（${requestId}）`);
    const launch = () => shell(options, args);
    const launchResult = launch();
    if (!quiet && !options.json && launchResult.trim()) console.error(launchResult.trim());
    const response = readResponse(options, requestId, deadline, launch);
    const startupTransient = response?.ok === false &&
      (response?.error === 'bridge not available' || (response?.error === 'command timeout' && response?.pending === true));
    if (!startupTransient || attempt === 2 || Date.now() + 350 >= deadline) return response;
    sleep(350 * (attempt + 1));
  }
  throw new Error('设备命令重试失败');
}

function payloadFromOptions(options) {
  if (options.payloadJson !== undefined) {
    try { return JSON.stringify(JSON.parse(options.payloadJson)); }
    catch (error) { throw new Error(`--payload-json 不是合法 JSON：${error.message}`); }
  }
  return options.payload;
}

function commandFromBatchItem(item) {
  if (!item || typeof item !== 'object' || typeof item.command !== 'string' ||
      !/^[A-Za-z][A-Za-z0-9_]*$/.test(item.command)) {
    throw new Error('批量项目必须包含合法 command 字段');
  }
  if (item.payload !== undefined && item.payloadJson !== undefined) {
    throw new Error(`批量项目 ${item.command} 同时包含 payload 和 payloadJson`);
  }
  let payload = item.payload;
  if (item.payloadJson !== undefined) {
    payload = JSON.stringify(item.payloadJson);
  }
  if (payload !== undefined && typeof payload !== 'string') {
    throw new Error(`批量项目 ${item.command} 的 payload 必须是字符串`);
  }
  return { command: item.command, payload };
}

function runBatch(options) {
  let document;
  try { document = JSON.parse(readFileSync(options.batch, 'utf8')); }
  catch (error) { throw new Error(`无法读取批量文件：${error.message}`); }
  const items = Array.isArray(document) ? document : document?.commands;
  if (!Array.isArray(items)) throw new Error('批量文件必须是 JSON 数组或包含 commands 数组的对象');
  return items.map((item) => {
    const request = commandFromBatchItem(item);
    try {
      return { command: request.command, response: runCommand(options, request.command, request.payload, true) };
    } catch (error) {
      return { command: request.command, response: { ok: false, error: error.message } };
    }
  });
}

async function runInteractive(options) {
  const input = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
  console.error('交互模式：每行输入 JSON 命令，例如 {"command":"getTimeInfo"}；输入 exit 退出。');
  for await (const line of input) {
    const text = line.trim();
    if (!text) continue;
    if (text === 'exit' || text === 'quit') break;
    try {
      const item = commandFromBatchItem(JSON.parse(text));
      console.log(JSON.stringify(runCommand(options, item.command, item.payload)));
    } catch (error) {
      console.error(error.message);
    }
  }
  input.close();
}

function output(options, value) {
  console.log(JSON.stringify(value));
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  findDevice(options);
  if (options.interactive) return runInteractive(options);
  if (options.batch !== undefined) { output(options, runBatch(options)); return; }
  if (options.list) { output(options, runCommand(options, 'getCommandCatalog', undefined)); return; }
  if (options.describe !== undefined) { output(options, runCommand(options, 'getCommandSchema', options.describe)); return; }
  const response = runCommand(options, options.command, payloadFromOptions(options));
  output(options, response);
  process.exitCode = response.ok === false ? 1 : 0;
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 2;
});
