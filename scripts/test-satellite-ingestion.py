import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def build_parser(folder):
    source = (ROOT / 'plugins/Satellites/src/Satellites.cpp').read_text()
    header = (ROOT / 'plugins/Satellites/src/Satellites.hpp').read_text()
    record = header[header.index('struct TleData\n'):header.index('//! TLE update source')]
    helpers = source[source.index('struct SatCsvEntry'):source.index('#undef TLE_POS_MUST_BE_LE')]
    parsers = source[source.index('static bool parseSatelliteCsvLine'):source.index('void Satellites::loadExtraData')]
    automatic_update = source[source.index('void Satellites::checkForUpdate(void)'):source.index('void Satellites::updateFromOnlineSources()')]
    program = '''
#include <QtCore>
#include <cmath>
#include <functional>
#include <iostream>
#define L1S(value) QLatin1String(value)
struct Satellite { enum OptStatus { StatusUnknown, StatusOperational, StatusNonoperational,
StatusPartiallyOperational, StatusStandby, StatusSpare, StatusExtendedMission, StatusDecayed }; };
''' + record + '''
static constexpr qint64 satelliteUpdateMaxBytes = 32 * 1024 * 1024;
class Satellites {
public:
enum { Updating = 0 };
bool updatesEnabled = true;
int updateState = 1;
int updateFrequencyHours = 72;
int attempts = 0;
QPair<QDateTime, double> lastUpdate;
QDateTime nextAutomaticUpdateAttempt;
bool scheduledUpdate = false;
bool lastAttemptWasScheduled = false;
void checkForUpdate(void);
void updateFromOnlineSources() { ++attempts; lastAttemptWasScheduled = scheduledUpdate; }
static void parseDataFile(QFile&, TleDataHash&, bool, const QString&);
static void parseTleFile(QFile&, TleDataHash&, bool, const QString&);
static void parseCsvFile(QFile&, const QStringList&, TleDataHash&, bool, const QString&);
static QString decodeSatIDFromAlpha5(QString&);
static QString getSatIdFromLine2(const QString&);
};
''' + helpers + '\n' + parsers + '\n' + automatic_update + '''
int main(int argc, char** argv) {
    QCoreApplication application(argc, argv);
    Satellites updateProbe;
    updateProbe.lastUpdate.first = QDateTime::currentDateTime().addDays(-4);
    updateProbe.nextAutomaticUpdateAttempt = QDateTime::currentDateTime().addSecs(1800);
    updateProbe.checkForUpdate();
    if (updateProbe.attempts != 0) return 2;
    updateProbe.nextAutomaticUpdateAttempt = QDateTime::currentDateTime().addSecs(-1);
    updateProbe.checkForUpdate();
    if (updateProbe.attempts != 1) return 3;
    if (!updateProbe.lastAttemptWasScheduled || updateProbe.scheduledUpdate) return 7;
    updateProbe.updateState = Satellites::Updating;
    updateProbe.checkForUpdate();
    if (updateProbe.attempts != 1) return 4;
    updateProbe.updateState = 1;
    updateProbe.lastUpdate.first = QDateTime::currentDateTime();
    updateProbe.checkForUpdate();
    if (updateProbe.attempts != 1) return 5;
    updateProbe.lastUpdate.first = QDateTime::currentDateTime().addDays(-4);
    updateProbe.updatesEnabled = false;
    updateProbe.checkForUpdate();
    if (updateProbe.attempts != 1) return 8;
    TleDataHash records;
    QJsonArray results;
    for (int index = 1; index < argc; ++index) {
        QFile file(QString::fromLocal8Bit(argv[index]));
        if (!file.open(QIODevice::ReadOnly)) return 6;
        Satellites::parseDataFile(file, records, index % 2 == 1, QString());
        QJsonObject orbits;
        for (auto entry = records.constBegin(); entry != records.constEnd() && !qEnvironmentVariableIsSet("SATELLITE_PARSE_SUMMARY"); ++entry) {
            const auto& record = entry.value();
            orbits[entry.key()] = QJsonObject{{"first", record.first}, {"second", record.second},
                {"name", record.name}, {"addThis", record.addThis}};
        }
        results.append(QJsonObject{{"complete", file.property("tleParseComplete").toBool()},
            {"count", records.size()}, {"orbits", orbits}});
    }
    std::cout << QJsonDocument(results).toJson(QJsonDocument::Compact).constData();
}
'''
    path = folder / 'parser.cpp'
    path.write_text(program)
    flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', '--libs', 'Qt6Core'], text=True))
    binary = folder / 'parser'
    subprocess.run(['c++', '-std=c++17', '-fPIC', str(path), '-o', str(binary), *flags], check=True)
    return binary


