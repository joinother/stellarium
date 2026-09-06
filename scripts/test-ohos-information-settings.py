#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
HDC = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--restart', action='store_true')
    args = parser.parse_args()

    def command(name, payload=None, allow_error=False):
        invocation = ['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                      '--command', name, '--json']
        if payload is not None:
            invocation.extend(['--payload', payload])
        result = subprocess.run(invocation, capture_output=True, text=True, timeout=45)
        response = json.loads(result.stdout)
        if not allow_error and response.get('ok') is not True:
            raise RuntimeError(str(response))
        return response

    initial = command('getInformationSettings')
    report = {'initial': initial, 'checks': [], 'restored': False}

    def expect(name, condition):
        report['checks'].append({'name': name, 'ok': bool(condition)})
        if not condition:
            raise AssertionError(name)

    try:
        for mask in [0, 33554431, 5]:
            response = command('setInformationSetting', f'mask|{mask}')
            expect(f'custom mask {mask}', response['infoMode'] == 'custom' and response['activeInfoMask'] == mask)
            command('setInformationSetting', 'mode|all')
            response = command('setInformationSetting', 'mode|custom')
            expect(f'restore custom mask {mask}', response['infoMode'] == 'custom' and response['activeInfoMask'] == mask)
        response = command('setInformationSetting', 'mask|1073741824', allow_error=True)
        expect('reject unsupported bits', response.get('ok') is not True)
        expect('invalid mask preserves choices', command('getInformationSettings')['activeInfoMask'] == 5)
        if args.restart:
            subprocess.run([HDC, '-t', args.device, 'shell', 'aa', 'force-stop', 'com.joinother.skyinstrument'], check=True)
            response = command('getInformationSettings')
            expect('restart retains mode and fields', response['infoMode'] == 'custom' and response['activeInfoMask'] == 5)
    finally:
        command('setInformationSetting', f"mask|{initial['customInfoMask']}")
        command('setInformationSetting', f"mode|{initial['infoMode']}")
        report['restored'] = command('getInformationSettings') == initial
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    expect('original settings restored', report['restored'])
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
