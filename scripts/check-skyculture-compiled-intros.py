import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('reviews', ROOT / 'scripts/review-skyculture-passages.py')
REVIEWS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REVIEWS)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lconvert', default=os.environ.get('LCONVERT', 'lconvert'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    context = json.loads((ROOT / 'data/skyculture_editorial_context.json').read_text())
    languages = context['priorityLanguages']
    _, sections = REVIEWS.load_reviews()
    sections = [section for section in sections if section['section'] == 'Introduction']
    cultures = {file.parent.name for file in (ROOT / 'skycultures').glob('*/description.md')}
    if {section['culture'] for section in sections} != cultures:
        raise ValueError('Introduction registry does not cover all bundled cultures')
    raw = ROOT / 'build/libstellarium-harmonyos/entry/src/main/resources/rawfile/stellarium'
    checks = []
    with tempfile.TemporaryDirectory(prefix='skyculture-qm-check-') as temp:
        for language in languages:
            path = Path('translations/stellarium-skycultures-descriptions') / f'{language}.qm'
            if (ROOT / path).read_bytes() != (raw / path).read_bytes():
                raise ValueError(f'Stale packaged QM: {language}')
            target = Path(temp) / f'{language}.ts'
            subprocess.run([args.lconvert, '-i', str(ROOT / path), '-o', str(target)], check=True, capture_output=True)
            translations = {message.findtext('source'): message.findtext('translation')
                            for node in ET.parse(target).findall('context') if not node.findtext('name')
                            for message in node.findall('message')}
            for section in sections:
                expected = '\n\n'.join(section['translations'][language])
                if translations.get(section['sourceAfter']) != expected:
                    raise ValueError(f"Compiled translation mismatch: {section['culture']}/{language}")
                checks.append({'culture': section['culture'], 'language': language, 'result': 'matched'})
    for culture in cultures:
        path = Path('skycultures') / culture / 'description.md'
        if (ROOT / path).read_bytes() != (raw / path).read_bytes():
            raise ValueError(f'Stale packaged source: {culture}')
    path = Path('data/skyculture_editorial_context.json')
    if (ROOT / path).read_bytes() != (raw / path).read_bytes():
        raise ValueError('Stale packaged editorial context')
    report = {'cultureCount': len(cultures), 'languageCount': len(languages), 'matchedChecks': len(checks),
              'scope': 'Compiled introductory text and packaged resources; not device rendering or full-body translation certification',
              'checks': checks}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ('cultureCount', 'languageCount', 'matchedChecks')}))


if __name__ == '__main__':
    main()
