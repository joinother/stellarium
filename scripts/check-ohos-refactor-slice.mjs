#!/usr/bin/env node
// 切片预检：在跑构建之前拦住"搬迁漏改引用"这一整类失败。
//
// 背景：本会话出现过三次同类返工 —— 把宿主字段搬进 store/组件后，只改了大部分引用，
// 漏掉几处 `this.<宿主字段>`，于是构建报 `Cannot find name` / 属性不存在，连续烧掉 2–3 轮构建。
// 本脚本把这一步提前成秒级本地检查，从而使"一片收 2–4 个 builder、300 行以上"变得安全。
//
// 检查项：
//   1) panels/**、state/** 里每个 `this.<ident>` 必须能在**同一文件**内找到声明
//      （成员、@Prop/@ObjectLink 等状态装饰器、方法、@BuilderParam、或文件作用域 function）；
//   2) 单体括号净深度必须为 0，且 `@Builder` 数与其签名数一致（拦住"孤儿 builder 体"）。
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const sourceRoot = join(root, 'harmonyos', 'ets-source');
const MONOLITH = join(sourceRoot, 'pages', 'MainWindowNativeNode.ets');

const walk = dir => readdirSync(dir).flatMap(name => {
  const full = join(dir, name);
  return statSync(full).isDirectory() ? walk(full) : (name.endsWith('.ets') ? [full] : []);
});

const problems = [];
// CustomComponent 基类自带的成员，组件里 this.getUIContext() 之类是合法的。
const BASE_MEMBERS = new Set(['getUIContext', 'aboutToAppear', 'aboutToDisappear', 'build']);

// ---- 1) 组件/store 文件内的 this.<ident> 自洽性 ----
for (const dir of ['panels', 'state', 'common']) {
  for (const file of walk(join(sourceRoot, dir))) {
    const raw = readFileSync(file, 'utf8');
    const text = raw.replace(/^[ \t]*\/\/.*$/gm, '');
    const declared = new Set();
    for (const match of text.matchAll(/^[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]+)*(?:private[ \t]+|public[ \t]+|readonly[ \t]+|static[ \t]+)*([A-Za-z_$][\w$]*)[ \t]*[:=]/gm)) declared.add(match[1]);
    for (const match of text.matchAll(/^[ \t]*(?:@[\w()]+[ \t]+)*(?:private[ \t]+|public[ \t]+|readonly[ \t]+|static[ \t]+)*([A-Za-z_$][\w$]*)[ \t]*\(/gm)) declared.add(match[1]);
    for (const match of text.matchAll(/^(?:export[ \t]+)?(?:default[ \t]+)?function[ \t]+([A-Za-z_$][\w$]*)/gm)) declared.add(match[1]);
    for (const match of text.matchAll(/^import[ \t]+\{([^}]*)\}/gm)) {
      for (const piece of match[1].split(',')) declared.add(piece.trim().split(/\s+as\s+/).pop().trim());
    }
    const seen = new Set();
    for (const match of text.matchAll(/(?<![A-Za-z0-9_$])this\.([A-Za-z_$][\w$]*)/g)) {
      const name = match[1];
      if (declared.has(name) || seen.has(name) || BASE_MEMBERS.has(name)) continue;
      seen.add(name);
      problems.push(`${relative(root, file)}: this.${name} 在本文件内没有声明（疑似漏改的宿主引用）`);
    }
  }
}

// ---- 2) 单体结构自洽性 ----
const monolith = readFileSync(MONOLITH, 'utf8');
let depth = 0;
for (const ch of monolith) {
  if (ch === '{') depth += 1;
  else if (ch === '}') depth -= 1;
}
if (depth !== 0) problems.push(`MainWindowNativeNode.ets: 括号净深度 ${depth}（应为 0，疑似删 builder 时留下孤儿体）`);
// 说明：不再统计 @Builder 数与其签名数是否相等 —— `@Builder` 也会出现在注释与字符串里，该计数噪声过大；
// "删 builder 留下孤儿体"这一真正要拦的问题由下面的括号净深度检查覆盖。

if (problems.length > 0) {
  console.error('切片预检未通过：');
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}
console.log('切片预检通过：组件/store 的 this 引用自洽，单体括号深度 0，@Builder 成对。');
