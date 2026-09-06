#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import re
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
    captures = []

    def command(name, payload=None):
        invocation = ['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                      '--command', name, '--json']
        if payload is not None:
            invocation += ['--payload', str(payload)]
        result = subprocess.run(invocation, capture_output=True, text=True, timeout=60)
        response = json.loads(result.stdout)
        if response.get('ok') is not True:
            raise RuntimeError(response)
        return response

    def device(*parts):
        return subprocess.run([HDC, '-t', args.device, *parts], capture_output=True, text=True,
                              check=True, timeout=30)

    def expect(name, condition):
        checks.append({'name': name, 'ok': bool(condition)})
        if not condition:
            raise AssertionError(name)

    with tempfile.TemporaryDirectory(prefix='stellarium-live-') as folder:
        def snapshot(label):
            remote = '/data/local/tmp/stellarium-detail-live.json'
            local = str(Path(folder) / 'layout.json')
            device('shell', 'uitest', 'dumpLayout', '-p', remote)
            device('file', 'recv', remote, local)
            entries = []

            def visit(node):
                attrs = node.get('attributes', {})
                if attrs.get('text'):
                    entries.append({'text': attrs['text'], 'bounds': attrs['bounds']})
                for child in node.get('children', []):
                    visit(child)

            visit(json.loads(Path(local).read_text()))
            captures.append({'label': label, 'entries': entries})
            return entries

        def value(entries, label, last=False):
            indices = list(range(len(entries) - 1))
            for index in reversed(indices) if last else indices:
                entry = entries[index]
                if entry['text'] == label:
                    return entries[index + 1]['text']
            raise AssertionError('missing row: ' + label)

        def tab(label):
            entries = snapshot('locate ' + label)
            entry = next(entry for entry in entries if entry['text'] == label)
            left, top, right, bottom = map(int, re.findall(r'\d+', entry['bounds']))
            device('shell', 'uitest', 'uiInput', 'click', str((left + right) // 2), str((top + bottom) // 2))
            time.sleep(0.5)
            for _ in range(2):
                device('shell', 'uitest', 'uiInput', 'swipe', str((left + right) // 2),
                       str(bottom + 110), str((left + right) // 2), str(bottom + 410), '600')
            time.sleep(0.5)

        original = command('getSimulationTime')
        original_info = command('getInformationSettings')
        original_selection = command('getSelectedObjectInfo')
        started = time.monotonic()
        try:
            command('setTimeRate', 0)
            command('searchObject', 'Moon')
            command('closeUiPanel')
            time.sleep(2)
            tab('坐标')
            command('setTimeRate', 0.001)
            first = snapshot('moon coordinates first')
            time.sleep(3)
            second = snapshot('moon coordinates second')
            expect('coordinate rows update without another selection or info command',
                   value(first, '地平坐标') != value(second, '地平坐标'))
            expect('equatorial coordinates also update', value(first, '赤道坐标') != value(second, '赤道坐标'))
            command('setTimeRate', 0)
            time.sleep(1)
            first = snapshot('paused coordinates first')
            time.sleep(2)
            second = snapshot('paused coordinates second')
            expect('paused simulation leaves coordinates unchanged',
                   value(first, '地平坐标') == value(second, '地平坐标'))
            full = command('getSelectedObjectInfo', 'details')
            expect('full response retains static and tagged dynamic fields',
                   any(field.get('live') for field in full['detailFields'])
                   and any(not field.get('live') for field in full['detailFields']))
            command('setTimeRate', 0.001)
            first = command('getSelectedObjectInfo')
            time.sleep(3)
            second = command('getSelectedObjectInfo')
            expect('heartbeat does not resend the full detail collection', 'detailFields' not in second)
            expect('heartbeat contains only tagged live supplemental fields',
                   len(second['liveDetailFields']) > 0 and all(field['live'] for field in second['liveDetailFields']))
            first_values = {field['key']: field['value'] for field in first['liveDetailFields']}
            expect('lunar and surface supplements change with simulation time',
                   any(first_values.get(field['key']) != field['value'] for field in second['liveDetailFields']))
            command('setTimeRate', 0)
            tab('资料')
            entries = snapshot('data tab bounds')
            bounds = next(entry['bounds'] for entry in entries if entry['text'] == '完整资料')
            left, top, right, bottom = map(int, re.findall(r'\d+', bounds))
            scroll_edge = left - 10
            for attempt in range(4):
                entries = snapshot('locate data tile ' + str(attempt))
                if (sum(entry['text'] == '实时高度 / 方位' for entry in entries) >= 2
                        and re.search(r'高度 .*方位', value(entries, '实时高度 / 方位', last=True))):
                    break
                device('shell', 'uitest', 'uiInput', 'swipe', str(scroll_edge), str(bottom + 340), str(scroll_edge), str(bottom + 20), '600')
            command('setTimeRate', 0.001)
            first = snapshot('data tab first')
            time.sleep(3)
            second = snapshot('data tab second')
            expect('data tab altitude tile updates as well',
                   sum(entry['text'] == '实时高度 / 方位' for entry in first) >= 2
                   and value(first, '实时高度 / 方位', last=True) != value(second, '实时高度 / 方位', last=True))
            command('setTimeRate', 1 / 86400)
            command('searchObject', 'STARLETTE')
            time.sleep(2)
            tab('坐标')
            first = snapshot('satellite without requesting passes first')
            time.sleep(3)
            second = snapshot('satellite without requesting passes second')
            expect('satellite coordinates update without computing pass predictions',
                   value(first, '地平坐标') != value(second, '地平坐标'))
            response = command('getSelectedObjectInfo')
            expect('satellite live range and rate are present',
                   {'range', 'rangeRate'}.issubset({field['key'] for field in response['liveDetailFields']}))
            expect('satellite heartbeat contains no pass calculation or TLE records',
                   'satellitePasses' not in response and not any(field['key'].startswith('tle') for field in response['liveDetailFields']))
            tab('资料')
            entries = snapshot('satellite data bounds')
            bounds = next(entry['bounds'] for entry in entries if entry['text'] == '完整资料')
            left, top, right, bottom = map(int, re.findall(r'\d+', bounds))
            for attempt in range(16):
                entries = snapshot('locate live satellite range ' + str(attempt))
                if (any(entry['text'] == '斜距' for entry in entries)
                        and re.fullmatch(r'[\d.]+ km', value(entries, '斜距'))):
                    break
                device('shell', 'uitest', 'uiInput', 'swipe', str(left - 10), str(bottom + 340),
                       str(left - 10), str(bottom + 20), '600')
            first = snapshot('supplemental satellite range first')
            time.sleep(3)
            second = snapshot('supplemental satellite range second')
            expect('structured supplemental range row updates without rebuilding the page',
                   value(first, '斜距') != value(second, '斜距'))
            device('shell', 'snapshot_display', '-f', '/data/local/tmp/stellarium-detail-live.jpeg')
            device('file', 'recv', '/data/local/tmp/stellarium-detail-live.jpeg', '/tmp/stellarium-detail-live.jpeg')
        finally:
            command('setTimeRate', 0)
            command('setJD', original['jd'] + (time.monotonic() - started) * original['timeRate'])
            command('setTimeRate', original['timeRate'])
            if original_selection.get('found'):
                command('searchObject', original_selection.get('englishName') or original_selection['name'])
            else:
                command('clearSelection')
            args.output.write_text(json.dumps({'checks': checks, 'captures': captures,
                'restoredRate': command('getSimulationTime')['timeRate'],
                'informationModeUnchanged': command('getInformationSettings')['infoMode'] == original_info['infoMode']},
                ensure_ascii=False, indent=2) + '\n')
        print(json.dumps({'passed': len(checks), 'report': str(args.output)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
