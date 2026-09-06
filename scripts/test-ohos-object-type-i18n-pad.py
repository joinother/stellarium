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
    report = {'checks': [], 'samples': []}

    def command(name, payload=None):
        invocation = ['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                      '--command', name, '--json']
        if payload is not None:
            invocation.extend(['--payload', str(payload)])
        response = subprocess.run(invocation, capture_output=True, text=True, timeout=50, check=True)
        data = json.loads(response.stdout)
        assert data.get('ok') is True, (name, data)
        return data

    def expect(label, condition):
        report['checks'].append({'label': label, 'passed': bool(condition)})
        assert condition, label

    original_language = command('getAppState')['language']
    original_selection = command('getSelectedObjectInfo')
    try:
        for language, expected in [('zh_CN', '脉动变星'), ('en', 'pulsating variable star'),
                                   ('zh_HK', '脈動變星'), ('zh_TW', '脈動變星'), ('zh_CN', '脉动变星')]:
            command('setLanguage', language)
            selected = command('searchObject', 'Betelgeuse')
            detailed = command('getSelectedObjectInfo')
            info = command('getObjectInfo')['info']
            report['samples'].append({'language': language, 'target': 'Betelgeuse',
                                      'type': detailed['type'], 'rawType': detailed['objectType']})
            expect(language + ' search localized', expected in selected['type'])
            expect(language + ' live detail localized', expected in detailed['type'])
            expect(language + ' full info localized', expected in info['type'])
            expect(language + ' raw classification stable', detailed['objectType'] == 'double star, pulsating variable star')
            if language == 'zh_CN':
                expect(language + ' constellation localized', detailed['constellation'] == '猎户座')
        for target, expected in [('Algol', '食双星系统'), ('Mira', '脉动变星'), ('Sirius', '双星'),
                                 ('Sun', '恒星'), ('M31', '星系'), ('M42', '电离氢区'),
                                 ('catalog|Quasars|MS 23574-3520|selectOnly', '类星体'),
                                 ('catalog|Pulsars|PSR J0437-4715|selectOnly', '脉冲星')]:
            selected = command('searchObject', target)
            report['samples'].append({'language': 'zh_CN', 'target': target, 'type': selected.get('type')})
            expect(target + ' found', selected.get('found') is True)
            expect(target + ' localized', expected in selected.get('type', ''))
        stars = command('getNavStars')
        expect('navigation stars remain off', stars.get('enabled') is False and stars.get('enableAtStartup') is False)
    finally:
        command('setLanguage', original_language)
        command('searchObject', original_selection.get('englishName') or 'Betelgeuse')
        command('setObjectDetailTab', '0')
        time.sleep(0.5)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'passed': len(report['checks']), 'output': str(args.output)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