def run_parser(binary, paths):
    result = subprocess.run([str(binary), *map(str, paths)], capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def checksum(line):
    prefix = line[:68]
    return prefix + str(sum(int(char) if char.isdigit() else 1 if char == '-' else 0 for char in prefix) % 10)


def fixtures():
    catalog = json.loads((ROOT / 'plugins/Satellites/resources/satellites.json').read_text())
    satellite = catalog['satellites']['25544']
    first, second = satellite['tle1'], satellite['tle2']
    first = checksum(first[:18] + '26300.50000000' + first[32:])
    second = checksum(second)
    older = checksum(first[:18] + '26299.50000000' + first[32:])
    valid = 'ISS (ZARYA)\n' + first + '\n' + second + '\n'
    header = 'OBJECT_NAME,OBJECT_ID,EPOCH,MEAN_MOTION,ECCENTRICITY,INCLINATION,RA_OF_ASC_NODE,ARG_OF_PERICENTER,MEAN_ANOMALY,EPHEMERIS_TYPE,CLASSIFICATION_TYPE,NORAD_CAT_ID,ELEMENT_SET_NO,REV_AT_EPOCH,BSTAR,MEAN_MOTION_DOT,MEAN_MOTION_DDOT\n'
    row = '"ISS, ZARYA",1998-067A,2026-10-27T12:00:00.000000,15.5,0.0004,51.6,100.2,50.3,90.4,0,U,25544,999,50000,0.00012,0.00001,0\n'
    return {
        'valid-3le': (valid, True),
        'valid-2le': (first + '\n' + second + '\n', True),
        'valid-bom-crlf': ('\ufeff' + valid.replace('\n', '\r\n'), True),
        'valid-csv': (header + row, True),
        'valid-csv-bom': ('\ufeff' + header + row, True),
        'older': ('Older ISS\n' + older + '\n' + second + '\n', True),
        'duplicate-new-first': (valid + 'Older ISS\n' + older + '\n' + second + '\n', True),
        'duplicate-old-first': ('Older ISS\n' + older + '\n' + second + '\n' + valid, True),
        'empty': ('', False),
        'html': ('<!DOCTYPE html><html>blocked</html>', False),
        'truncated': ('ISS\n' + first + '\n', False),
        'checksum': (valid.replace(second, second[:68] + str((int(second[68]) + 1) % 10)), False),
        'id-mismatch': (valid.replace(second, checksum(second[:2] + '99999' + second[7:])), False),
        'bad-angle': (valid.replace(second, checksum(second[:17] + '999.0000' + second[25:])), False),
        'bad-day': (valid.replace(first, checksum(first[:18] + '26366.50000000' + first[32:])), False),
        'bad-inclination': (valid.replace(second, checksum(second[:8] + '181.0000' + second[16:])), False),
        'partial': (valid + 'BROKEN\n1 12345\n', False),
        'nan-csv': (header + row.replace(',15.5,', ',NaN,'), False),
        'infinite-csv': (header + row.replace(',0.00012,', ',inf,'), False),
        'bad-csv-angle': (header + row.replace(',100.2,', ',400.2,'), False),
        'csv-bad-quote': (header + row.replace('"ISS, ZARYA"', '"ISS, ZARYA'), False),
        'long-line': ('X' * 5000 + '\n' + first + '\n' + second + '\n', False),
        'oversize': ('X' * (32 * 1024 * 1024 + 1), False),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--files', nargs='*')
    parser.add_argument('--export-fixtures', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='satellite-ingestion-') as temp:
        folder = Path(temp)
        binary = build_parser(folder)
        if args.files:
            os.environ['SATELLITE_PARSE_SUMMARY'] = '1'
            for path, result in zip(args.files, run_parser(binary, args.files)):
                print(json.dumps({'path': path, 'complete': result['complete'], 'mergedCount': result['count']}))
            return
        cases = fixtures()
        fixture_dir = args.export_fixtures or folder
        fixture_dir.mkdir(parents=True, exist_ok=True)
        paths = {}
        for name, (data, expected) in cases.items():
            path = fixture_dir / (name + ('.csv' if 'csv' in name else '.tle'))
            path.write_bytes(data.encode())
            paths[name] = path
            result = run_parser(binary, [path])[0]
            assert result['complete'] == expected, (name, result)
            assert result['count'] == (1 if expected else 0), name
            print('PASS', name)
        for name, (_, expected) in cases.items():
            results = run_parser(binary, [paths['valid-3le'], paths[name]])
            if not expected or name in ['older', 'duplicate-new-first', 'duplicate-old-first']:
                assert results[0]['orbits'] == results[1]['orbits'], name
        reversed_order = run_parser(binary, [paths['older'], paths['valid-3le']])
        assert reversed_order[-1]['orbits']['25544']['first'][18:32] == '26300.50000000'
        assert reversed_order[-1]['orbits']['25544']['addThis'] is True
        print('PASS merge order, add flag, and rollback for every malformed source')


if __name__ == '__main__':
    main()
