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
    args = parser.parse_args()

    def command(name, payload=None, allow_error=False):
        invocation = ['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                      '--command', name, '--json']
        if payload is not None:
            invocation.extend(['--payload', payload])
        result = subprocess.run(invocation, capture_output=True, text=True, timeout=60)
        response = json.loads(result.stdout)
        if not allow_error and response.get('ok') is not True:
            raise RuntimeError(str(response))
        return response

    camera = command('getMosaicCamera')['mosaicCamera']
    textures = command('getNebulaTextureStatus')
    report = {'checks': [], 'initialCamera': camera, 'initialTextureCount': textures['count']}
    imported = None

    def expect(name, condition):
        report['checks'].append({'name': name, 'ok': bool(condition)})
        if not condition:
            raise AssertionError(name)

    try:
        expect('visibility is boolean', isinstance(camera['visible'], bool))
        for value in [True, False, True, False]:
            command('setMosaicCamera', f'enabled|{int(value)}')
            command('setMosaicCamera', f'visible|{int(value)}')
            state = command('getMosaicCamera')['mosaicCamera']
            expect(f'camera flags {value}', state['enabled'] == value and state['visible'] == value)
        for name in camera['names']:
            command('setMosaicCamera', f'camera|{name}')
            expect(f'camera selection {name}', command('getMosaicCamera')['mosaicCamera']['currentCamera'] == name)
        command('setMosaicCamera', f"camera|{camera['currentCamera']}")
        for key, value in [('ra', '361'), ('dec', '91'), ('rotation', 'nan'), ('camera', 'unknown')]:
            expect(f'reject invalid {key}', command('setMosaicCamera', f'{key}|{value}', True).get('ok') is not True)
        resources = command('getDeepSkyImageStatus')
        source = resources['imageRoot'] + '/m31.png'
        response = command('importNebulaTexture', json.dumps({'sourcePath': source,
                           'centerRaDeg': 10, 'centerDecDeg': 30, 'angularWidthDeg': 2}))
        imported = response['imageUrl']
        status = command('getNebulaTextureStatus')
        expect('offline import valid', status['count'] == textures['count'] + 1
               and any(item['imageUrl'] == imported and item['ready'] for item in status['items']))
        decodes = status['imageDecodeCount']
        rebuilds = status['layerRebuildCount']
        for enabled in [False, True, True, False, True]:
            command('setNebulaTexturesVisible', str(int(enabled)))
            command('setNebulaTextureConflictAvoidance', str(int(enabled)))
            status = command('getNebulaTextureStatus')
            expect(f'texture flags without reload {enabled}', status['enabled'] == enabled
                   and status['avoidAreaConflict'] == enabled and status['imageDecodeCount'] == decodes
                   and status['layerRebuildCount'] == rebuilds)
        time.sleep(3)
        status = command('getNebulaTextureStatus')
        expect('collection completion does not rebuild the layer', status['layerRebuildCount'] == rebuilds)
        refreshed = command('refreshNebulaTextures')['status']
        expect('explicit refresh rebuilds once without decoding unchanged images',
               refreshed['layerRebuildCount'] == rebuilds + 1 and refreshed['imageDecodeCount'] == decodes)
        expect('fixture validation uses the cache', command('validateNebulaTexture', imported)['ready'])
        report['probes'] = {'imageDecodeCount': decodes, 'layerRebuildCount': rebuilds}
    finally:
        if imported:
            command('removeNebulaTexture', imported)
        command('setNebulaTexturesVisible', str(int(textures['enabled'])))
        command('setNebulaTextureConflictAvoidance', str(int(textures['avoidAreaConflict'])))
        command('setMosaicCamera', f"camera|{camera['currentCamera']}")
        command('setMosaicCamera', f"enabled|{int(camera['enabled'])}")
        command('setMosaicCamera', f"visible|{int(camera['visible'])}")
        report['restored'] = command('getMosaicCamera')['mosaicCamera'] == camera
        report['fixtureRemoved'] = command('getNebulaTextureStatus')['count'] == textures['count']
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'checks': len(report['checks']), 'restored': report['restored'],
                      'fixtureRemoved': report['fixtureRemoved']}))


if __name__ == '__main__':
    main()
