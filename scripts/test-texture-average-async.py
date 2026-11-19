import argparse
from pathlib import Path
import runpy
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--qt-prefix", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    extract = runpy.run_path(str(root / "scripts/test-painter-streaming.py"))["function"]
    header = (root / "src/core/TextureAverageComputer.hpp").read_text().replace('#include "StelOpenGL.hpp"', '')
    source = (root / "src/core/TextureAverageComputer.cpp").read_text()
    for include in ('TextureAverageComputer.hpp', 'StelMainView.hpp', 'StelUtils.hpp'):
        source = source.replace(f'#include "{include}"', '')
    header = header.replace('QOpenGLExtraFunctions&', 'TestGL&')
    source = source.replace('QOpenGLExtraFunctions&', 'TestGL&').replace(
        'gl(*QOpenGLContext::currentContext()->extraFunctions())', 'gl(testGL())')
    lightweight = (root / 'src/core/modules/AtmosphereLightweight.cpp').read_text()
    light_header = (root / 'src/core/modules/AtmosphereLightweight.hpp').read_text()
    fields = light_header[light_header.index('\tstruct LuminanceReadbackSample'):]
    fields = fields[:fields.index('\n\tstd::unique_ptr')]
    average = extract(lightweight, 'float AtmosphereLightweight::computeAverageLuminance(')
    tail = average[average.index('\tLuminanceReadbackSample sample;'):]
    tail = tail.replace('context->isOpenGLES()', 'testGLES')
    tail = tail.replace('std::chrono::steady_clock::now()', 'testNow')
    probe = lightweight[lightweight.index('const auto luminanceProbeFragSrc = R"('):]
    probe = probe[:probe.index(')";') + 3]
    with tempfile.TemporaryDirectory(prefix='texture-average-async-') as directory:
        temporary = Path(directory)
        (temporary / 'texture-average-source.inc').write_text(header + '\n' + source)
        (temporary / 'luminance-fields.inc').write_text(fields)
        (temporary / 'luminance-tail.inc').write_text('float computeAverageLuminance(const TestCore* core) {\n' + tail)
        (temporary / 'luminance-probe.inc').write_text(probe)
        frameworks = args.qt_prefix / 'lib'
        command = ['c++', '-std=c++17', '-O1', '-g', '-fsanitize=address,undefined',
                   '-fno-omit-frame-pointer', '-Wall', '-Wextra',
                   '-I' + str(root / 'src/core'), '-I' + str(temporary), '-F' + str(frameworks)]
        for name in ('QtCore', 'QtGui', 'QtOpenGL'):
            command += ['-I' + str(frameworks / f'{name}.framework/Headers'), '-framework', name]
        executable = temporary / 'test-average'
        command += [str(root / 'scripts/test-texture-average-async.cpp'), str(root / 'src/core/VecMath.cpp'),
                    '-Wl,-rpath,' + str(frameworks), '-o', str(executable)]
        subprocess.run(command, check=True)
        subprocess.run([str(executable)], check=True)
        broken = tail.replace('restoreLuminance(result.value, completedLuminanceSample_)',
                              'restoreLuminance(result.value, sample)')
        assert broken != tail
        (temporary / 'luminance-tail.inc').write_text('float computeAverageLuminance(const TestCore* core) {\n' + broken)
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        regression = subprocess.run([str(executable)], capture_output=True, text=True)
        assert regression.returncode != 0 and '.9f' in regression.stderr, regression.stderr
        print('Wrong-current-weights mutation rejected')
        (temporary / 'luminance-tail.inc').write_text('float computeAverageLuminance(const TestCore* core) {\n' + tail)
        broken_source = source.replace('if (gl.glGetError() != GL_NO_ERROR) readbackFailed = true;', '')
        assert broken_source != source
        (temporary / 'texture-average-source.inc').write_text(header + '\n' + broken_source)
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        regression = subprocess.run([str(executable)], capture_output=True, text=True)
        assert regression.returncode != 0 and '!failedRead.enqueueTextureAverageSimple' in regression.stderr, regression.stderr
        print('Delayed-error-check mutation rejected with OHOS-style draining GL macros')
        (temporary / 'texture-average-source.inc').write_text(header + '\n' + source)
        mutations = {
            'fixed sixty-second fast-forward rejection': ('if (std::abs(elapsedDays) >= 0.95) return false;', 'if (std::abs(elapsedDays) > 60. / 86400.) return false;'),
            'ignored explicit time synchronization': ('&& sample.syncMilliseconds == captured.syncMilliseconds', ''),
            'ignored light direction discontinuity': ('lightCosine < std::cos(M_PI / 180.)', 'false'),
            'ignored layer blend discontinuity': ('|| std::abs(sample.layerAlphas[index] - captured.layerAlphas[index]) > 0.25f', ''),
            'ignored elapsed-time discontinuity': ('if (std::abs(elapsedDays - sample.timeRate * elapsed) > driftLimit) return false;', ''),
            'accepted whole-day direction alias': ('if (std::abs(elapsedDays) >= 0.95) return false;', ''),
        }
        for name, (before, after) in mutations.items():
            assert before in tail, name
            broken = tail.replace(before, after)
            (temporary / 'luminance-tail.inc').write_text('float computeAverageLuminance(const TestCore* core) {\n' + broken)
            subprocess.run(command, check=True, capture_output=True)
            regression = subprocess.run([str(executable)], capture_output=True, text=True)
            assert regression.returncode != 0 and 'Assertion' in regression.stderr, name + ': ' + regression.stderr
            print('Mutation rejected:', name)


if __name__ == '__main__':
    main()
