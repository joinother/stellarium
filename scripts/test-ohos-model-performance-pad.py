import argparse
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = {'checks': [], 'frames': []}

    def command(name, payload=None, allow_error=False):
        invocation = ['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                      '--command', name, '--json']
        if payload is not None:
            invocation += ['--payload', str(payload)]
        completed = subprocess.run(invocation, capture_output=True, text=True, timeout=60)
        result = json.loads(completed.stdout)
        if not allow_error and not result.get('ok'):
            raise RuntimeError(result)
        return result

    def expect(label, condition):
        report['checks'].append({'label': label, 'passed': bool(condition)})
        assert condition, label

    def frame(target, immersive=False, after=0):
        for attempt in range(40):
            result = command('getObjectModelView', allow_error=True)
            if (result.get('ok') and result.get('selectedEnglishName') == target
                    and result.get('renderedAt', 0) > after and result.get('immersive') == immersive
                    and result.get('renderSize') == (640 if immersive else 320)):
                return result
            time.sleep(0.15)
        raise AssertionError('no completed frame: ' + str(result))

    original_time = command('getSimulationTime')
    original_selection = command('getSelectedObjectInfo')
    try:
        command('setTimeRate', 0)
        for query in ['Moon', 'Saturn', 'Jupiter']:
            selected = command('searchObject', query)
            expect(query + ' selected', selected.get('found'))
            target = selected['englishName']
            command('setObjectModelView', 'open')
            previous = frame(target)
            expect(query + ' keeps physical lighting', bool(previous.get('lighting', {}).get('sunDirectionBody')))
            command('setObjectModelView', 'immersive')
            previous = frame(target, True, previous['renderedAt'])
            for step in range(4):
                command('setObjectModelView', '18|-13')
                current = frame(target, True, previous['renderedAt'])
                report['frames'].append(current)
                expect(query + ' worker frame ' + str(step), current.get('renderer') == 'worker')
                expect(query + ' rotation ' + str(step), current['rotation'] != previous['rotation'])
                expect(query + ' UI runs during calculation ' + str(step),
                       current['computeMs'] < 80 or current.get('uiPulseCount', 0) > 0)
                previous = current
            command('setObjectModelView', 'close')
            closed = frame(target, False, previous['renderedAt'])
            expect(query + ' close preserves pose', closed['rotation'] == previous['rotation'])
        for query in ['Moon', 'Saturn', 'Betelgeuse', 'Jupiter']:
            command('searchObject', query)
        command('setObjectModelView', 'open')
        expect('latest target wins after switching models', frame('Jupiter')['selectedEnglishName'] == 'Jupiter')
    finally:
        command('setObjectModelView', 'close', allow_error=True)
        command('setTimeRate', original_time['timeRate'])
        command('searchObject', original_selection.get('englishName') or 'Betelgeuse')
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'passed': len(report['checks']), 'frames': len(report['frames']), 'output': str(args.output)}))


if __name__ == '__main__':
    main()
