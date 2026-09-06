#!/usr/bin/env python3
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
    parser.add_argument('--restart', action='store_true')
    args = parser.parse_args()

    def command(name, payload=None, allow_error=False):
        invocation = ['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                      '--command', name, '--json']
        if payload is not None:
            invocation.extend(['--payload', str(payload)])
        result = subprocess.run(invocation, capture_output=True, text=True, timeout=60)
        response = json.loads(result.stdout)
        if not allow_error and response.get('ok') is not True:
            raise RuntimeError(str(response))
        return response

    initial = command('getTimeSettings')
    simulation = command('getSimulationTime')
    report = {'initial': initial, 'checks': [], 'restored': False}

    def expect(name, condition):
        report['checks'].append({'name': name, 'ok': bool(condition)})
        if not condition:
            raise AssertionError(name)

    def restart():
        subprocess.run([HDC, '-t', args.device, 'shell', 'aa', 'force-stop',
                        'com.joinother.skyinstrument'], check=True, capture_output=True)
        return command('getTimeSettings')

    saved_keys = ['dateFormat', 'timeFormat', 'startupTimeMode', 'startupTimeStop',
                  'todayTime', 'presetLocalTime', 'deltaTAlgorithm', 'deltaTCustom']
    try:
        command('setTimeRate', '0')
        command('setDate', '2026-09-06T05:14:25')
        frozen = command('getSimulationTime')['jd']
        for date_format in ['system_default', 'yyyymmdd', 'ddmmyyyy', 'mmddyyyy',
                            'wwyyyymmdd', 'wwddmmyyyy', 'wwmmddyyyy']:
            command('setDateFormat', date_format)
            for clock_format in ['system_default', '24h', '12h']:
                settings = command('setTimeFormat', clock_format)
                clock = command('getSimulationTime')
                state = command('getState')
                date_text, clock_text = state['timeText'].split('T')
                year, month, day = date_text.split('-')
                expected_date = {'yyyymmdd': date_text, 'ddmmyyyy': f'{day}-{month}-{year}',
                                 'mmddyyyy': f'{month}-{day}-{year}'}.get(date_format.removeprefix('ww'))
                hour = int(clock_text[:2])
                expected_clock = (f'{hour % 12 or 12:02d}' + clock_text[2:] + (' AM' if hour < 12 else ' PM')
                                  if clock_format == '12h' else clock_text)
                expect(f'format {date_format}/{clock_format}',
                       settings['dateFormat'] == date_format and settings['timeFormat'] == clock_format
                       and settings['formattedTime'] == clock['formattedTime'] == state['formattedTime']
                       and (expected_date is None or expected_date in clock['formattedTime'])
                       and (clock_format == 'system_default' or clock['formattedTime'].endswith(expected_clock))
                       and abs(clock['jd'] - frozen) < 1e-8)
        for name, value in [('setDateFormat', 'invalid'), ('setTimeFormat', '25h'),
                            ('setTimeSetting', 'todayTime|25:30'),
                            ('setTimeSetting', 'startupStop|maybe'),
                            ('setTimeSetting', 'startupMode|wrong'),
                            ('setTimeSetting', 'presetLocal|2026-02-30T10:00:00'),
                            ('setTimeSetting', 'deltaCustom|1820,-26,nan,0,32'),
                            ('setTimeSetting', 'deltaT|Unknown')]:
            before = command('getTimeSettings')
            response = command(name, value, allow_error=True)
            after = command('getTimeSettings')
            expect(f'reject {value} without changing settings', response.get('ok') is not True
                   and all(before[key] == after[key] for key in saved_keys))
        response = command('setTimeSetting', 'todayTime|22:30')
        expect('normalize HH:mm input', response['todayTime'] == '22:30:00')
        command('setTimeSetting', 'startupStop|1')
        response = command('setTimeSetting', 'presetCurrent|1')
        local = command('getState')['timeText']
        expect('capture observation-local preset and select mode',
               response['presetLocalTime'] == local and response['startupTimeMode'] == 'preset')
        expect('saving startup settings does not jump the sky',
               abs(command('getSimulationTime')['jd'] - frozen) < 1e-8)
        command('setJD', frozen - 5)
        command('setTimeSetting', 'applyStartup|1')
        clock = command('getSimulationTime')
        expect('apply preset without timezone shift', abs(clock['jd'] - frozen) < 1e-7 and clock['timeRate'] == 0)
        if args.restart:
            response = restart()
            clock = command('getSimulationTime')
            expect('restart retains formats, preset, and pause', response['dateFormat'] == 'wwmmddyyyy'
                   and response['timeFormat'] == '12h' and response['startupTimeMode'] == 'preset'
                   and abs(clock['jd'] - frozen) < 1e-7 and clock['timeRate'] == 0)
        command('setTimeSetting', 'presetLocal|2027-04-05T21:30:45')
        command('setTimeSetting', 'applyStartup|1')
        expect('editable preset applied', command('getState')['timeText'] == '2027-04-05T21:30:45')
        command('setTimeSetting', 'startupMode|today')
        command('setTimeSetting', 'applyStartup|1')
        expect('today uses saved clock time', command('getState')['timeText'].endswith('T22:30:00'))
        command('setTimeSetting', 'deltaT|WithoutCorrection')
        expect('DeltaT algorithm changes the computed value', command('getDeltaT')['deltaT'] == 0)
        command('setTimeSetting', 'deltaCustom|2000,-25,-10,2,30')
        response = command('setTimeSetting', 'deltaT|Custom')
        expect('custom DeltaT editable', response['deltaTCustom'] == '2000,-25,-10,2,30'
               and response['deltaTAlgorithm'] == 'Custom' and len(response['deltaTAlgorithms']) > 8)
        command('setTimeSetting', 'deltaCustom|2000,-24,100,2,30')
        expect('editing active custom parameters refreshes the description',
               '-24.0000' in command('getTimeSettings')['deltaTDescription'])
        command('setTimeSetting', 'deltaCustom|2000,-25,-10,2,30')
        if args.restart:
            response = restart()
            expect('restart retains today and custom DeltaT',
                   response['startupTimeMode'] == 'today' and response['deltaTCustom'] == '2000,-25,-10,2,30'
                   and command('getState')['timeText'].endswith('T22:30:00'))
        command('setTimeSetting', 'startupMode|actual')
        command('setTimeSetting', 'startupStop|0')
        command('setTimeSetting', 'applyStartup|1')
        clock = command('getSimulationTime')
        expect('actual time resumes at real-time speed', abs(clock['timeRate'] * 86400 - 1) < 1e-7
               and abs((clock['jd'] - 2440587.5) * 86400 - time.time()) < 20)
    finally:
        command('setDateFormat', initial['dateFormat'])
        command('setTimeFormat', initial['timeFormat'])
        for key, field in [('todayTime', 'todayTime'), ('presetLocal', 'presetLocalTime'),
                           ('deltaCustom', 'deltaTCustom'), ('deltaT', 'deltaTAlgorithm'),
                           ('startupMode', 'startupTimeMode')]:
            command('setTimeSetting', f'{key}|{initial[field]}')
        command('setTimeSetting', f"startupStop|{int(initial['startupTimeStop'])}")
        command('setJD', simulation['jd'])
        command('setTimeRate', simulation['timeRate'])
        restored = command('getTimeSettings')
        report['restored'] = all(restored[key] == initial[key] for key in saved_keys)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    expect('original settings restored', report['restored'])
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'checks': len(report['checks']), 'passed': all(item['ok'] for item in report['checks']),
                      'restored': report['restored']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
