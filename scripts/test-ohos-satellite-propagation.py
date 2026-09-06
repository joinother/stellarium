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

    def command(name, payload=None, allow_error=False):
        invocation = ['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                      '--command', name, '--json']
        if payload is not None:
            invocation += ['--payload', str(payload)]
        completed = subprocess.run(invocation, capture_output=True, text=True, timeout=60)
        if allow_error and completed.returncode != 0:
            encoded = completed.stdout.strip() or completed.stderr.strip()
            if encoded.startswith('{'):
                return json.loads(encoded)
        if completed.returncode != 0 or not completed.stdout.strip():
            raise RuntimeError(f'{name}: {completed.stderr or completed.stdout}')
        response = json.loads(completed.stdout)
        if not response.get('ok'):
            raise RuntimeError(response)
        return response

    def expect(name, condition):
        checks.append({'name': name, 'ok': bool(condition)})
        if not condition:
            raise AssertionError(name)

    def texts():
        with tempfile.TemporaryDirectory() as folder:
            remote = '/data/local/tmp/satellite-propagation-layout.json'
            local = Path(folder) / 'layout.json'
            subprocess.run([HDC, '-t', args.device, 'shell', 'uitest', 'dumpLayout', '-p', remote], check=True, capture_output=True)
            subprocess.run([HDC, '-t', args.device, 'file', 'recv', remote, str(local)], check=True, capture_output=True)
            return local.read_text()

    startup_attempts = 0
    while True:
        startup_attempts += 1
        try:
            original = command('getSimulationTime')
            break
        except RuntimeError as error:
            if startup_attempts >= 4 or not any(message in str(error) for message in ['command timeout', 'bridge not available']):
                raise
            time.sleep(1)
    def process_id():
        return subprocess.check_output([HDC, '-t', args.device, 'shell', 'pidof', 'com.joinother.skyinstrument'], text=True).strip()

    original_pid = process_id()
    selection = command('getSelectedObjectInfo')
    information = command('getInformationSettings')
    started = time.monotonic()
    now = 2461289.883
    epoch = 2461215.75002315
    try:
        command('setTimeRate', 0)
        command('setJD', now)
        command('setInformationSetting', 'mode|all')
        for target in ['STARLINK-37238', 'STARLINK-37365', 'STARLINK-37489']:
            selected = command('searchObject', f'catalog|Satellites|{target}|selectOnly')
            expect(target + ' remains discoverable in the catalogue', selected.get('found') and selected.get('englishName') == target)
            state = command('getSelectedObjectInfo', 'full')
            samples.append(state)
            expect(target + ' rejects divergent propagation', state.get('propagationStatus') == 'divergent_extrapolation' and state.get('orbitValid') is False)
            expect(target + ' does not publish invented range or sky coordinates', state.get('distanceStatus') == 'invalid_orbit' and all(key not in state for key in ['distance', 'altitude', 'azimuth', 'raJ2000Degrees']))
            expect(target + ' exposes actual per-object TLE age', state.get('tleOutdated') and 74 < state.get('tleAgeDays', 0) < 75)
            passes = command('getSatelliteDetail', '|1|1')['satelliteDetail']
            expect(target + ' does not generate false passes', passes['dataStatus'] == 'invalid_orbit' and passes['allPasses'] == [])
            distance = command('getDistanceInfo')
            expect(target + ' distance CLI also rejects this orbit', distance['distanceStatus'] == 'invalid_orbit' and 'distance' not in distance)
            for navigation, argument in [('moveToSelected', None), ('moveToSelectedAt', '500|350|1000|700|center'), ('setTracking', 'true')]:
                rejected = command(navigation, argument, allow_error=True)
                expect(target + ' rejects ' + navigation + ' without a valid position', rejected.get('ok') is False and rejected.get('errorCode') == 'invalid_orbit')
        command('setObjectDetailTab', '0')
        time.sleep(0.5)
        expect('observation page explains that invalid markers are hidden', '轨道推算异常' in texts())
        subprocess.run([HDC, '-t', args.device, 'shell', 'snapshot_display', '-f', '/data/local/tmp/satellite-invalid-orbit.jpeg'], check=True, capture_output=True)
        subprocess.run([HDC, '-t', args.device, 'file', 'recv', '/data/local/tmp/satellite-invalid-orbit.jpeg', '/tmp/satellite-invalid-orbit.jpeg'], check=True, capture_output=True)
        command('searchObject', 'catalog|Satellites|STARLINK-37365|selectOnly')
        command('setJD', epoch)
        recovered = command('getSelectedObjectInfo')
        expect('returning to TLE epoch recovers without restart or toggling visibility', recovered.get('orbitValid') and recovered.get('propagationStatus') == 'valid')
        expect('TLE epoch retains fractional UTC day', abs(recovered.get('tleAgeDays', 99)) < 1e-7)
        positions = []
        for offset in [0, 1, 2, 10]:
            command('setJD', epoch + offset / 86400)
            detail = command('getSatelliteDetail', '|1|1')['satelliteDetail']
            samples.append(detail)
            radius = math.sqrt(sum(detail[f'TEME-km-{axis}'] ** 2 for axis in ['X', 'Y', 'Z']))
            speed = math.sqrt(sum(detail[f'TEME-speed-{axis}'] ** 2 for axis in ['X', 'Y', 'Z']))
            expect(f'epoch+{offset}s has LEO radius and orbital speed', 6700 < radius < 6900 and 7 < speed < 9)
            positions.append([detail[f'TEME-km-{axis}'] for axis in ['X', 'Y', 'Z']])
        displacement = math.sqrt(sum((positions[1][axis] - positions[0][axis]) ** 2 for axis in range(3)))
        expect('one simulated second moves several kilometres, not millions', 7 < displacement < 9)
        command('setJD', now)
        expect('returning to present suppresses the divergent orbit again', command('getSelectedObjectInfo').get('orbitValid') is False)
        for target in ['STARLINK-36933', 'STARLETTE', 'ISS (ZARYA)', 'Rhyolite 3', 'Vortex 1']:
            selected = command('searchObject', f'catalog|Satellites|{target}|selectOnly')
            expect(target + ' selects the correct object', selected.get('found') and selected.get('englishName') == target)
            state = command('getSelectedObjectInfo')
            samples.append(state)
            expect(target + ' healthy orbit remains available', state.get('orbitValid') and state.get('distanceKm', 0) > 0)
            if target == 'STARLINK-36933':
                expect('new September TLE replaces old June TLE on existing installation', 0 < state['tleAgeDays'] < 1 and state.get('tleOutdated') is False)
                command('setObjectDetailTab', '0')
                time.sleep(0.4)
                subprocess.run([HDC, '-t', args.device, 'shell', 'snapshot_display', '-f', '/data/local/tmp/starlink36933-corrected.jpeg'], check=True, capture_output=True)
                subprocess.run([HDC, '-t', args.device, 'file', 'recv', '/data/local/tmp/starlink36933-corrected.jpeg', '/tmp/starlink36933-corrected.jpeg'], check=True, capture_output=True)
        expect('application process stays alive throughout regression', process_id() == original_pid)
    finally:
        command('setTimeRate', 0)
        command('setJD', original['jd'] + (time.monotonic() - started) * original['timeRate'])
        command('setTimeRate', original['timeRate'])
        command('setInformationSetting', 'mode|' + information['infoMode'])
        if selection.get('found'):
            command('searchObject', selection.get('englishName') or selection['name'])
        else:
            command('clearSelection')
        args.output.write_text(json.dumps({'device': args.device, 'startupAttempts': startup_attempts, 'checks': checks, 'samples': samples}, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'passed': len(checks), 'report': str(args.output)}))


if __name__ == '__main__':
    main()
