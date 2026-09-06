import argparse
import json
from pathlib import Path
import re
import subprocess
import time


ROOT = Path(__file__).resolve().parents[1]
HDC = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = {'checks': [], 'samples': []}

    def hdc(*values):
        return subprocess.check_output([HDC, '-t', args.device, *map(str, values)], text=True, timeout=50)

    def command(name, payload=None):
        invocation = ['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                      '--command', name, '--json']
        if payload is not None:
            invocation += ['--payload', str(payload)]
        result = subprocess.run(invocation, capture_output=True, text=True, timeout=60, check=True)
        return json.loads(result.stdout)

    def expect(label, condition):
        report['checks'].append({'label': label, 'passed': bool(condition)})
        assert condition, label

    def frame(target, immersive=False, after=0):
        for attempt in range(40):
            result = command('getObjectModelView')
            if (result.get('ok') and result.get('selectedEnglishName') == target
                    and result.get('immersive') == immersive and result.get('renderedAt', 0) >= after
                    and result.get('renderSize') == (640 if immersive else 320)):
                return result
            time.sleep(0.2)
        raise AssertionError('no stable frame: ' + str(result))

    def layout():
        remote = '/data/local/tmp/model-scroll-layout.json'
        local = args.output.parent / 'model-scroll-layout.json'
        hdc('shell', 'uitest', 'dumpLayout', '-p', remote)
        hdc('file', 'recv', remote, local)
        nodes = [json.loads(local.read_text())]
        bounds = {}
        while nodes:
            node = nodes.pop()
            attributes = node.get('attributes', {})
            if attributes.get('id'):
                bounds[attributes['id']] = [int(value) for value in re.findall(r'-?\d+', attributes['bounds'])]
            nodes.extend(node.get('children', []))
        return bounds

    def swipe(start_x, start_y, end_x, end_y):
        hdc('shell', 'uitest', 'uiInput', 'swipe', start_x, start_y, end_x, end_y, 500)
        time.sleep(0.7)

    def model_center():
        bounds = layout()
        left, top, right, bottom = bounds['object-model-inline-stage']
        scroll = bounds['object-detail-content-scroll']
        top, bottom = max(top, scroll[1]), min(bottom, scroll[3])
        assert bottom - top > 50, 'model needs to be visible for physical gesture'
        return (left + right) // 2, (top + bottom) // 2

    def top_of_details():
        for attempt in range(6):
            left, top, right, bottom = layout()['object-detail-content-scroll']
            swipe(left + 30, top + 20, left + 30, bottom - 20)
            if command('getObjectModelView').get('detailScrollY', 0) < 1:
                return
        raise AssertionError('cannot return to top of details')

    def screenshot(name):
        remote = '/data/local/tmp/model-scroll-' + name + '.jpeg'
        hdc('shell', 'snapshot_display', '-f', remote)
        hdc('file', 'recv', remote, args.output.parent / ('model-scroll-' + name + '.jpeg'))

    def same_sky(before):
        after = command('getViewDirection')
        return all(abs(after[key] - before[key]) < 1e-5 for key in ['azimuth', 'altitude'])

    original_time = command('getSimulationTime')
    original_selection = command('getSelectedObjectInfo')
    original_pid = hdc('shell', 'pidof', 'com.joinother.skyinstrument').strip()
    try:
        command('setTimeRate', 0)
        for query in ['Moon', 'Betelgeuse']:
            selected = command('searchObject', query)
            expect(query + ' selected', selected.get('found'))
            target = selected['englishName']
            command('setObjectModelView', 'open')
            frame(target)
            top_of_details()
            time.sleep(0.8)
            before = frame(target)
            sky = command('getViewDirection')
            center_x, center_y = model_center()
            swipe(center_x - 65, center_y, center_x + 65, center_y)
            horizontal = frame(target, after=before['renderedAt'] + 1)
            expect(query + ' horizontal drag rotates', horizontal['rotation'] != before['rotation'])
            expect(query + ' horizontal drag does not scroll', abs(horizontal['detailScrollY'] - before['detailScrollY']) < 1)
            expect(query + ' horizontal drag does not move sky', same_sky(sky))
            center_x, center_y = model_center()
            swipe(center_x, center_y + 45, center_x + 8, center_y - 95)
            vertical = frame(target, after=horizontal['renderedAt'] + 1)
            report['samples'].append({'target': query, 'horizontal': horizontal, 'vertical': vertical})
            expect(query + ' vertical drag over model rotates', vertical['rotation'] != horizontal['rotation'])
            expect(query + ' vertical drag does not scroll', abs(vertical['detailScrollY'] - horizontal['detailScrollY']) < 1)
            expect(query + ' vertical drag leaves sky unchanged', same_sky(sky))
            screenshot(query + '-compact')
            for side in ['left', 'right']:
                top_of_details()
                before_gutter = frame(target)
                bounds = layout()
                model = bounds['object-model-inline-stage']
                scroll = bounds['object-detail-content-scroll']
                gutter_x = (scroll[0] + model[0]) // 2 if side == 'left' else (scroll[2] + model[2]) // 2
                center_y = (max(model[1], scroll[1]) + min(model[3], scroll[3])) // 2
                swipe(gutter_x, center_y + 45, gutter_x, center_y - 95)
                scrolled = frame(target)
                report['samples'].append({'target': query, 'gutter': side, 'before': before_gutter,
                                          'after': scrolled, 'modelBounds': model, 'scrollBounds': scroll,
                                          'touchX': gutter_x, 'touchY': center_y})
                expect(query + ' ' + side + ' gutter scrolls', scrolled['detailScrollY'] > before_gutter['detailScrollY'] + 10)
                expect(query + ' ' + side + ' gutter does not rotate', scrolled['rotation'] == before_gutter['rotation'])
                expect(query + ' ' + side + ' gutter does not move sky', same_sky(sky))
            screenshot(query + '-scrolled')
            top_of_details()
            expect(query + ' can scroll back up', command('getObjectModelView')['detailScrollY'] < 1)
            left, top, right, bottom = layout()['object-model-expand']
            hdc('shell', 'uitest', 'uiInput', 'click', (left + right) // 2, (top + bottom) // 2)
            full = frame(target, True)
            left, top, right, bottom = layout()['object-model-stage']
            swipe((left + right) // 2, (top + bottom) // 2 + 60, (left + right) // 2, (top + bottom) // 2 - 60)
            rotated = frame(target, True, full['renderedAt'] + 1)
            expect(query + ' full screen retains vertical rotation', rotated['rotation'] != full['rotation'])
            expect(query + ' full screen does not scroll underlying details', abs(rotated['detailScrollY'] - full['detailScrollY']) < 1)
            left, top, right, bottom = layout()['object-model-close']
            hdc('shell', 'uitest', 'uiInput', 'click', (left + right) // 2, (top + bottom) // 2)
            closed = frame(target, False, rotated['renderedAt'] + 1)
            expect(query + ' real close retains rotation', closed['rotation'] == rotated['rotation'])
            expect(query + ' real close leaves sky unchanged', same_sky(sky))
            bounds = layout()
            model = bounds['object-model-inline-stage']
            scroll = bounds['object-detail-content-scroll']
            gutter_x = (scroll[0] + model[0]) // 2
            center_y = (max(model[1], scroll[1]) + min(model[3], scroll[3])) // 2
            swipe(gutter_x, center_y + 35, gutter_x, center_y - 80)
            resumed = frame(target)
            expect(query + ' scroll still works after leaving full screen', resumed['detailScrollY'] > closed['detailScrollY'] + 10)
            report['samples'].append({'target': query, 'before': before, 'horizontal': horizontal,
                                      'vertical': vertical, 'closed': closed, 'resumed': resumed})
        expect('process stayed alive', hdc('shell', 'pidof', 'com.joinother.skyinstrument').strip() == original_pid)
    finally:
        command('setObjectModelView', 'close')
        command('setTimeRate', original_time['timeRate'])
        command('searchObject', original_selection.get('englishName') or 'Betelgeuse')
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'passed': len(report['checks']), 'output': str(args.output)}))


if __name__ == '__main__':
    main()
