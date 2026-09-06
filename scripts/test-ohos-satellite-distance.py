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
        response = json.loads(subprocess.run(invocation, capture_output=True, text=True, timeout=60).stdout)
        if not response.get('ok'):
            raise RuntimeError(response)
        return response

    def device(*parts):
        subprocess.run([HDC, '-t', args.device, *parts], check=True, capture_output=True, timeout=30)

    def expect(name, condition):
        checks.append({'name': name, 'ok': bool(condition)})
        if not condition:
            raise AssertionError(name)

    def ui_texts():
        with tempfile.TemporaryDirectory() as folder:
            remote = '/data/local/tmp/satellite-distance.json'
            local = Path(folder) / 'layout.json'
            device('shell', 'uitest', 'dumpLayout', '-p', remote)
            device('file', 'recv', remote, str(local))
            texts = []

            def visit(node):
                if node.get('attributes', {}).get('text'):
                    texts.append(node['attributes']['text'])
                for child in node.get('children', []):
                    visit(child)

            visit(json.loads(local.read_text()))
            return texts

    original = command('getSimulationTime')
    selection = command('getSelectedObjectInfo')
    started = time.monotonic()
    try:
        command('setTimeRate', 0)
        command('searchObject', 'STARLETTE')
        time.sleep(1)
        frozen = command('getSelectedObjectInfo')
        samples.append(frozen)
        expect('satellite distance is a finite positive km value', math.isfinite(frozen['distanceKm']) and frozen['distanceKm'] > 0)
        expect('distance explicitly refers to the observer', frozen['distanceReference'] == 'observer' and frozen['distanceStatus'] == 'computed')
        live = {field['key']: field['value'] for field in frozen['liveDetailFields']}
        expect('summary distance equals the native slant range, not orbital height',
               frozen['distance'] == live['range'] and frozen['distance'] != live['height'])
        time.sleep(1)
        texts = ui_texts()
        expect('visible card distance matches the paused native calculation', texts[texts.index('距离') + 1] == frozen['distance'])
        command('setTimeRate', 1 / 86400)
        time.sleep(3)
        moving = command('getSelectedObjectInfo')
        samples.append(moving)
        expect('satellite distance changes while simulation runs', moving['distanceKm'] != frozen['distanceKm'])
        time.sleep(1)
        texts = ui_texts()
        expect('visible summary distance also changes', texts[texts.index('距离') + 1] != frozen['distance'])
        device('shell', 'snapshot_display', '-f', '/data/local/tmp/satellite-distance.jpeg')
        device('file', 'recv', '/data/local/tmp/satellite-distance.jpeg', '/tmp/satellite-distance.jpeg')
        command('setTimeRate', 0)
        command('searchObject', 'Moon')
        moon = command('getSelectedObjectInfo')
        samples.append(moon)
        expect('natural satellite keeps the solar-system AU distance', moon['distance'].endswith(' AU') and 'distanceKm' not in moon)
        command('clearSelection')
        cleared = command('getSelectedObjectInfo')
        expect('cleared selection does not retain a distance', not cleared['found'] and 'distance' not in cleared)
    finally:
        command('setTimeRate', 0)
        command('setJD', original['jd'] + (time.monotonic() - started) * original['timeRate'])
        command('setTimeRate', original['timeRate'])
        if selection.get('found'):
            command('searchObject', selection.get('englishName') or selection['name'])
        else:
            command('clearSelection')
        args.output.write_text(json.dumps({'checks': checks, 'samples': samples,
            'restoredRate': command('getSimulationTime')['timeRate']}, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'passed': len(checks), 'report': str(args.output)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
