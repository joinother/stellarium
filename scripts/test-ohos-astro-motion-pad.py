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

    def command(name, payload=None, allow_error=False):
        invocation = ['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                      '--command', name, '--json']
        if payload is not None:
            invocation += ['--payload', str(payload)]
        result = subprocess.run(invocation, capture_output=True, text=True, timeout=90)
        response = json.loads(result.stdout)
        if not allow_error and not response.get('ok'):
            raise RuntimeError(response)
        return response

    def expect(name, condition):
        checks.append({'name': name, 'ok': bool(condition)})
        if not condition:
            raise AssertionError(name)

    def panel(tab=None, settled_filters=False):
        for attempt in range(40):
            state = command('getAstroPanelState', allow_error=True)
            if state.get('ok') and not state['transitioning'] and (tab is None or state['tab'] == tab) and (not settled_filters or not state.get('loading')):
                return state
            time.sleep(0.1)
        raise AssertionError('transition did not settle: ' + str(state))

    def pid():
        return subprocess.check_output([HDC, '-t', args.device, 'shell', 'pidof',
                                        'com.joinother.skyinstrument'], text=True).strip()

    def snapshot(name):
        remote = '/data/local/tmp/astro-' + name + '.jpeg'
        subprocess.run([HDC, '-t', args.device, 'shell', 'snapshot_display', '-f', remote], check=True, capture_output=True)
        subprocess.run([HDC, '-t', args.device, 'file', 'recv', remote,
                        str(args.output.parent / ('astro-' + name + '.jpeg'))], check=True, capture_output=True)

    initial = None
    original_pid = pid()
    try:
        command('openUiPanel', 'astro')
        time.sleep(1)
        initial = panel()
        for tab in [5, 2, 4, 9, 0, 1, 6, 3, 7, 8, 5]:
            command('setAstroTab', tab)
            state = panel(tab)
            samples.append(state)
            expect('tab ' + str(tab) + ' finishes with correct group', state['group'] == (1 if tab in [0, 1, 6] else 2 if tab in [3, 7, 8] else 0))
            revision = state['transitionId']
            command('setAstroTab', tab)
            expect('tab ' + str(tab) + ' is idempotent', panel(tab)['transitionId'] == revision)
            if tab in [0, 5, 8]:
                snapshot('tab-' + str(tab))
        for group, tab in [(1, 0), (2, 3), (0, 5)]:
            command('setAstroGroup', group)
            expect('group ' + str(group) + ' opens its first page', panel(tab)['group'] == group)
        panel(settled_filters=True)
        baseline = 0
        for attempt in range(20):
            command('setAstroScroll', 380)
            time.sleep(0.2)
            baseline = panel()['scrollY']
            if baseline > 0:
                break
        expect('semantic scroll reaches tonight filters', baseline > 0)
        for key, value in [('period', 'morning'), ('altitude', '20'), ('magnitude', '8'), ('direction', 'east')]:
            command('setAstroFilter', key + '|' + value)
            state = panel(settled_filters=True)
            samples.append(state)
            expect(key + ' changes in actual UI state', str(state[key]) == value)
            expect(key + ' does not jump the scroll', abs(state['scrollY'] - baseline) < 2)
        snapshot('filters')
        for name, payload in [('setAstroTab', '-1'), ('setAstroTab', '10'), ('setAstroGroup', '3'),
                              ('setAstroFilter', 'period|invalid'), ('setAstroFilter', 'altitude|-90'),
                              ('setAstroScroll', '-1')]:
            expect(name + ' rejects ' + payload, command(name, payload, True).get('ok') is False)
        command('closeUiPanel')
        command('openUiPanel', 'astro')
        time.sleep(0.6)
        expect('panel can reopen after navigation', panel()['tab'] == 5)
        expect('app process remains alive without restart', original_pid != '' and pid() == original_pid)
    finally:
        if initial is not None:
            command('openUiPanel', 'astro')
            time.sleep(0.5)
            for key in ['period', 'altitude', 'magnitude', 'direction']:
                command('setAstroFilter', key + '|' + str(initial[key]))
            command('setAstroTab', initial['tab'])
            panel(initial['tab'])
        args.output.write_text(json.dumps({'device': args.device, 'checks': checks, 'samples': samples}, ensure_ascii=False, indent=2) + '\n')
        print(json.dumps({'passed': sum(item['ok'] for item in checks), 'total': len(checks), 'output': str(args.output)}))


if __name__ == '__main__':
    main()
