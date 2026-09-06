import argparse
import json
import re
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
HDC = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--touch', action='store_true')
    args = parser.parse_args()
    checks = []
    frames = []

    def command(name, payload=None, allow_error=False):
        invocation = ['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                      '--command', name, '--json']
        if payload is not None:
            invocation += ['--payload', str(payload)]
        completed = subprocess.run(invocation, capture_output=True, text=True, timeout=65)
        response = json.loads(completed.stdout)
        if not allow_error and not response.get('ok'):
            raise RuntimeError(response)
        return response

    def expect(name, condition):
        checks.append({'name': name, 'ok': bool(condition)})
        if not condition:
            raise AssertionError(name)

    def frame(kind, after=0, immersive=False, target=None, jd=None):
        for attempt in range(35):
            result = command('getObjectModelView', allow_error=True)
            if (result.get('kind') == kind and result.get('renderedAt', 0) > after
                    and result.get('immersive') == immersive and result.get('renderSize') == (640 if immersive else 320)
                    and (target is None or result.get('selectedEnglishName') == target)
                    and (jd is None or abs(result.get('lighting', {}).get('jd', 0) - jd) < 1e-5)):
                return result
            time.sleep(0.2)
        raise RuntimeError('model did not produce the requested frame: ' + str(result))

    def screenshot(name):
        remote = '/data/local/tmp/procedural-' + name + '.jpeg'
        local = args.output.parent / ('procedural-' + name + '.jpeg')
        subprocess.run([HDC, '-t', args.device, 'shell', 'snapshot_display', '-f', remote], check=True, capture_output=True)
        subprocess.run([HDC, '-t', args.device, 'file', 'recv', remote, str(local)], check=True, capture_output=True)

    def pid():
        return subprocess.check_output([HDC, '-t', args.device, 'shell', 'pidof',
                                        'com.joinother.skyinstrument'], text=True).strip()

    def hit_bounds(identifier):
        remote = '/data/local/tmp/procedural-hit-layout.json'
        local = args.output.parent / 'procedural-hit-layout.json'
        subprocess.run([HDC, '-t', args.device, 'shell', 'uitest', 'dumpLayout', '-p', remote], check=True, capture_output=True)
        subprocess.run([HDC, '-t', args.device, 'file', 'recv', remote, str(local)], check=True, capture_output=True)
        nodes = [json.loads(local.read_text())]
        while nodes:
            node = nodes.pop()
            attributes = node.get('attributes', {})
            if attributes.get('id') == identifier:
                return [int(value) for value in re.findall(r'-?\d+', attributes['bounds'])]
            nodes.extend(node.get('children', []))
        raise AssertionError('missing hit-test target ' + identifier)

    def input_event(*values):
        subprocess.run([HDC, '-t', args.device, 'shell', 'uitest', 'uiInput', *map(str, values)],
                       check=True, capture_output=True)

    def view_matches(expected):
        current = command('getViewDirection')
        return all(abs(current[key] - expected[key]) < 1e-6 for key in ['azimuth', 'altitude'])

    original_time = command('getSimulationTime')
    original_selection = command('getSelectedObjectInfo')
    original_pid = pid()
    try:
        command('setTimeRate', 0)
        for query, kind in [('Sirius', 'star'), ('Betelgeuse', 'star'),
                            ('catalog|Quasars|MS 23574-3520|selectOnly', 'quasar'),
                            ('catalog|Pulsars|PSR J0437-4715|selectOnly', 'pulsar'),
                            ('NGC 6256', 'globular-cluster'), ('NGC 188', 'open-cluster')]:
            previous = command('getObjectModelView', allow_error=True).get('renderedAt', 0)
            selected = command('searchObject', query)
            expect(query + ' selected', selected.get('found'))
            initial = frame(kind, previous, target=selected['englishName'])
            sample = {'query': query, 'initial': initial}
            frames.append(sample)
            command('setObjectModelView', 'open')
            expect(query + ' explicitly schematic', initial['schematic'] is True)
            expect(query + ' inline resolution', initial['renderSize'] == 320)
            command('setObjectModelView', '35|-50')
            rotated = frame(kind, initial['renderedAt'], target=selected['englishName'])
            sample['rotated'] = rotated
            expect(query + ' rotates in 3D', rotated['rotation'] != initial['rotation'])
            command('setObjectModelView', 'immersive')
            full = frame(kind, rotated['renderedAt'], True, selected['englishName'])
            sample['full'] = full
            expect(query + ' fullscreen resolution', full['renderSize'] == 640)
            screenshot(kind)
            command('setObjectModelView', 'close')
            closed = frame(kind, full['renderedAt'], target=selected['englishName'])
            sample['closed'] = closed
            expect(query + ' close retains rotation', closed['rotation'] == rotated['rotation'])
            expect(query + ' close retains target', closed['selectedEnglishName'] == initial['selectedEnglishName'])
        for target in ['M31', 'NGC 7006']:
            command('searchObject', target)
            command('setObjectDetailTab', '2')
            time.sleep(1)
            expect(target + ' keeps photograph instead of invented model', not command('getObjectModelView', allow_error=True).get('ok'))
        command('searchObject', 'Moon')
        moon = frame('textured-sphere')
        expect('Moon retains physical texture model', moon['schematic'] is False)
        expect('Moon retains ephemeris lighting', bool(moon.get('lighting', {}).get('sunDirectionBody')))
        if args.touch:
            left, top, right, bottom = hit_bounds('object-model-inline-stage')
            time.sleep(0.8)
            original_view = command('getViewDirection')
            input_event('swipe', (left + right) // 2 - 50, top + 40, (left + right) // 2 + 50, top + 40, 400)
            inline = frame('textured-sphere', moon['renderedAt'])
            frames.append({'inlineTouchBeforeView': original_view, 'inlineTouchAfterView': command('getViewDirection'),
                           'inlineTouchFrame': inline, 'inlineBounds': [left, top, right, bottom]})
            expect('inline model responds to real rightward touch', inline['rotation'] != moon['rotation'])
            expect('inline model touch does not move sky', view_matches(original_view))
            command('setObjectModelView', 'reset')
            moon = frame('textured-sphere', inline['renderedAt'])
        command('setObjectModelView', 'immersive')
        full = frame('textured-sphere', moon['renderedAt'], True)
        screenshot('moon')
        if args.touch:
            original_view = command('getViewDirection')
            left, top, right, bottom = hit_bounds('object-model-stage')
            center_x, center_y = (left + right) // 2, (top + bottom) // 2
            input_event('swipe', center_x, center_y + 60, center_x, center_y - 60, 600)
            rotated = frame('textured-sphere', full['renderedAt'], True)
            expect('real upward touch rotates the model upward', rotated['rotation'][5] < 0)
            expect('model swipe leaves sky view unchanged', view_matches(original_view))
            left, top, right, bottom = hit_bounds('object-model-close')
            input_event('click', (left + right) // 2, (top + bottom) // 2)
            closed = frame('textured-sphere', rotated['renderedAt'])
            expect('real close button retains Moon selection', closed['selectedEnglishName'] == 'Moon')
            expect('real close button leaves sky view unchanged', view_matches(original_view))
            changed_jd = command('getSimulationTime')['jd'] + 1
            command('setJD', changed_jd)
            updated = frame('textured-sphere', closed['renderedAt'], jd=changed_jd)
            expect('lighting still refreshes after real model touches', abs(updated['lighting']['jd'] - changed_jd) < 1e-5)
            expect('lighting refresh retains inspection rotation', updated['rotation'] == closed['rotation'])
        else:
            command('setObjectModelView', 'close')
            frame('textured-sphere', full['renderedAt'])
        command('clearSelection')
        time.sleep(1)
        expect('clearing selection removes model feedback', not command('getObjectModelView', allow_error=True).get('ok'))
        expect('app process did not restart', bool(original_pid) and original_pid == pid())
    finally:
        command('setObjectModelView', 'close', True)
        command('setJD', original_time['jd'])
        command('setTimeRate', original_time['timeRate'])
        if original_selection.get('englishName'):
            command('searchObject', original_selection['englishName'], True)
        args.output.write_text(json.dumps({'checks': checks, 'frames': frames}, ensure_ascii=False, indent=2))
    print(json.dumps({'passed': len(checks), 'report': str(args.output)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
