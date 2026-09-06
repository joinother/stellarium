#!/usr/bin/env python3
import argparse
import json
import math
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


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
        completed = subprocess.run(invocation, capture_output=True, text=True, timeout=65)
        response = json.loads(completed.stdout)
        if not allow_error and not response.get('ok'):
            raise RuntimeError(response)
        return response

    def expect(name, condition):
        checks.append({'name': name, 'ok': bool(condition)})
        if not condition:
            raise AssertionError(name)

    def frame(target, after=0, reset=False):
        for attempt in range(35):
            result = command('getObjectModelView', allow_error=True)
            if (result.get('selectedEnglishName') == target and result.get('renderedAt', 0) > after
                    and result.get('renderSize') == 320
                    and (not reset or result.get('rotation') == [1, 0, 0, 0, 1, 0, 0, 0, 1])):
                return result
            time.sleep(0.2)
        raise RuntimeError('model did not produce a fresh frame: ' + str(result))

    def dot(left, right):
        return sum(first * second for first, second in zip(left, right))

    original = command('getSimulationTime')
    selection = command('getSelectedObjectInfo')
    started = time.monotonic()
    try:
        command('setTimeRate', 0)
        frozen = command('getSimulationTime')['jd']
        for target in ['Moon', 'Venus', 'Saturn', 'Uranus', 'Sun']:
            previous = command('getObjectModelView', allow_error=True).get('renderedAt', 0)
            command('searchObject', target)
            command('setObjectModelView', 'open')
            command('setObjectModelView', 'reset')
            native = command('getObjectDetailModel')
            lighting = native['lighting']
            matrix = lighting['viewToBody']
            columns = [matrix[column::3] for column in range(3)]
            expect(target + ' physical view is orthonormal', all(
                abs(dot(columns[row], columns[column]) - (1 if row == column else 0)) < 1e-9
                for row in range(3) for column in range(3)))
            expect(target + ' solar direction is normalized', abs(dot(lighting['sunDirectionBody'], lighting['sunDirectionBody']) - 1) < 1e-9)
            expect(target + ' phase matches view/solar geometry', abs(
                (1 + dot(columns[2], lighting['sunDirectionBody'])) / 2 - lighting['illuminatedFraction']) < 1e-9)
            rendered = frame(target, previous, reset=True)
            expect(target + ' native lighting reaches rendered UI', rendered.get('lighting', {}).get('sunDirectionBody') == lighting['sunDirectionBody'])
            expect(target + ' static render resolution retained', rendered['renderSize'] == 320)
            samples.append({'target': target, 'native': native, 'frame': rendered})

        command('searchObject', 'Moon')
        command('setObjectModelView', 'open')
        command('setObjectModelView', 'reset')
        initial = frame('Moon', reset=True)
        command('setObjectModelView', '0|-50')
        rotated = frame('Moon', initial['renderedAt'])
        samples.append({'rotationCheckInitial': initial, 'rotationCheckResult': rotated})
        expect('upward drag rotates toward negative screen Y', rotated['rotation'][5] < 0 and rotated['rotation'][7] > 0)
        expect('rotation keeps sun fixed to body, not screen', initial['lighting']['sunDirectionBody'] == rotated['lighting']['sunDirectionBody'])
        initial_screen_sun = [dot(initial['viewToBody'][column::3], initial['lighting']['sunDirectionBody']) for column in range(3)]
        rotated_screen_sun = [dot(rotated['viewToBody'][column::3], rotated['lighting']['sunDirectionBody']) for column in range(3)]
        expect('screen terminator moves during rotation', math.dist(initial_screen_sun, rotated_screen_sun) > 0.01)
        command('setObjectModelView', 'reset')
        reset = frame('Moon', rotated['renderedAt'], reset=True)
        expect('reset restores observer view', reset['rotation'] == [1, 0, 0, 0, 1, 0, 0, 0, 1])
        command('setObjectModelView', '25|20')
        inspecting = frame('Moon', reset['renderedAt'])
        command('setJD', frozen + 10)
        advanced = frame('Moon', inspecting['renderedAt'])
        expect('time updates light without resetting manual rotation', advanced['rotation'] == inspecting['rotation'])
        expect('ephemeris time is refreshed in rendered model', abs(advanced['lighting']['jd'] - frozen - 10) < 1e-5)
        expect('changed date changes body-fixed light', advanced['lighting']['sunDirectionBody'] != inspecting['lighting']['sunDirectionBody'])
        expect('model control rejects malformed input', not command('setObjectModelView', 'nan|2', True)['ok'])
        samples.extend([{'initial': initial, 'rotated': rotated, 'reset': reset, 'advanced': advanced}])
        command('clearSelection')
        for attempt in range(20):
            empty = command('getObjectModelView', allow_error=True)
            if not empty.get('ok'):
                break
            time.sleep(0.1)
        expect('clearing selection invalidates the old rendered model probe', not empty.get('ok'))
    finally:
        command('setTimeRate', 0)
        command('setJD', original['jd'] + (time.monotonic() - started) * original['timeRate'])
        command('setTimeRate', original['timeRate'])
        if selection.get('found'):
            command('searchObject', selection.get('englishName') or selection['name'])
        else:
            command('clearSelection')
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({'device': args.device, 'checks': checks, 'samples': samples}, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'passed': len(checks), 'report': str(args.output)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
