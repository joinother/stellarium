import argparse
import json
from pathlib import Path
import subprocess
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
        result = subprocess.run(invocation, capture_output=True, text=True, timeout=75)
        if result.returncode != 0:
            raise RuntimeError(result.stdout or result.stderr)
        response = json.loads(result.stdout)
        if not response.get('ok'):
            raise RuntimeError(response)
        return response

    def expect(name, condition):
        checks.append({'name': name, 'ok': bool(condition)})
        if not condition:
            raise AssertionError(name)

    def panel(group=None):
        for attempt in range(20):
            state = command('getSatellitePanelState')
            if not state['loading'] and (group is None or state['group'] == group):
                return state
            time.sleep(0.15)
        raise AssertionError('satellite panel did not finish loading')

    def pid():
        return subprocess.check_output([HDC, '-t', args.device, 'shell', 'pidof', 'com.joinother.skyinstrument'], text=True).strip()

    def screenshot(name):
        remote = f'/data/local/tmp/{name}.jpeg'
        subprocess.run([HDC, '-t', args.device, 'shell', 'snapshot_display', '-f', remote], check=True, capture_output=True)
        subprocess.run([HDC, '-t', args.device, 'file', 'recv', remote, f'/tmp/{name}.jpeg'], check=True, capture_output=True)

    original = command('getSimulationTime')
    selection = command('getSelectedObjectInfo')
    flags = command('getSatellites')['satellites']
    atmosphere = command('getAtmosphereFlags')['flags']
    view = command('getViewDirection')
    original_pid = pid()
    try:
        command('openUiPanel', 'satellites')
        time.sleep(1)
        initial = panel()
        expect('group catalogue is populated', len(initial['groups']) > 10)
        command('setSatellitePanelScroll', 600)
        time.sleep(0.2)
        baseline = panel()['scrollY']
        expect('semantic scroll moved the satellite panel', baseline > 0)
        for group in ['active', 'amateur', 'argos', 'beidou', 'visual', '']:
            expect(group + ' exists in the catalogue', group == '' or group in initial['groups'])
            command('setSatellitePanelGroup', group)
            state = panel(group)
            native = command('getSatellites', group + '||40')['satellites']
            samples.append({'group': group, 'panel': state, 'nativeElapsedMs': native['elapsedMs']})
            expect(group + ' UI has the authoritative matching results', state['matchedCount'] == native['matchedCount'] and state['ids'] == [item['id'] for item in native['items']])
            expect(group + ' does not jump the parent scroll', abs(state['scrollY'] - baseline) < 2)
            revision = state['requestId']
            command('setSatellitePanelGroup', group)
            expect(group + ' same-value selection does not reload', panel(group)['requestId'] == revision)
        screenshot('satellite-groups-stable')
        command('setTimeRate', 0)
        command('setJD', 2461289.883)
        command('setSatellitesFlag', 'hints:1')
        command('setSatellitesFlag', 'orbitLines:1')
        time.sleep(0.2)
        expect('CLI orbit toggle is reflected in the existing ArkUI panel', panel()['orbitLines'] is True)
        command('searchObject', 'catalog|Satellites|STARLINK-36933|selectOnly')
        time.sleep(0.5)
        orbit = command('getSatellites')['satellites']['selectedOrbit']
        samples.append({'orbit': orbit})
        expect('selected starlink receives a transient orbit preview', orbit['selectedPreview'] and orbit['requested'])
        expect('preview does not overwrite saved orbit preference', orbit['configured'] is False)
        expect('valid orbit points are actually sampled', orbit['orbitValid'] and orbit['pointCount'] > 2)
        draws = orbit['drawCount']
        time.sleep(0.4)
        expect('renderer submits the selected orbit path', command('getSatellites')['satellites']['selectedOrbit']['drawCount'] > draws)
        command('setAtmosphereFlag', 'landscape|0')
        command('setAtmosphereFlag', 'atmosphere|0')
        command('setAtmosphereFlag', 'fog|0')
        command('closeUiPanel')
        command('moveToSelected')
        time.sleep(1)
        screenshot('satellite-selected-orbit')
        command('setSatellitesFlag', 'orbitLines:0')
        time.sleep(0.3)
        off = command('getSatellites')['satellites']['selectedOrbit']
        expect('CLI orbit disable is reflected in ArkUI', panel()['orbitLines'] is False)
        time.sleep(0.4)
        expect('disabled orbit switch stops drawing cached points', command('getSatellites')['satellites']['selectedOrbit']['drawCount'] == off['drawCount'])
        command('setSatellitesFlag', 'orbitLines:1')
        command('searchObject', 'catalog|Satellites|STARLINK-37489|selectOnly')
        time.sleep(0.4)
        invalid = command('getSatellites')['satellites']['selectedOrbit']
        expect('invalid TLE never renders a selected orbit', not invalid['orbitValid'] and invalid['drawCount'] == 0)
        expect('application did not restart during the tests', pid() == original_pid)
    finally:
        command('setJD', original['jd'])
        command('setTimeRate', original['timeRate'])
        command('setSatellitesFlag', 'hints:' + str(int(flags['hints'])))
        command('setSatellitesFlag', 'orbitLines:' + str(int(flags['orbitLines'])))
        for name, enabled in atmosphere.items():
            command('setAtmosphereFlag', name + '|' + str(int(enabled)))
        if selection.get('found') and selection.get('englishName'):
            command('searchObject', selection['englishName'])
        else:
            command('clearSelection')
        command('moveToAltAz', f"{view['azimuth']}|{view['altitude']}|0")
        args.output.write_text(json.dumps({'checks': checks, 'samples': samples}, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'passed': len(checks), 'report': str(args.output)}))


if __name__ == '__main__':
    main()
