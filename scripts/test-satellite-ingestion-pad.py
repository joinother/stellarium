import argparse
import hashlib
import http.server
import importlib.util
import json
from pathlib import Path
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ingestion', ROOT / 'scripts/test-satellite-ingestion.py')
ingestion = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ingestion)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--bundle', required=True)
    parser.add_argument('--hdc', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    checks = []

    def hdc(*parts):
        result = subprocess.run([args.hdc, '-t', args.device, *parts], capture_output=True, text=True, timeout=90)
        if result.returncode != 0 or '[Fail]' in result.stdout or 'Permission denied' in result.stdout:
            raise RuntimeError(result.stdout + result.stderr)
        return result.stdout

    def command(name, payload=None, reject=False):
        invocation = ['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                      '--bundle', args.bundle, '--hdc', args.hdc, '--command', name, '--json']
        if payload is not None:
            invocation += ['--payload', payload if isinstance(payload, str) else json.dumps(payload)]
        result = subprocess.run(invocation, capture_output=True, text=True, timeout=90)
        response = json.loads(result.stdout or result.stderr)
        if not reject and not response.get('ok'):
            raise AssertionError((name, response))
        return response

    def expect(name, condition):
        checks.append({'name': name, 'ok': bool(condition)})
        (args.output / 'checks.json').write_text(json.dumps(checks, ensure_ascii=False, indent=2))
        if not condition:
            raise AssertionError(name)
        print('PASS', name, flush=True)

    base = f'/data/app/el2/100/base/{args.bundle}/files/stellarium_userdir'
    catalog = base + '/modules/Satellites/satellites.json'
    sandbox = '/data/storage/el2/base/files/stellarium_userdir'
    device_fixture = sandbox
    source_settings = command('getSatelliteSources')
    (args.output / 'original-sources.json').write_text(json.dumps(source_settings, indent=2))
    command('setSatelliteUpdateSetting', {'updatesEnabled': False})
    backup = args.output / 'original-catalog.json'
    hdc('file', 'recv', catalog, str(backup))
    original = json.loads(backup.read_text())

    def digest():
        return hdc('shell', 'sha256sum ' + catalog).split()[0]

    baseline = digest()
    cases = ingestion.fixtures()
    for name, (content, _) in cases.items():
        path = args.output / (name + '.txt')
        path.write_bytes(content.encode())
        hdc('file', 'send', '-b', args.bundle, str(path), device_fixture + '/' + name + '.txt')

    release = threading.Event()
    started = threading.Event()
    satellite_id = 99990
    while str(satellite_id) in original['satellites']:
        satellite_id -= 1
    first, second = cases['valid-2le'][0].splitlines()
    first = ingestion.checksum(first[:2] + str(satellite_id) + first[7:])
    second = ingestion.checksum(second[:2] + str(satellite_id) + second[7:])
    local_data = 'SATELLITE TEST\n' + first + '\n' + second + '\n'
    newer_first = ingestion.checksum(first[:18] + '26301.50000000' + first[32:])
    online_data = 'SATELLITE TEST\n' + newer_first + '\n' + second + '\n'

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/slow':
                started.set()
                release.wait(20)
            content = ('BROKEN\n1 12345\n' if self.path == '/bad' else online_data).encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)

        def log_message(self, *unused):
            pass

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()
    remote_port = 18992
    forwarding = False

    def sources(paths):
        return {'sources': [{'url': f'http://127.0.0.1:{remote_port}{path}', 'addNew': True} for path in paths]}

    def finish_update():
        for attempt in range(80):
            response = command('getSatelliteSources')
            if response['settings']['updateState'] != 0:
                return response['settings']['updateState']
            time.sleep(0.5)
        raise AssertionError('update did not terminate')

    try:
        for malformed in ({}, {'sources': 'invalid'}, {'sources': None}, ''):
            response = command('setSatelliteSources', malformed, reject=True)
            current_sources = command('getSatelliteSources')['sources']
            expect('invalid source configuration retains current sources: ' + json.dumps(malformed),
                   not response.get('ok') and current_sources == source_settings['sources'])
        for name, (_, expected) in cases.items():
            response = command('importSatelliteTle', {'paths': [sandbox + '/' + name + '.txt']}, reject=True)
            expect(name + ' result', response.get('ok') == expected)
            expect(name + ' retains existing newer catalogue', digest() == baseline)
        path = args.output / 'new.txt'
        path.write_text(local_data)
        hdc('file', 'send', '-b', args.bundle, str(path), device_fixture + '/new.txt')
        mixed = command('importSatelliteTle', {'paths': [sandbox + '/new.txt', sandbox + '/truncated.txt']}, reject=True)
        expect('mixed valid and corrupt files rejected atomically', not mixed['ok'] and digest() == baseline)
        missing = command('importSatelliteTle', {'paths': [sandbox + '/new.txt', sandbox + '/missing.txt']}, reject=True)
        expect('mixed valid and missing files rejected atomically', not missing['ok'] and digest() == baseline)
        command('setSatelliteUpdateSetting', {'autoAddEnabled': False})
        imported = command('importSatelliteTle', {'paths': [sandbox + '/new.txt']})
        expect('explicit import adds a satellite with auto-add disabled', imported['catalogCountAfter'] == imported['catalogCountBefore'] + 1)
        new_digest = digest()
        unchanged = command('importSatelliteTle', {'paths': [sandbox + '/new.txt']})
        expect('repeated import is idempotent', unchanged['updateState'] == 1 and digest() == new_digest)
        hdc('rport', f'tcp:{remote_port}', f'tcp:{port}')
        forwarding = True
        command('setSatelliteSources', sources(['/slow']))
        command('refreshSatelliteCatalog')
        expect('controlled online request is in progress', started.wait(5))
        for name, payload in [('importSatelliteTle', {'paths': [sandbox + '/new.txt']}),
                              ('setSatelliteSources', sources(['/bad'])),
                              ('restoreSatelliteSources', ''), ('refreshSatelliteCatalog', '')]:
            response = command(name, payload, reject=True)
            expect(name + ' rejects concurrent mutation', response.get('reason') == 'satellite_update_busy')
        release.set()
        expect('online update completes after import', finish_update() == 2)
        updated_digest = digest()
        older = command('importSatelliteTle', {'paths': [sandbox + '/new.txt']})
        expect('older import cannot overwrite online orbit', older['updateState'] == 1 and digest() == updated_digest)
        command('setSatelliteSources', sources(['/valid', '/bad']))
        command('refreshSatelliteCatalog')
        expect('bad remote source reports partial success without damaging valid data', finish_update() == 5 and digest() == updated_digest)
        command('setSatelliteSources', sources(['/bad']))
        command('refreshSatelliteCatalog')
        expect('all bad online data fails and preserves catalogue', finish_update() == 3 and digest() == updated_digest)
    finally:
        release.set()
        finish_update()
        cleaned_up = False
        try:
            cleanup_file = args.output / 'cleanup.tle'
            cleanup_file.write_text(cases['valid-2le'][0])
            cleanup_paths = []
            for name in list(cases) + ['new']:
                target = device_fixture + '/' + name + '.txt'
                hdc('file', 'send', '-b', args.bundle, str(cleanup_file), target)
                cleanup_paths.append(target)
            command('importSatelliteTle', {'paths': cleanup_paths, 'deleteFiles': True})
            cleaned_up = all(hdc('shell', 'if test -f ' + base + '/' + path.rsplit('/', 1)[1] +
                                '; then echo present; else echo absent; fi').strip() == 'absent'
                             for path in cleanup_paths)
        except Exception as error:
            print('Fixture cleanup failed:', error, flush=True)
        command('setSatelliteSources', {'sources': source_settings['sources']})
        command('setSatelliteUpdateSetting', {'autoAddEnabled': source_settings['settings']['autoAddEnabled']})
        hdc('shell', 'aa force-stop ' + args.bundle)
        hdc('file', 'send', '-b', args.bundle, str(backup), sandbox + '/modules/Satellites/satellites.json')
        expect('original catalogue restored after injection tests', digest() == baseline)
        if forwarding:
            hdc('fport', 'rm', f'tcp:{remote_port}', f'tcp:{port}')
        server.shutdown()
        hdc('shell', 'aa start -a QAbility -b ' + args.bundle)
        time.sleep(5)
        command('setSatelliteUpdateSetting', {'updatesEnabled': source_settings['settings']['updatesEnabled']})
        expect('injected fixture files removed', cleaned_up)


if __name__ == '__main__':
    main()
