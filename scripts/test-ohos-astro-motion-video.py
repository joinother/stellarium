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

    def hdc(*values):
        return subprocess.check_output([HDC, '-t', args.device, *values], text=True)

    def command(name, payload=None):
        invocation = ['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                      '--command', name, '--json']
        if payload is not None:
            invocation += ['--payload', str(payload)]
        response = json.loads(subprocess.check_output(invocation, text=True, timeout=90))
        assert response.get('ok'), response
        return response

    def layout():
        remote = '/data/local/tmp/astro-motion-layout.json'
        local = args.output.with_suffix('.layout.json')
        hdc('shell', 'uitest', 'dumpLayout', '-p', remote)
        hdc('file', 'recv', remote, str(local))
        nodes = [json.loads(local.read_text())]
        bounds = {}
        while nodes:
            node = nodes.pop()
            attributes = node.get('attributes', {})
            if attributes.get('id', '').startswith('astro-filter-period-'):
                bounds[attributes['id']] = [int(value) for value in re.findall(r'-?\d+', attributes['bounds'])]
            nodes.extend(node.get('children', []))
        return bounds

    def recorder(filename=None):
        invocation = ['shell', 'aa', 'start', '-b', 'com.huawei.hmos.screenrecorder', '-a',
                      'com.huawei.hmos.screenrecorder.ServiceExtAbility']
        if filename:
            invocation += ['--ps', 'CustomizedFileName', filename]
        hdc(*invocation)

    original = command('getAstroPanelState')
    filename = args.output.stem + '.mp4'
    recording = False
    try:
        command('openUiPanel', 'astro')
        command('setAstroTab', 5)
        time.sleep(1)
        command('setAstroFilter', 'period|midnight')
        time.sleep(1)
        command('setAstroScroll', 380)
        time.sleep(5)
        before = layout()
        assert 'astro-filter-period-morning' in before
        recorder(filename)
        recording = True
        started = time.monotonic()
        time.sleep(4)
        marks = []
        for name, payload in [('setAstroFilter', 'period|morning'), ('setAstroFilter', 'period|midnight'),
                              ('setAstroTab', '0'), ('setAstroTab', '5')]:
            marks.append({'command': name, 'payload': payload, 'secondsAfterStartCommand': time.monotonic() - started})
            command(name, payload)
            time.sleep(2)
        recorder()
        recording = False
        time.sleep(2)
        query = hdc('shell', 'mediatool', 'query', filename, '-u')
        uri = re.search(r'"(file://[^\"]+)"', query)
        assert uri, query
        copied = hdc('shell', 'mediatool', 'recv', uri.group(1), '/data/local/tmp')
        remote = next(line.strip() for line in copied.splitlines() if line.startswith('/data/local/tmp/'))
        video = args.output.with_suffix('.mp4')
        hdc('file', 'recv', remote, str(video))
        command('setAstroScroll', 380)
        time.sleep(1)
        after = layout()
        assert before == after, {'before': before, 'after': after}
        args.output.write_text(json.dumps({'video': str(video), 'before': before, 'after': after,
                                          'marks': marks, 'stableBounds': True}, ensure_ascii=False, indent=2) + '\n')
        print(str(args.output))
    finally:
        if recording:
            recorder()
        command('setAstroFilter', 'period|' + original['period'])
        command('setAstroTab', original['tab'])


if __name__ == '__main__':
    main()
