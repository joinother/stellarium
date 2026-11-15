import argparse
import os
from pathlib import Path
import runpy
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--qt-prefix', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    extract = runpy.run_path(str(root / 'scripts/test-painter-streaming.py'))['function']
    source = (root / 'src/core/modules/AtmosphereLightweight.cpp').read_text()
    header = (root / 'src/core/modules/AtmosphereLightweight.hpp').read_text()
    params = header[header.index('\tstruct DrawParams'):header.index(' drawParams[DRAW_PARAM_COUNT];')]
    implementation = '\n'.join(extract(source, signature) for signature in (
        'void AtmosphereLightweight::computeColor(', 'void AtmosphereLightweight::computeDrawParams('))
    with tempfile.TemporaryDirectory(prefix='stellarium-lightweight-prep-') as directory:
        temporary = Path(directory)
        (temporary / 'draw-params.inc').write_text(params + ';\n')
        (temporary / 'lightweight-preparation.inc').write_text(implementation)
        executable = temporary / 'test-preparation'
        frameworks = args.qt_prefix / 'lib'
        command = [os.environ.get('CXX', 'c++'), '-std=c++17', '-O1', '-g',
                   '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-Wall', '-Wextra',
                   '-I' + str(root / 'src/core'), '-I' + str(temporary), '-F' + str(frameworks)]
        for framework in ('QtCore', 'QtGui', 'QtOpenGL'):
            command += ['-I' + str(frameworks / f'{framework}.framework/Headers'), '-framework', framework]
        command += [str(root / 'scripts/test-lightweight-preparation.cpp'), str(root / 'src/core/VecMath.cpp'),
                    '-Wl,-rpath,' + str(frameworks), '-o', str(executable)]
        subprocess.run(command, check=True)
        subprocess.run([str(executable)], check=True)
        mutations = {
            'missing first-fill guard': ('p.prepCached && p.prepCachedLayerA', 'p.prepCachedLayerA'),
            'stale alpha': ('&& p.prepCachedAlpha == p.layerAlpha', ''),
            'single-layer blend': ('if (pass == 1)', 'if (layer == p.layerToDrawB)'),
            'single-layer NaN': ('highIt == lowIt ? 0.f : ', ''),
        }
        for name, (before, after) in mutations.items():
            broken = implementation.replace(before, after)
            assert broken != implementation, name
            (temporary / 'lightweight-preparation.inc').write_text(broken)
            subprocess.run(command, check=True, capture_output=True)
            result = subprocess.run([str(executable)], capture_output=True, text=True)
            assert result.returncode != 0, f'Mutation escaped: {name}'
            assert 'Assertion' in result.stderr or 'ASSERT:' in result.stderr, result.stderr
            print('Mutation rejected:', name)


if __name__ == '__main__':
    main()
