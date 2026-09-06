#!/usr/bin/env python3
import argparse
import json
import math
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
HDC = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    checks = []
    samples = []

    def command(name, payload=None):
        invocation = ['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                      '--command', name, '--json']
        if payload is not None:
            invocation += ['--payload', str(payload)]
        completed = subprocess.run(invocation, capture_output=True, text=True, timeout=65)
        response = json.loads(completed.stdout)
        if not response.get('ok'):
            raise RuntimeError(response)
        return response

    def device(*parts):
        subprocess.run([HDC, '-t', args.device, *parts], check=True, capture_output=True, timeout=30)

    def expect(name, condition):
        checks.append({'name': name, 'ok': bool(condition)})
        if not condition:
            raise AssertionError(name)

    def texts():
        with tempfile.TemporaryDirectory() as folder:
            remote = '/data/local/tmp/distance-audit-layout.json'
            local = Path(folder) / 'layout.json'
            device('shell', 'uitest', 'dumpLayout', '-p', remote)
            device('file', 'recv', remote, str(local))
            values = []

            def visit(node):
                value = node.get('attributes', {}).get('text')
                if value:
                    values.append(value)
                for child in node.get('children', []):
                    visit(child)

            visit(json.loads(local.read_text()))
            return values

    original_time = command('getSimulationTime')
    original_info = command('getInformationSettings')
    original_selection = command('getSelectedObjectInfo')
    started = time.monotonic()
    cases = [
        ('Sirius', 'ly', None), ('Vega', 'ly', None), ('Betelgeuse', None, None),
        ('M31', 'kpc', None), ('M42', 'kpc', None), ('M45', 'kpc', None),
        ('Moon', 'AU', None), ('Sun', 'AU', None), ('STARLETTE', 'km', None),
        ('catalog|Exoplanets|51 Peg|selectOnly', 'pc', None),
        ('catalog|Pulsars|PSR J0437-4715|selectOnly', 'kpc', None),
        ('SN 1987A', 'kly', 160000.), ('catalog|Novae|GK Per|selectOnly', 'kly', 1500.),
        ('catalog|Novae|T Aur|selectOnly', None, None),
        ('catalog|Quasars|MS 23574-3520|selectOnly', None, None),
    ]
    try:
        command('setTimeRate', 0)
        command('setInformationSetting', 'mode|all')
        for query, unit, expected_ly in cases:
            selected = command('searchObject', query)
            expect(query + ' selects the requested catalogue object', selected.get('found') is True)
            detailed = command('getSelectedObjectInfo', 'full')
            distance = command('getDistanceInfo')
            legacy = command('getObjectInfo')['info']
            samples.append({'query': query, 'selection': detailed, 'distance': distance})
            expect(query + ' legacy object info shares distance status', legacy['distanceStatus'] == distance['distanceStatus'])
            expect(query + ' legacy altitude is an angle, not vector component', abs(legacy['alt'] - detailed['altitude']) < 1e-7)
            expect(query + ' selected title has a name or catalogue ID', bool(selected.get('name')))
            expect(query + ' status agrees between summary and distance CLI', selected['distanceStatus'] == distance['distanceStatus'])
            if unit:
                expect(query + ' source unit is correct', selected['distanceUnit'] == unit)
                expect(query + ' distance is finite and positive', math.isfinite(selected['distanceLightYears']) and selected['distanceLightYears'] > 0)
                expect(query + ' CLI keeps numeric distance with explicit unit', isinstance(distance['distance'], (float, int)) and distance['distanceUnit'] == unit)
                expect(query + ' full and compact distance agree', detailed['distance'] == selected['distance'] == distance['distanceText'])
                if expected_ly:
                    expect(query + ' converts catalogue distance correctly', abs(selected['distanceLightYears'] - expected_ly) < 0.01)
            if query == 'Sirius':
                expect('Sirius is at approximately 8.6 light years', 8 < selected['distanceLightYears'] < 9)
                fields = {field['key']: field['value'] for field in detailed.get('detailFields', [])}
                expect('stellar parallax is in mas, not arcseconds mislabeled mas', float(fields['stellarParallax'].split()[0]) > 300)
                expect('stellar absolute magnitude matches desktop formula', 1 < float(fields['stellarAbsoluteMagnitude']) < 2)
                expect('stellar distance includes its parallax uncertainty', selected.get('distanceErrorLightYears', 0) > 0)
            if query.endswith('MS 23574-3520|selectOnly'):
                expect('quasar is redshift-only, without invented distance', selected['distanceStatus'] == 'redshift_only' and 'distance' not in selected)
                expect('quasar keeps its structured redshift', any(field['key'] == 'redshift' for field in detailed['detailFields']))
            if query == 'SN 1987A':
                spoken = command('getObjectSpokenText')['text']
                expect('spoken distance is also corrected to light years', '160000.00 光年' in spoken and '160.00 天文单位' not in spoken)
            if query.endswith('T Aur|selectOnly'):
                expect('missing nova distance is explicit, not zero AU', selected['distanceStatus'] == 'unavailable' and 'distance' not in selected)
            command('setObjectDetailTab', '1')
            time.sleep(0.35)
            visible = texts()
            if unit:
                expect(query + ' distance appears in the visible summary', selected.get('distanceCompact', selected['distance']) in visible)
            else:
                expect(query + ' information panel remains readable', len(visible) > 5)
            if query in ['Sirius', 'M31'] or query.endswith('MS 23574-3520|selectOnly'):
                name = 'quasar' if 'Quasars' in query else query.lower()
                device('shell', 'snapshot_display', '-f', f'/data/local/tmp/distance-{name}.jpeg')
                device('file', 'recv', f'/data/local/tmp/distance-{name}.jpeg', f'/tmp/distance-{name}.jpeg')
    finally:
        command('setInformationSetting', f"mode|{original_info['infoMode']}")
        command('setTimeRate', 0)
        command('setJD', original_time['jd'] + (time.monotonic() - started) * original_time['timeRate'])
        command('setTimeRate', original_time['timeRate'])
        if original_selection.get('found'):
            command('searchObject', original_selection.get('englishName') or original_selection['name'])
        else:
            command('clearSelection')
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({'device': args.device, 'checks': checks, 'samples': samples}, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'passed': len(checks), 'report': str(args.output)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
