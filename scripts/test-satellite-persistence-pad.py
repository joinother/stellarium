import argparse
import http.server
import importlib.util
import json
from pathlib import Path
import re
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
        if result.returncode or '[Fail]' in result.stdout or 'Permission denied' in result.stdout:
            raise RuntimeError(result.stdout + result.stderr)
        return result.stdout

    def command(name, payload=None):
        invocation = ['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                      '--bundle', args.bundle, '--hdc', args.hdc, '--command', name, '--json']
        if payload is not None:
            invocation += ['--payload', payload if isinstance(payload, str) else json.dumps(payload)]
        result = subprocess.run(invocation, capture_output=True, text=True, timeout=100)
        response = json.loads(result.stdout or result.stderr)
        if not response.get('ok'):
            raise AssertionError((name, response))
        return response

    def expect(name, condition):
        checks.append({'name': name, 'ok': bool(condition)})
        (args.output / 'checks.json').write_text(json.dumps(checks, ensure_ascii=False, indent=2))
        if not condition:
            raise AssertionError(name)
        print('PASS', name, flush=True)

    def settings():
        return command('getSatelliteSources')['settings']

    def start():
        hdc('shell', 'aa start -a QAbility -b ' + args.bundle)
        for attempt in range(3):
            try:
                return settings()
            except (AssertionError, subprocess.TimeoutExpired):
                if attempt == 2:
                    raise
                time.sleep(2)

    def restart():
        hdc('shell', 'aa force-stop ' + args.bundle)
        return start()

    def replace_settings(text, values):
        match = re.search(r'(?ms)^\[Satellites\]\n(.*?)(?=^\[|\Z)', text)
        if not match:
            raise AssertionError('Satellites config section missing')
        section = match.group(1)
        for key, value in values.items():
            pattern = r'(?m)^' + re.escape(key) + r'=.*$'
            line = key + '=' + value
            section = re.sub(pattern, lambda _: line, section) if re.search(pattern, section) else section + line + '\n'
        return text[:match.start(1)] + section + text[match.end(1):]

    base = f'/data/app/el2/100/base/{args.bundle}/files/stellarium_userdir'
    sandbox = '/data/storage/el2/base/files/stellarium_userdir'
    original_settings = start()
    backup = args.output / 'original-config.ini'
    hdc('file', 'recv', base + '/config.ini', str(backup))
    original = backup.read_text()
    expect('starts idle', original_settings['updateState'] != 0)
    baseline = hdc('shell', 'sha256sum ' + base + '/modules/Satellites/satellites.json').split()[0]
    data = ingestion.fixtures()['valid-3le'][0].encode()
    requests = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            content = data if self.path == '/valid' else b'Invalid query'
            self.send_response(200)
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)

        def log_message(self, *_):
            pass

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    port = server.server_address[1]
    remote_port = 18992
    threading.Thread(target=server.serve_forever, daemon=True).start()
    forwarding = False

    def force_due():
        hdc('shell', 'aa force-stop ' + args.bundle)
        current = args.output / 'due-config.ini'
        hdc('file', 'recv', base + '/config.ini', str(current))
        current.write_text(replace_settings(current.read_text(), {
            'last_update': '2001-05-25T12:00:00',
            'next_automatic_update_attempt': '2001-05-25T12:00:00'}))
        hdc('file', 'send', '-b', args.bundle, str(current), sandbox + '/config.ini')
        return start()

    def wait_complete(previous):
        deadline = time.monotonic() + 75
        while time.monotonic() < deadline:
            current = settings()
            if current['updateState'] != 0 and current.get('lastCheckedAt', '') != previous:
                return current
            time.sleep(1)
        raise AssertionError('update did not finish')

    try:
        command('setSatelliteUpdateSetting', {'updatesEnabled': True})
        expect('enabled setting survives force-stop and restart', restart()['updatesEnabled'])
        command('setSatelliteUpdateSetting', {'updatesEnabled': False})
        expect('disabled setting survives force-stop and restart', not restart()['updatesEnabled'])
        hdc('rport', f'tcp:{remote_port}', f'tcp:{port}')
        forwarding = True
        command('setSatelliteSources', {'sources': [f'http://127.0.0.1:{remote_port}/valid']})
        command('setSatelliteUpdateSetting', {'updatesEnabled': True})
        previous = settings().get('lastCheckedAt', '')
        force_due()
        complete = wait_complete(previous)
        expect('overdue automatic timer really makes a request', requests == ['/valid'])
        expect('unchanged valid data records a completed check', complete['lastCheckResult'] == 1)
        expect('successful check schedules configured interval', complete['secondsToUpdate'] > 3600)
        previous_orbit = command('getSatellites')['satellites']['newestUpdate']
        command('openUiPanel', 'satellites')
        command('setSatellitePanelSection', 'diagnostics')
        command('refreshSatelliteCatalog')
        manual = wait_complete(complete['lastCheckedAt'])
        expect('manual unchanged refresh advances check timestamp', manual['lastCheckResult'] == 1)
        expect('unchanged refresh keeps actual orbit timestamp', command('getSatellites')['satellites']['newestUpdate'] == previous_orbit)
        deadline = time.monotonic() + 15
        panel = {}
        while time.monotonic() < deadline:
            panel = command('getSatellitePanelState')
            if panel.get('updateSettings', {}).get('lastCheckedAt') == manual['lastCheckedAt']:
                break
            time.sleep(1)
        (args.output / 'panel.json').write_text(json.dumps(panel, ensure_ascii=False, indent=2))
        expect('open details panel receives new check record', panel.get('updateSettings', {}).get('lastCheckedAt') == manual['lastCheckedAt'])
        command('setSatelliteSources', {'sources': [f'http://127.0.0.1:{remote_port}/bad']})
        force_due()
        failed = wait_complete(manual['lastCheckedAt'])
        expect('malformed automatic response records failure', failed['lastCheckResult'] == 3)
        expect('failure exposes retry cooldown', 1500 < failed['secondsToUpdate'] <= 1800)
        count = len(requests)
        resumed = restart()
        expect('failure result survives restart', resumed['lastCheckResult'] == 3)
        expect('retry cooldown survives restart', 1400 < resumed['secondsToUpdate'] <= 1800)
        time.sleep(16)
        expect('restart does not hammer a failed source', len(requests) == count)
        expect('all checks preserve installed catalogue', hdc('shell', 'sha256sum ' + base + '/modules/Satellites/satellites.json').split()[0] == baseline)
    finally:
        hdc('shell', 'aa force-stop ' + args.bundle)
        restored = args.output / 'restored-config.ini'
        restored.write_text(replace_settings(original, {'updates_enabled': 'true'}))
        hdc('file', 'send', '-b', args.bundle, str(restored), sandbox + '/config.ini')
        if forwarding:
            hdc('fport', 'rm', f'tcp:{remote_port}', f'tcp:{port}')
        server.shutdown()
        expect('restored production settings leave automatic updates enabled', start()['updatesEnabled'])


if __name__ == '__main__':
    main()
