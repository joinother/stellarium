#!/usr/bin/env node
// 隐私制品审计：核对签名 HAP 里的编译产物。
//
// 依赖（任一缺失则对应小节降级跳过，不判失败；Windows 上刻意不比对 Qt 平台补丁）：
//   - 签名 HAP（缺失则整体跳过，退出 0）
//   - unzip 或 tar（解包 HAP）
//   - build/qt-platform-patch/*（Qt 平台补丁产物；Windows 不比对）
//   - ark_disasm（ArkTS 反汇编器；缺失则跳过字节码守卫小节）
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const hap = resolve(process.argv[2] ?? join(root, 'build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap'));
const manifestPath = join(root, 'build/qt-platform-patch/manifest.json');
const referencePath = join(root, 'build/qt-platform-patch/compiled/plugins/platforms/libqohos.so');
const disassembler = process.env.ARK_DISASM ?? (process.platform === 'darwin'
  ? '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/ark_disasm'
  : (process.env.DEVECO_HOME
    ? join(process.env.DEVECO_HOME, 'sdk/default/openharmony/toolchains', process.platform === 'win32' ? 'ark_disasm.exe' : 'ark_disasm')
    : ''));
const auditDirectory = mkdtempSync(join(tmpdir(), 'stellarium-privacy-artifact-'));
const hash = buffer => createHash('sha256').update(buffer).digest('hex');
const skipped = [];

// HAP 缺失：这是本机未产出签名包，不是审计失败。
if (!existsSync(hap)) {
  console.log(JSON.stringify({ skipped: true, reason: `signed HAP not found: ${hap}` }, null, 2));
  process.exit(0);
}

