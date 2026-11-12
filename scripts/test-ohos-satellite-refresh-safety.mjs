import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { execFileSync } from 'node:child_process';

const read = path => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const source = read('plugins/Satellites/src/Satellites.cpp');
const native = read('src/StelMainView.cpp');
function body(marker, text = source) {
  const declaration = text.indexOf(marker);
  assert.notEqual(declaration, -1, marker);
  const start = text.indexOf('{', declaration);
  let depth = 0;
  for (let index = start; index < text.length; index++) {
    if (text[index] === '{') depth++;
    if (text[index] === '}' && --depth === 0) return text.slice(start, index + 1);
  }
  assert.fail(`Unclosed ${marker}`);
}

const save = body('bool Satellites::saveDataMap(');
const executableSave = save
  .replace(/qWarning\(\)[^;]*;/g, '')
  .replace('path.isEmpty()', '!path')
  .replace('QSaveFile jsonFile(path);', 'const jsonFile = new QSaveFile(path);')
  .replace('QIODevice::WriteOnly', '"write"')
  .replace('const QByteArray contents = StelJsonParser::write(map);', 'const contents = serialize(map);')
  .replaceAll('contents.isEmpty()', '!contents.length')
  .replaceAll('contents.size()', 'contents.length')
  .replace('catch (const std::exception& error)', 'catch (error)');

function saveScenario(failure) {
  const state = { disk: 'previous catalog', pending: '', canceled: false, direct: null };
  class MockSaveFile {
    setDirectWriteFallback(value) { state.direct = value; }
    open() { return failure !== 'open'; }
    write(contents) { state.pending = contents; return contents.length - (failure === 'short' ? 1 : 0); }
    cancelWriting() { state.canceled = true; state.pending = ''; }
    commit() {
      if (failure === 'commit') return false;
      state.disk = state.pending;
      return true;
    }
  }
  const serialize = () => {
    if (failure === 'serialize') throw new Error('serialization failed');
    return failure === 'empty' ? '' : 'replacement catalog';
  };
  const run = new Function('QSaveFile', 'serialize', 'catalogPath', 'map', 'path', executableSave);
  state.ok = run(MockSaveFile, serialize, '/catalog.json', {}, '');
  return state;
}

for (const failure of ['open', 'short', 'commit', 'serialize', 'empty']) {
  test(`actual atomic save body preserves previous file on ${failure} failure`, () => {
    const result = saveScenario(failure);
    assert.equal(result.ok, false);
    assert.equal(result.disk, 'previous catalog');
    assert.equal(result.direct, false);
  });
}
test('actual atomic save body replaces file only on successful commit', () => {
  const result = saveScenario();
  assert.equal(result.ok, true);
  assert.equal(result.disk, 'replacement catalog');
  assert.doesNotMatch(save, /\.remove\(/);
});

const parse = body('void Satellites::parseDataFile(');
const csvLineCode = body('static bool parseSatelliteCsvLine(')
  .replace('fields.clear();', 'fields.length = 0;')
  .replace('QString field;', 'let field = "";')
  .replaceAll('field.clear();', 'field = "";')
  .replaceAll('field.isEmpty()', '(field.length === 0)')
  .replaceAll('fields.append', 'fields.push')
  .replaceAll('line.size()', 'line.length')
  .replaceAll(/QLatin1Char\(('(?:[^'\\]|\\.)*')\)/g, '$1')
  .replaceAll(/\bbool /g, 'let ')
  .replaceAll(/\bint /g, 'let ')
  .replace('const QChar character', 'const character');
const parseSatelliteCsvLine = new Function('line', 'fields', csvLineCode);
test('download batch rejects each bad source and reports partial success', () => {
  const download = body('void Satellites::saveDownloadedUpdate(');
  const batch = body('void Satellites::finishDownloadBatch(');
  assert.match(batch, /if \(!updateSources\[i\]\.file\)\s*\{\s*complete = false;/);
  assert.match(batch, /complete = updateSources\[i\]\.file->property\("tleParseComplete"\).toBool\(\) && complete/);
  assert.match(batch, /if \(!newData.isEmpty\(\)\)[\s\S]*updateSatellites\(newData, complete\)/);
  assert.match(body('void Satellites::updateSatellites('), /!complete[\s\S]*CompletePartial;\s*emit updateStateChanged/);
  assert.match(download, /tmpFile->write\(fd\) == fd.size\(\) && tmpFile->flush\(\)/);
  assert.match(body('void Satellites::updateFromFiles('), /if \(!complete\)[\s\S]*return;[\s\S]*updateSatellites/);
});
test('malformed TLE and CSV propagate failure instead of silently skipping rows', () => {
  const tle = body('void Satellites::parseTleFile(');
  const csv = body('void Satellites::parseCsvFile(');
  assert.match(tle, /if \(!tlePairValid[\s\S]*setProperty\("tleParseComplete", false\)/);
  assert.match(tle, /if \(!lastData.name.isEmpty\(\) \|\| !lastData.first.isEmpty\(\)\) openFile.setProperty\("tleParseComplete", false\);/);
  assert.match(csv, /const auto warn = \[&openFile[^]*?setProperty\("tleParseComplete", false\)/);
  assert.match(body('bool tlePairValid('), /checksum % 10 != line\[68\].digitValue\(\)/);
  assert.doesNotMatch(body('QString formatTleEpoch('), /static const auto epoch0/);
});
test('refresh commits before live mutation, success and timestamp; retains absent/manual objects', () => {
  const update = body('void Satellites::updateSatellites(');
  const commit = update.indexOf('!saveDataMap(candidate)');
  assert.ok(commit > 0);
  for (const action of ['beginSatellitesChange()', 'sat->setNewTleElements', 'satellites.append', 'markLastUpdate()', 'CompleteUpdates']) {
    assert.ok(update.indexOf(action) > commit, action);
  }
  assert.match(update.slice(commit), /OtherError;[\s\S]*return;/);
  assert.doesNotMatch(update, /removeWithoutModelReset|satellites\.(clear|remove|erase)|toBeRemoved/);
  assert.match(update, /record.value\("userDefined"\).toBool\(\)/);
  assert.match(update, /sat->userDefined \|\| !changedIds.contains\(sat->id\)/);
  assert.match(update, /\(updatedCount > 0 \|\| addedCount > 0\) && !saveDataMap/);
  assert.match(body('void Satellites::saveCatalog('), /if \(!saveDataMap[^]*OtherError[^]*emit updateStateChanged/);
});
test('explicit satellite epochs return an error object before calling mutable legacy predictor', () => {
  const handler = body('if (commandName == "getSatellitePasses" || commandName == "getSatelliteDetail")', native);
  const guard = body('if (options.contains("startJD"))', handler);
  assert.match(guard, /result\["ok"\] = false/);
  assert.match(guard, /result\["reason"\] = "explicit_epoch_prediction_unsupported"/);
  assert.match(guard, /return result;/);
  assert.doesNotMatch(guard, /setJD|->update|getPassPredictions/);
  assert.ok(handler.indexOf('return result;', handler.indexOf('options.contains("startJD")')) < handler.indexOf('satellite->getPassPredictions'));
  assert.match(handler, /satellite->getPassPredictions\(core, hours, qBound\(1, limit, 32\), minimumElevation\)/);
});

test('native Qt parsers accept ordinary data and reject corrupt sources atomically', () => {
  const result = execFileSync('python3', [new URL('./test-satellite-ingestion.py', import.meta.url).pathname], { encoding: 'utf8' });
  assert.match(result, /PASS merge order, add flag, and rollback/);
});
