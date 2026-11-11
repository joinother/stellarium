import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

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
const executableParse = parse
  .replace(/qWarning\(\)[^;]*;/g, '{}')
  .replace('TleDataHash parsed;', 'const parsed = new Map();')
  .replace('const QString line', 'const line')
  .replace('QStringList firstLineEntries;', 'const firstLineEntries = [];')
  .replace('const bool csvHeaderValid', 'const csvHeaderValid')
  .replaceAll('.trimmed()', '.trim()')
  .replaceAll(/line.contains\("([^"]+)", Qt::CaseInsensitive\)/g, 'line.toLowerCase().includes("$1")')
  .replace('const auto firstLineEntries', 'const firstLineEntries')
  .replace("line.trimmed().split(QLatin1Char(','))", "line.trim().split(',')")
  .replaceAll(/firstLineEntries.contains\(L1S\("([^"]+)"\)\)/g, 'firstLineEntries.includes("$1")')
  .replaceAll('parsed.isEmpty()', 'parsed.size === 0')
  .replaceAll('QFileDevice::NoError', '0')
  .replaceAll('.toBool()', '')
  .replace('for (auto entry = parsed.constBegin(); entry != parsed.constEnd(); ++entry)', 'for (const [key, value] of parsed)')
  .replaceAll('entry.value()', 'value')
  .replaceAll('entry.key()', 'key')
  .replaceAll('tleList.contains', 'tleList.has')
  .replaceAll('tleList.insert', 'tleList.set');
function parseScenario({ malformed = false, empty = false, readError = false, add = true } = {}) {
  const properties = {};
  const file = {
    setProperty(key, value) { properties[key] = value; },
    property(key) { return properties[key]; },
    isOpen: () => true, isReadable: () => true, readLine: () => 'ISS',
    seek: () => true, error: () => readError ? 1 : 0
  };
  const parser = (openFile, parsed) => {
    if (!empty) parsed.set('25544', { name: 'new', addThis: add });
    if (malformed) openFile.setProperty('tleParseComplete', false);
  };
  const records = new Map([['25544', { name: 'old', addThis: true }], ['manual', { name: 'manual' }]]);
  const run = new Function('parseSatelliteCsvLine', 'parseTleFile', 'parseCsvFile', 'openFile', 'tleList', 'addFlagValue', 'tleURL', executableParse);
  run(parseSatelliteCsvLine, parser, parser, file, records, add, 'source');
  return { records, complete: properties.tleParseComplete };
}
for (const failure of ['malformed', 'empty', 'readError']) {
  test(`actual parser wrapper rejects ${failure} source without merging partial records`, () => {
    const result = parseScenario({ [failure]: true });
    assert.equal(result.complete, false);
    assert.equal(result.records.get('25544').name, 'old');
    assert.equal(result.records.get('manual').name, 'manual');
  });
}
test('actual parser wrapper merges complete source while preserving add preference', () => {
  assert.equal(parseScenario().records.get('25544').name, 'new');
  assert.equal(parseScenario({ add: false }).records.get('25544').name, 'old');
});

test('download batch requires every source and propagates parser failure', () => {
  const download = body('void Satellites::saveDownloadedUpdate(');
  assert.match(download, /if \(!updateSources\[i\]\.file\)\s*\{\s*complete = false;/);
  assert.match(download, /complete = updateSources\[i\]\.file->property\("tleParseComplete"\).toBool\(\) && complete/);
  assert.match(download, /if \(complete && !newData.isEmpty\(\)\)\s*updateSatellites/);
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

function numericConversion(expression, flag) {
  return `(${flag} = /^[-+]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?$/.test((${expression}).trim()), Number(${expression}))`;
}
function translate(sourceBody) {
  return sourceBody
    .replace(/\/\/[^\n]*/g, '')
    .replace(/q(?:Warning|Debug)\(\)[^;]*;/g, '{}')
    .replaceAll(/QLatin1Char\(('(?:[^'\\]|\\.)*')\)/g, '$1')
    .replaceAll(/(?:QStringLiteral|L1S)\(("(?:[^"\\]|\\.)*")\)/g, '$1')
    .replace(/static const QRegularExpression (\w+)\(("(?:[^"\\]|\\.)*")(?:, QRegularExpression::\w+)?\s*\);/g, 'const $1 = new RegExp($2);')
    .replaceAll(/(\w+)\.match\(([^;]+?)\)\.hasMatch\(\)/g, '$1.test($2)')
    .replace(/\bconst (?:QString|QChar|double|auto&?|uint|int) /g, 'const ')
    .replace(/\b(?:QString|bool|int|double|uint) /g, 'let ')
    .replaceAll('.trimmed()', '.trim()')
    .replaceAll('.toUpper()', '.toUpperCase()')
    .replaceAll(/\.mid\((\d+), (\d+)\)/g, '.substr($1, $2)')
    .replaceAll(/\.size\(\)|\.length\(\)/g, '.length')
    .replaceAll(/([\w.]+)\.isEmpty\(\)/g, '($1.length === 0)')
    .replaceAll(/(\w+)\[([^\]]+)\]\.isDigit\(\)/g, '/[0-9]/.test($1[$2])')
    .replaceAll(/(\w+)\[([^\]]+)\]\.digitValue\(\)/g, 'Number($1[$2])')
    .replaceAll(/(\w+)\[([^\]]+)\]\.unicode\(\)/g, '$1[$2]')
    .replaceAll(/([\w.]+)\.replace\((\d+), (\d+), ("[^"]*")\);/g, '$1 = $1.slice(0, $2) + $4 + $1.slice($2 + $3);')
    .replaceAll('std::isfinite', 'Number.isFinite')
    .replaceAll('.toBool()', '')
    .replaceAll('tleList.contains', 'tleList.has')
    .replaceAll(/tleList.insert\(([^,]+), ([^)]+)\)/g, 'tleList.set($1, structuredClone($2))')
    .replaceAll(/Satellite::(Status\w+)/g, 'statuses.$1');
}
const templates = [...source.matchAll(/TLE_LINE[12]_TEMPLATE = "([^"]+)"/g)].map(match => match[1]);
const validateLine = new Function('line', 'lineTemplate', translate(body('bool tleLineValid(')));
const pairCode = translate(body('bool tlePairValid('))
  .replace('for (const QString& line : {first, second})', 'for (const line of [first, second])')
  .replaceAll(/(\w+\.substr\(\d+, \d+\))\.toDouble\(&(\w+)\)/g, (_, expression, flag) => numericConversion(expression, flag))
  .replace('("0." + second.substr(26, 7)).toDouble(&eccentricityOk)', numericConversion('("0." + second.substr(26, 7))', 'eccentricityOk'))
  .replace("first[33] = ' ';", "first = first.slice(0, 33) + ' ' + first.slice(34);");
const validatePair = new Function('tleLineValid', 'TLE_LINE1_TEMPLATE', 'TLE_LINE2_TEMPLATE',
  `return (first, second) => ${pairCode}`)(validateLine, ...templates);
const statuses = Object.fromEntries([...read('plugins/Satellites/src/Satellite.hpp').matchAll(/(Status\w+)\s*=\s*(-?\d+)/g)].map(match => [match[1], Number(match[2])]));
function emptyTle() {
  return { id: '', name: '', first: '', second: '', sourceURL: '', status: 0, addThis: false };
}
const tleCode = translate(body('void Satellites::parseTleFile('))
  .replace('TleData lastData{};', 'let lastData = emptyTle();')
  .replaceAll('TleData()', 'emptyTle()')
  .replace(/const QMap<QString, Satellite::OptStatus> satOpStatusMap = \{([\s\S]*?)\};/, (_, entries) =>
    `const satOpStatusMap = new Map([${entries.replaceAll(/\{([^{}]+)\}/g, '[$1]')}]);`)
  .replace('QString(openFile.readLine())', 'openFile.readLine()')
  .replace('QRegularExpressionMatch match;', 'let match;')
  .replace('line.indexOf(statusRx, 0, &match)>-1', '(match = line.match(statusRx)) !== null')
  .replace('satOpStatusMap.value(match.captured(1).toUpperCase(), statuses.StatusUnknown)', '(satOpStatusMap.get(match[1].toUpperCase()) ?? statuses.StatusUnknown)')
  .replaceAll(/line.replace\((\w+),""\);/g, 'line = line.replace($1, "");')
  .replace('id.toInt()', 'Number(id)');
const parseTle = new Function('statuses', 'emptyTle', 'tlePairValid', 'getSatIdFromLine2',
  `return (openFile, tleList, addFlagValue, tleURL) => ${tleCode}`)(statuses, emptyTle, validatePair, line => String(Number(line.substr(2, 5))));

function inputFile(text) {
  const lines = text.split('\n');
  let cursor = 0;
  const properties = {};
  return {
    isOpen: () => true, isReadable: () => true, atEnd: () => cursor >= lines.length,
    readLine: () => lines[cursor++] ?? '', error: () => 0,
    seek: () => { cursor = 0; return true; },
    setProperty: (key, value) => { properties[key] = value; },
    property: key => properties[key]
  };
}
const bundled = JSON.parse(read('plugins/Satellites/resources/satellites.json')).satellites;
const parseInput = new Function('parseSatelliteCsvLine', 'parseTleFile', 'parseCsvFile',
  `return (openFile, tleList, addFlagValue, tleURL) => ${executableParse}`)(parseSatelliteCsvLine, parseTle, () => assert.fail('Unexpected CSV'));
function parseTleInput(text) {
  const file = inputFile(text);
  const records = new Map();
  parseInput(file, records, true, 'fixture');
  return { records, complete: file.property('tleParseComplete') };
}

test('actual TLE parser accepts every bundled pair, including all zero-prefixed derivatives', () => {
  const entries = Object.entries(bundled);
  assert.equal(entries.length, 3134);
  let compatibleCount = 0;
  for (const [id, satellite] of entries) {
    const parsed = parseTleInput(`${satellite.name}\n${satellite.tle1}\n${satellite.tle2}`);
    assert.equal(parsed.complete, true, id);
    assert.equal(parsed.records.size, 1, id);
    assert.equal([...parsed.records.values()][0].first, satellite.tle1, id);
    if (satellite.tle1[33] === '0') compatibleCount++;
  }
  assert.equal(compatibleCount, 166);
});
test('actual TLE parser initializes first and subsequent unnamed 2LE records to Unknown', () => {
  const fixtures = ['3889', '25544'].map(id => bundled[id]);
  const parsed = parseTleInput(fixtures.flatMap(satellite => [satellite.tle1, satellite.tle2]).join('\n'));
  assert.equal(parsed.complete, true);
  assert.equal(parsed.records.size, 2);
  for (const record of parsed.records.values()) {
    assert.equal(record.status, statuses.StatusUnknown);
    assert.match(record.name, /^NORAD /);
  }
  const mixed = parseTleInput(`Canyon [+]\n${fixtures[0].tle1}\n${fixtures[0].tle2}\n${fixtures[1].tle1}\n${fixtures[1].tle2}`);
  assert.equal(mixed.records.get('3889').status, statuses.StatusOperational);
  assert.equal(mixed.records.get('25544').status, statuses.StatusUnknown);
});
test('actual TLE parser rejects malformed tail and altered checksum without publishing partial batch', () => {
  const satellite = bundled['3889'];
  for (const tail of [satellite.tle1, satellite.tle1 + '\n' + satellite.tle2.slice(0, 68) + '9']) {
    const parsed = parseTleInput(`${satellite.tle1}\n${satellite.tle2}\n${tail}`);
    assert.equal(parsed.complete, false);
    assert.equal(parsed.records.size, 0);
  }
});
test('actual CSV tokenizer preserves comma/escaped quote names and 17 columns', () => {
  const rest = ['1998-067A', '2026-11-11T00:00:00.000000', '15.5', '0.0001', '51.6', '100', '20', '30', '0', 'U', '25544', '999', '50000', '0.0001', '0.00001', '0'];
  const fields = [];
  assert.equal(parseSatelliteCsvLine('"ISS, ""ZARYA""",' + rest.join(','), fields), true);
  assert.equal(fields.length, 17);
  assert.equal(fields[0], 'ISS, "ZARYA"');
  assert.deepEqual(fields.slice(1), rest);
  for (const malformed of ['"unterminated', 'bad"quote,1', '"closed"junk,1']) {
    assert.equal(parseSatelliteCsvLine(malformed, []), false);
  }
});

const csvCode = translate(body('void Satellites::parseCsvFile(')
  .replace('const auto warn = [&openFile,&tleURL,&headerEntries](const QString& what, const QString& why, const QStringList& lineEntries)', 'const warn = (what, why, lineEntries) =>')
  .replace('const auto warnAboutLine = [&warn, &lineEntries](const QString& what, const QString& why)', 'const warnAboutLine = (what, why) =>')
  .replace(/QString\("number of entries[^;]+?\.arg\(headerEntries.size\(\)\)/, '"column count mismatch"'))
  .replace('QString(openFile.readLine())', 'openFile.readLine()')
  .replace('QStringList lineEntries;', 'const lineEntries = [];')
  .replace('TleData data{};', 'const data = emptyTle();')
  .replace('SatCsvEntry entry;', 'const entry = {};')
  .replace('data.name.trim().isEmpty()', '(data.name.trim().length === 0)')
  .replaceAll(/(lineEntries\[\w+\]\.trim\(\))\.toDouble\(&(\w+)\)/g, (_, expression, flag) => numericConversion(expression, flag))
  .replaceAll(/(lineEntries\[\w+\]\.trim\(\)|data.id)\.toUInt\(&(\w+)\)/g, (_, expression, flag) => `(${flag} = /^\\d+$/.test(${expression}), Number(${expression}))`);
const csvHeader = ['OBJECT_NAME', 'OBJECT_ID', 'EPOCH', 'MEAN_MOTION', 'ECCENTRICITY', 'INCLINATION', 'RA_OF_ASC_NODE', 'ARG_OF_PERICENTER', 'MEAN_ANOMALY', 'EPHEMERIS_TYPE', 'CLASSIFICATION_TYPE', 'NORAD_CAT_ID', 'ELEMENT_SET_NO', 'REV_AT_EPOCH', 'BSTAR', 'MEAN_MOTION_DOT', 'MEAN_MOTION_DDOT'];
const csvRecord = '"ISS, ""ZARYA""",1998-067A,2026-11-11T00:00:00.000000,15.5,0.0001,51.6,100,20,30,0,U,25544,999,50000,0.0001,0.00001,0';
function parseCsvInput(text) {
  const generatedInputs = [];
  const parseCsv = new Function('parseSatelliteCsvLine', 'emptyTle', 'tlePairValid', 'generateTleLine1', 'generateTleLine2',
    `return (openFile, headerEntries, tleList, addFlagValue, tleURL) => ${csvCode}`)(
    parseSatelliteCsvLine, emptyTle, validatePair,
    entry => { generatedInputs.push(structuredClone(entry)); return bundled['25544'].tle1; },
    () => bundled['25544'].tle2);
  const parseFile = new Function('parseSatelliteCsvLine', 'parseTleFile', 'parseCsvFile',
    `return (openFile, tleList, addFlagValue, tleURL) => ${executableParse}`)(parseSatelliteCsvLine, parseTle, parseCsv);
  const file = inputFile(text);
  const records = new Map();
  parseFile(file, records, true, 'fixture');
  return { records, generatedInputs, complete: file.property('tleParseComplete') };
}
test('actual CSV parser maps quoted 17-column records and quoted headers into satellite data', () => {
  const parsed = parseCsvInput(csvHeader.map(name => `"${name}"`).join(',') + '\n' + csvRecord);
  assert.equal(parsed.complete, true);
  assert.equal(parsed.records.size, 1);
  assert.equal(parsed.records.get('25544').name, 'ISS, "ZARYA"');
  assert.equal(parsed.records.get('25544').status, statuses.StatusUnknown);
  assert.deepEqual(parsed.generatedInputs[0], {
    object_id: '1998-067A', epoch: '2026-11-11T00:00:00.000000', mean_motion: 15.5,
    eccentricity: 0.0001, inclination: 51.6, ra_of_asc_node: 100, arg_of_pericenter: 20,
    mean_anomaly: 30, ephemeris_type: 0, classification_type: 'U', element_set_no: 999,
    rev_at_epoch: 50000, bstar: 0.0001, mean_motion_dot: 0.00001, mean_motion_ddot: 0
  });
});
test('actual CSV parser discards whole batch after bad quotes, field count or numeric tail', () => {
  for (const malformed of ['"unterminated', csvRecord + ',extra', csvRecord.replace(',15.5,', ',invalid,')]) {
    const parsed = parseCsvInput(csvHeader.join(',') + '\n' + csvRecord + '\n' + malformed);
    assert.equal(parsed.complete, false);
    assert.equal(parsed.records.size, 0);
    assert.equal(parsed.generatedInputs.length, 1);
  }
});
