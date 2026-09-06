import { readFileSync, writeFileSync } from 'node:fs';

const file = new URL('../build/libstellarium-harmonyos/entry/build-profile.json5', import.meta.url);
const source = readFileSync(file, 'utf8');
const workerPath = './src/main/ets/pages/DetailModelWorker.ets';
if (!source.includes(workerPath)) {
  if (/['"]sourceOption['"]\s*:/.test(source)) {
    throw new Error('Preserve existing sourceOption; add DetailModelWorker.ets to its workers list before syncing.');
  }
  const anchor = /(['"]buildOption['"]\s*:\s*\{)/;
  if (!anchor.test(source)) throw new Error('Module buildOption was not found; no configuration changed.');
  writeFileSync(file, source.replace(anchor, '$1\n    "sourceOption": { "workers": ["' + workerPath + '"] },'));
}
console.log('Detail-model worker registered in entry module; application signing configuration is untouched.');