function extract(name) {
  try {
    return execFileSync('unzip', ['-p', hap, name], { maxBuffer: 256 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'] });
  } catch (error) {
    // Windows 自带 bsdtar，可读 zip。
    return execFileSync('tar', ['-xOf', hap, name], { maxBuffer: 256 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'] });
  }
}

function allocatedSections(buffer) {
  assert.equal(buffer.subarray(0, 6).toString('hex'), '7f454c460201', 'expected 64-bit little-endian ELF');
  assert.equal(buffer.readUInt16LE(18), 183, 'expected arm64');
  const tableOffset = Number(buffer.readBigUInt64LE(40));
  const entrySize = buffer.readUInt16LE(58);
  const count = buffer.readUInt16LE(60);
  assert.ok(entrySize >= 64 && count > 0 && tableOffset + count * entrySize <= buffer.length);
  const namesIndex = buffer.readUInt16LE(62);
  assert.ok(namesIndex < count);
  const namesOffset = Number(buffer.readBigUInt64LE(tableOffset + entrySize * namesIndex + 24));
  const result = {};
  for (let index = 0; index < count; index++) {
    const entry = tableOffset + index * entrySize;
    if (!(buffer.readBigUInt64LE(entry + 8) & 2n) || buffer.readUInt32LE(entry + 4) === 8) continue;
    const nameStart = namesOffset + buffer.readUInt32LE(entry);
    const nameEnd = buffer.indexOf(0, nameStart);
    assert.ok(nameStart < buffer.length && nameEnd >= nameStart);
    const name = buffer.toString('utf8', nameStart, nameEnd);
    const offset = Number(buffer.readBigUInt64LE(entry + 24));
    const size = Number(buffer.readBigUInt64LE(entry + 32));
    assert.ok(offset + size <= buffer.length);
    result[name] = { size, sha256: hash(buffer.subarray(offset, offset + size)) };
  }
  assert.ok(result['.text'] && result['.rodata']);
  return result;
}

// ── Qt 运行时比对：Windows 上跳过（不验证平台补丁构建） ──
let qtRuntime = null;
const qtPatchReady = process.platform !== 'win32' && existsSync(manifestPath) && existsSync(referencePath);
if (qtPatchReady) {
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const reference = readFileSync(referencePath);
  assert.equal(hash(reference), manifest.librarySha256);
  const packedPlatform = extract('libs/arm64-v8a/libqohos.so');
  const sections = allocatedSections(packedPlatform);
  assert.deepEqual(sections, allocatedSections(reference), 'packaged Qt runtime differs from the audited build, excluding non-runtime debug sections');
  qtRuntime = { qtRevision: manifest.revision, packedPlatformSha256: hash(packedPlatform), matchingRuntimeSections: Object.keys(sections).length };
} else {
  skipped.push('qt-runtime-comparison');
}

// ── module.json 权限检查（始终执行） ──
const module = JSON.parse(extract('module.json').toString('utf8'));
const buildMode = module.app.debug === true ? 'debug' : 'release';
const expectedMode = process.env.EXPECT_OHOS_BUILD_MODE;
if (expectedMode !== undefined) {
  assert.ok(['debug', 'release'].includes(expectedMode), 'expected build mode must be debug or release');
  assert.equal(buildMode, expectedMode, 'compiled build mode differs from expectation; signing configuration does not select build mode');
}
const permissions = (module.module.requestPermissions ?? []).map(permission => permission.name);
// The packaged permissions must reflect the network mode selected in the
// source manifest (scripts/set-ohos-network-mode.sh toggles INTERNET); the
// audit never assumes offline. ACCESS_UDID must never be requested.
const sourcePermissions = [...readFileSync(join(root, 'harmonyos/module.json5'), 'utf8')
  .matchAll(/"name":\s*"(ohos\.permission\.[A-Z_]+)"/g)].map(match => match[1]);
assert.deepEqual([...permissions].sort(), [...new Set(sourcePermissions)].sort(),
  'packaged permissions must match harmonyos/module.json5 (selected network mode)');
assert.ok(!permissions.includes('ohos.permission.ACCESS_UDID'));

// ── 字节码守卫审计：需要 ark_disasm ──
let guards = null;
const disassemblerReady = disassembler.length > 0 && existsSync(disassembler);
if (disassemblerReady) {
  const abc = extract('ets/modules.abc');
  const abcPath = join(auditDirectory, 'modules.abc');
  const assemblyPath = join(auditDirectory, 'modules.pa');
  writeFileSync(abcPath, abc, { mode: 0o600 });
  execFileSync(disassembler, [abcPath, assemblyPath], { timeout: 120000, maxBuffer: 1024 * 1024 });
  const assembly = readFileSync(assemblyPath, 'utf8');

  function findMethod(className, methodName) {
    const expression = new RegExp(`^\\.function[^\\n]*\\.${className}\\.[^\\n]*#${methodName}\\([^\\n]*\\{\\n[\\s\\S]*?^\\}`, 'm');
    return assembly.match(expression)?.[0] ?? null;
  }

  const stage = findMethod('QAbilityStage', 'initQtAppContextImpl');
  const child = findMethod('QChildProcess', 'onStart');
  if (stage === null || child === null) {
    // The symbol spelling depends on the ark_disasm version; do not fail the
    // audit on a toolchain naming difference.
    skipped.push('bytecode-guard-audit:method-symbols-not-found');
  } else {
    assert.equal((stage.match(/"hasCurrentPrivacyConsent"/g) ?? []).length, 3);
    assert.ok(stage.lastIndexOf('"hasCurrentPrivacyConsent"') < stage.indexOf('"setupQtApplication"'));
    assert.match(stage, /Privacy consent changed during resource finalization/);
    assert.match(stage, /\bthrow\b/);
    assert.ok(child.indexOf('"hasCurrentPrivacyConsent"') >= 0);
    assert.ok(child.indexOf('"hasCurrentPrivacyConsent"') < child.indexOf('"runQtChildProcess"'));
    assert.match(child, /blocked Qt child process before current consent/);
    assert.match(child, /\breturnundefined\b/);
    assert.ok(child.indexOf('returnundefined') < child.indexOf('"runQtChildProcess"'));
    guards = { mainInitializationConsentChecks: 3, childInitializationGuard: true, bytecodeSha256: hash(abc) };
  }
} else {
  skipped.push('bytecode-guard-audit');
}

const mapPath = join(dirname(hap), `symbol/${buildMode}/entry-sourceMaps.map`);
const report = {
  scope: 'Artifact identity and compiled guard presence; not exhaustive control-flow proof or a system privacy scan',
  skipped,
  hap, buildMode, versionCode: module.app.versionCode, hapSha256: hash(readFileSync(hap)),
  qtRuntime,
  permissions,
  guards,
  sourceMap: existsSync(mapPath) ? { path: mapPath, sha256: hash(readFileSync(mapPath)) } : null,
  auditDirectory
};
writeFileSync(join(auditDirectory, 'report.json'), JSON.stringify(report, null, 2) + '\n', { mode: 0o600 });
console.log(JSON.stringify(report, null, 2));
