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
    checks = []

    def command(name, payload=''):
        result = subprocess.run(['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                                 '--command', name, '--payload', str(payload), '--json'],
                                capture_output=True, text=True, timeout=55)
        value = json.loads(result.stdout)
        missing_model = (name == 'getObjectModelView' and value.get('ok') is False
                         and value.get('error') == 'model is not ready'
                         and isinstance(value.get('detailScrollY'), (int, float)))
        if result.returncode and not missing_model:
            raise RuntimeError(result.stdout + result.stderr)
        return value

    def hdc(*values):
        return subprocess.check_output([HDC, '-t', args.device, *map(str, values)], text=True, timeout=50)

    def layout():
        remote = '/data/local/tmp/satellite-icon-layout.json'
        local = args.output.parent / 'satellite-icon-layout.json'
        hdc('shell', 'uitest', 'dumpLayout', '-p', remote)
        hdc('file', 'recv', remote, local)
        nodes = [json.loads(local.read_text())]
        bounds, texts = {}, []
        while nodes:
            node = nodes.pop()
            attributes = node.get('attributes', {})
            if attributes.get('id'):
                bounds[attributes['id']] = [int(value) for value in re.findall(r'-?\d+', attributes['bounds'])]
            if attributes.get('text'):
                texts.append(attributes['text'])
            nodes.extend(node.get('children', []))
        return bounds, texts

    def check(label, condition):
        checks.append({'label': label, 'passed': bool(condition)})
        assert condition, label

    original_time = command('getSimulationTime')
    original_selection = command('getSelectedObjectInfo')
    try:
        command('setTimeRate', 0)
        for target in ['ISS (ZARYA)', 'CSS (TIANHE)', 'STARLINK-36933']:
            selected = command('searchObject', target)
            check(target + ' selected', selected.get('found') and selected.get('englishName') == target)
            command('setObjectDetailTab', 2)
            time.sleep(1)
            for attempt in range(6):
                if command('getObjectModelView')['detailScrollY'] < 1:
                    break
                bounds, texts = layout()
                left, top, right, bottom = bounds['object-detail-content-scroll']
                hdc('shell', 'uitest', 'uiInput', 'swipe', left + 30, top + 20,
                    left + 30, bottom - 20, 500)
                time.sleep(0.7)
            bounds, texts = layout()
            check(target + ' reuses satellite icon', 'object-detail-satellite-icon' in bounds)
            check(target + ' no false 3D model', 'object-model-inline-stage' not in bounds)
            check(target + ' category disclaimer displayed', any('类别图标' in text for text in texts))
            remote = '/data/local/tmp/satellite-icon.jpeg'
            hdc('shell', 'snapshot_display', '-f', remote)
            hdc('file', 'recv', remote, args.output.parent / ('satellite-icon-' + target.split(' ')[0] + '.jpeg'))
            left, top, right, bottom = bounds['object-detail-satellite-icon']
            center_x, center_y = (left + right) // 2, (top + bottom) // 2
            before = command('getObjectModelView')['detailScrollY']
            sky = command('getViewDirection')
            hdc('shell', 'uitest', 'uiInput', 'swipe', center_x, center_y, center_x, center_y - 100, 500)
            time.sleep(0.7)
            after = command('getObjectModelView')['detailScrollY']
            check(target + ' swipe over icon scrolls details', after > before + 10)
            sky_after = command('getViewDirection')
            check(target + ' scrolling does not move sky', all(abs(sky[key] - sky_after[key]) < 1e-5
                                                              for key in ['altitude', 'azimuth']))
        command('searchObject', 'Moon')
        command('setObjectDetailTab', 2)
        time.sleep(2)
        bounds, texts = layout()
        check('Moon retains model, not artificial icon', 'object-model-inline-stage' in bounds
              and 'object-detail-satellite-icon' not in bounds)
    finally:
        args.output.write_text(json.dumps({'checks': checks}, ensure_ascii=False, indent=2) + '\n')
        command('setTimeRate', original_time['timeRate'])
        command('searchObject', original_selection.get('englishName') or 'Betelgeuse')
    print(json.dumps({'passed': len(checks), 'output': str(args.output)}))


if __name__ == '__main__':
    main()
