#!/usr/bin/env node

import { readFileSync } from 'node:fs';
import process from 'node:process';

const source = readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8');
const catalogSource = readFileSync(new URL('../src/StelOhosCommandCatalog.hpp', import.meta.url), 'utf8');
const sourceCommands = new Set([...source.matchAll(/commandName\s*==\s*"([A-Za-z][A-Za-z0-9_]*)"/g)].map((match) => match[1]));
const uiCommands = new Set(['backUiPanel', 'closeUiPanel', 'openPluginFeature', 'openUiPanel', 'setLayerTab', 'setSkyCultureMakerTab',
  'copyTextToClipboard', 'startGuide', 'guideAction', 'getGuideState',
  'setAstroTab', 'setAstroGroup', 'setAstroFilter', 'setAstroScroll', 'getAstroPanelState', 'setTelescopeLivePosition']);
const catalogBlock = catalogSource.match(/return QStringLiteral\(([\s\S]*?)\)\.split\(','\);/);
if (!catalogBlock) {
  console.error('无法找到命令目录 names()');
  process.exit(2);
}
const catalogText = [...catalogBlock[1].matchAll(/"([^"\\]*(?:\\.[^"\\]*)*)"/g)]
  .map((match) => match[1]).join('');
const catalogCommands = new Set(catalogText.split(',').filter((name) => /^[A-Za-z][A-Za-z0-9_]*$/.test(name)));
const missing = [...sourceCommands].filter((name) => !catalogCommands.has(name)).sort();
const stale = [...catalogCommands].filter((name) => !sourceCommands.has(name) && !uiCommands.has(name)).sort();
if (missing.length || stale.length) {
  if (missing.length) console.error(`目录缺少命令：${missing.join(', ')}`);
  if (stale.length) console.error(`目录包含未实现命令：${stale.join(', ')}`);
  process.exit(1);
}
console.log(`命令目录一致：${catalogCommands.size} 个命令`);
