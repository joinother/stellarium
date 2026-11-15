import os
from pathlib import Path
import re
import runpy
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
FUNCTION = runpy.run_path(str(ROOT / 'scripts/test-painter-streaming.py'))['function']


def read(path):
    return (ROOT / path).read_text()


def check_wiring(read_source):
    for path in ('StelToast.cpp', 'StelHips.cpp', 'StelSkyImageTile.cpp',
                 'modules/ZoneArray.cpp', 'modules/MilkyWay.cpp',
                 'modules/ZodiacalLight.cpp', 'modules/Comet.cpp'):
        source = read_source('src/core/' + path)
        assert 'getVisualExtinction()' in source, path
        assert 'getExtinction()' not in source, path
    consumers = {
        'src/core/StelObject.cpp': ('StelObject::getPickState(', 'StelObject::getSelectPriority('),
        'src/core/modules/Planet.cpp': ('Planet::draw(', 'Planet::draw3dModel(', 'Planet::drawHints(', 'Planet::getSelectPriority('),
        'src/core/modules/Nebula.cpp': ('Nebula::getPickState(',),
        'src/core/modules/Comet.cpp': ('Comet::drawComa(',),
        'plugins/Satellites/src/Satellite.cpp': ('Satellite::getRenderState(',),
        'plugins/Quasars/src/Quasar.cpp': ('Quasar::draw(', 'Quasar::getSelectPriority('),
        'plugins/Exoplanets/src/Exoplanet.cpp': ('Exoplanet::draw(',),
        'plugins/Supernovae/src/Supernova.cpp': ('Supernova::draw(',),
        'plugins/Novae/src/Nova.cpp': ('Nova::draw(',),
    }
    for path, signatures in consumers.items():
        for signature in signatures:
            source = read_source(path)
            definition = re.search(r'^\w+ ' + re.escape(signature), source, re.MULTILINE)
            assert definition, signature
            body = FUNCTION(source, definition.group())
            assert 'getVMagnitudeWithVisualExtinction(' in body, signature
            assert 'getVMagnitudeWithExtinction(' not in body, signature
    physical = {
        'src/core/modules/AtmospherePreetham.cpp': 'moon->getVMagnitudeWithExtinction(core)',
        'src/core/modules/LandscapeMgr.cpp': 'moon->getVMagnitudeWithExtinction(core)',
        'src/core/StelObject.cpp': 'map.insert("vmage", getVMagnitudeWithExtinction(core))',
        'src/core/modules/Nebula.cpp': 'qMin(getVMagnitudeWithExtinction(core), getBMagnitudeWithExtinction(core))',
        'plugins/Satellites/src/Satellite.cpp': 'QString::number(getVMagnitudeWithExtinction(core, mag)',
    }
    for path, expression in physical.items():
        assert expression in read_source(path), path
    nebula = FUNCTION(read_source('src/core/modules/Nebula.cpp'), 'Nebula::getVisibilityLevelByMagnitude(')
    assert 'qMin(vMag, bMag)' in nebula and 'WithExtinction(' not in nebula


def extracted_code():
    header = read('src/core/RefractionExtinction.hpp')
    extinction = header[header.index('\nclass Extinction\n') + 1:header.index('//! @class Refraction')]
    source = read('src/core/RefractionExtinction.cpp')
    extinction += FUNCTION(source, 'Extinction::Extinction()')
    extinction += FUNCTION(source, 'float Extinction::airmass(')
    drawer_header = read('src/core/StelSkyDrawer.hpp')
    accessors = '\n'.join(FUNCTION(drawer_header, 'const Extinction& ' + name + '(')
                          for name in ('getExtinction', 'getVisualExtinction'))
    drawer = read('src/core/StelSkyDrawer.cpp')
    update = FUNCTION(drawer, 'void StelSkyDrawer::update(')
    scaling = re.search(r'visualExtinction = extinction;\s*visualExtinction\.setExtinctionCoefficient\([^;]+;', update)
    assert scaling, 'Missing per-frame visual extinction update'
    setter = FUNCTION(drawer, 'void StelSkyDrawer::setExtinctionCoefficient(')
    obj_header = read('src/core/StelObject.hpp')
    names = ('getVMagnitudeWithExtinction', 'getVMagnitudeWithVisualExtinction')
    declarations = '\n'.join(re.search(r'float ' + name + r'\([^;]+;', obj_header).group() for name in names)
    methods = '\n'.join(FUNCTION(read('src/core/StelObject.cpp'), 'float StelObject::' + name + '(') for name in names)
    return extinction, accessors, scaling.group(), setter, declarations, methods


def main():
    check_wiring(read)
    for path, before, after in (
        ('src/core/StelToast.cpp', 'getVisualExtinction()', 'getExtinction()'),
        ('src/core/modules/Planet.cpp', 'getVMagnitudeWithVisualExtinction(', 'getVMagnitudeWithExtinction('),
        ('src/core/modules/AtmospherePreetham.cpp', 'getVMagnitudeWithExtinction(', 'getVMagnitudeWithVisualExtinction('),
    ):
        try:
            check_wiring(lambda name: read(name).replace(before, after) if name == path else read(name))
        except AssertionError:
            print('Wiring mutation rejected:', path)
        else:
            raise AssertionError('Wiring mutation escaped: ' + path)
    parts = extracted_code()
    template = read('scripts/test-visual-extinction.cpp.in')
    for marker, value in zip(('EXTINCTION', 'ACCESSORS', 'SCALING', 'SETTER', 'DECLARATIONS', 'METHODS'), parts):
        template = template.replace('@' + marker + '@', value)
    with tempfile.TemporaryDirectory(prefix='stellarium-visual-extinction-') as directory:
        temporary = Path(directory)
        source = temporary / 'test.cpp'
        executable = temporary / 'test'
        command = [os.environ.get('CXX', 'c++'), '-std=c++17', '-O1', '-g',
                   '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-Wall', '-Wextra',
                   str(source), '-o', str(executable)]
        source.write_text(template)
        subprocess.run(command, check=True)
        subprocess.run([str(executable)], check=True)
        mutations = {
            'physical accessor returns visual': ('getExtinction() const {return extinction;}', 'getExtinction() const {return visualExtinction;}'),
            'frame scaling mutates physical coefficient': (parts[2], parts[2].replace('visualExtinction.setExtinctionCoefficient', 'extinction.setExtinctionCoefficient')),
            'visual magnitude uses physical extinction': ('getVisualExtinction().forward', 'getExtinction().forward'),
        }
        for name, (before, after) in mutations.items():
            assert before in template, name
            source.write_text(template.replace(before, after))
            subprocess.run(command, check=True, capture_output=True)
            result = subprocess.run([str(executable)], capture_output=True, text=True)
            assert result.returncode != 0 and 'Assertion' in result.stderr, name + ': ' + result.stderr
            print('Runtime mutation rejected:', name)
    print('PASS: visual/physical extinction runtime invariants and draw-consumer wiring')


if __name__ == '__main__':
    main()
