import { readFileSync, writeFileSync } from 'node:fs';

const file = new URL('../build/libstellarium-harmonyos/entry/build-profile.json5', import.meta.url);
const source = readFileSync(file, 'utf8');
const workerPath = './src/main/ets/capability/DetailModelWorker.ets';
// Phase M1 moved the render pipeline out of pages/; an existing generated
// project still registers the old pages/ path, so rewrite it in place.
const legacyWorkerPath = './src/main/ets/pages/DetailModelWorker.ets';
if (!source.includes(workerPath)) {
  if (source.includes(legacyWorkerPath)) {
    writeFileSync(file, source.split(legacyWorkerPath).join(workerPath));
  } else if (/['"]sourceOption['"]\s*:/.test(source)) {
    throw new Error('Preserve existing sourceOption; add DetailModelWorker.ets to its workers list before syncing.');
  } else {
    const anchor = /(['"]buildOption['"]\s*:\s*\{)/;
    if (!anchor.test(source)) throw new Error('Module buildOption was not found; no configuration changed.');
    writeFileSync(file, source.replace(anchor, '$1\n    "sourceOption": { "workers": ["' + workerPath + '"] },'));
  }
}
console.log('Detail-model worker registered in entry module; application signing configuration is untouched.');
