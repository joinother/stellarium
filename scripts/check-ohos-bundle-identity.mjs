#!/usr/bin/env node
// 护栏：跟踪文件里不得出现"本机调试签名身份"。
//
// 背景：DevEco「Automatically generate signature」会按机器生成个人签名（bundle-name 形如
// com.<owner>.<app>），它只应存在于被 Git 忽略的生成工程里。历史上它曾泄漏进构建脚本与开发文档；
// 本脚本在提交前拦住复发。
//
// 规范身份（唯一真源）是 harmonyos/AppScope/app.json5 的 bundleName（发布身份）。
// 本机调试身份一律由运行时推导（pack.info / app.json5 / --bundle / STELLARIUM_BUNDLE），不写死。
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

// 个人/本机调试身份前缀（可扩展）。
const FORBIDDEN = [
  { id: 'com.cnchensh.', why: '本机 DevEco 调试签名身份' },
];

// 允许保留历史痕迹的文件（真机记录 / 本清理方案的示例）。
const ALLOWLIST = new Set([
  'docs/harmonyos/CHANGELOG.md',
  'docs/harmonyos/release/BUNDLE-IDENTITY-CLEANUP.md',
]);

// 跳过二进制/大体积资产，只扫文本。
const BINARY_EXT = /\.(png|jpe?g|webp|gif|ico|svgz?|qm|mo|so|hap|hsp|app|zip|gz|xz|bz2|pdf|ttf|otf|woff2?|bin|dat|o|a|dll|exe|jar|pdb)$/i;

const files = execFileSync('git', ['ls-files'], { encoding: 'utf8' })
  .split('\n')
  .map((line) => line.trim())
  .filter(Boolean);

const violations = [];
for (const file of files) {
  if (ALLOWLIST.has(file) || BINARY_EXT.test(file)) continue;
  let text;
  try {
    text = readFileSync(file, 'utf8');
  } catch {
    continue;
  }
  const hit = FORBIDDEN.find(({ id }) => text.includes(id));
  if (!hit) continue;
  const lines = text.split('\n');
  for (let index = 0; index < lines.length; index += 1) {
    if (lines[index].includes(hit.id)) {
      violations.push(`${file}:${index + 1}  含 "${hit.id}"（${hit.why}）`);
    }
  }
}

if (violations.length > 0) {
  console.error('bundle identity check failed：跟踪文件里出现了本机调试签名身份。');
  console.error('请改为运行时推导（pack.info / app.json5 / --bundle / STELLARIUM_BUNDLE），不要写死：');
  for (const violation of violations) console.error('  ' + violation);
  process.exit(1);
}
console.log('bundle identity check passed：未发现本机调试签名身份。');
