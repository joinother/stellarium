import argparse
import importlib.util
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
PRIORITY_LANGUAGES = ['zh_CN', 'zh_TW', 'en', 'es', 'fr', 'de', 'ru', 'ja', 'ko', 'pt_BR']
SPEC = importlib.util.spec_from_file_location('editorial_audit', ROOT / 'scripts/audit-skyculture-editorial.py')
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


def source_sections(markdown):
    markdown = re.sub(r'<!--.*?-->', '', markdown.replace('\r', ''))
    parts = re.split(r'^## +(.+)$', markdown, flags=re.M)
    return [(parts[index], parts[index + 1].strip('\n')) for index in range(1, len(parts), 2)]


def translation_mode(source, entries, locale):
    if locale == 'en' or locale.startswith('en_'):
        return 'source-language'
    entry = entries.get(('', source))
    if not entry or not entry.get('msgstr'):
        return 'source-fallback'
    if entry.get('fuzzy'):
        return 'fuzzy-fallback'
    if entry['msgstr'].strip() == source.strip():
        return 'source-copy'
    return 'translated-draft'


def constellation_parts(source):
    parts = re.split(r'^[ \t]*#####[ \t]*([^#\n][^\n]*)$', source, flags=re.M)
    return [parts[index].strip() for index in range(2, len(parts), 2) if parts[index].strip()]


def section_coverage(name, source, entries, locale):
    mode = translation_mode(source, entries, locale)
    units = [mode]
    if name == 'Constellations' and mode in ('source-fallback', 'fuzzy-fallback'):
        parts = constellation_parts(source)
        if parts:
            units = [translation_mode(part, entries, locale) for part in parts]
    return {'section': name, 'wholeSection': mode, 'htmlUnits': len(units),
            'htmlTranslatedUnits': sum(item == 'translated-draft' for item in units),
            'htmlFallbackUnits': sum(item in ('source-fallback', 'fuzzy-fallback', 'source-copy') for item in units),
            'narrationMode': mode}


def build_report(root=ROOT):
    cultures = {}
    for file in sorted((root / 'skycultures').glob('*/description.md')):
        cultures[file.parent.name] = source_sections(file.read_text())
    catalogs = []
    failures = []
    for file in sorted((root / 'po/stellarium-skycultures-descriptions').glob('*.po')):
        entries = {(entry.get('msgctxt', ''), entry['msgid']): entry for entry in AUDIT.read_catalog(file)}
        coverage = []
        for culture, sections in cultures.items():
            details = [section_coverage(name, source, entries, file.stem)
                       for name, source in sections if source and name not in ('References', 'Authors', 'License')]
            intro = next((item['wholeSection'] for item in details if item['section'] == 'Introduction'), 'not-applicable')
            coverage.append({'culture': culture, 'introduction': intro, 'sections': details,
                             'semanticReview': 'not-certified'})
            if file.stem in PRIORITY_LANGUAGES and intro not in ('translated-draft', 'source-language'):
                failures.append({'culture': culture, 'locale': file.stem, 'mode': intro})
        catalogs.append({'locale': file.stem, 'priority': file.stem in PRIORITY_LANGUAGES, 'cultures': coverage})
    available = {catalog['locale'] for catalog in catalogs}
    if set(PRIORITY_LANGUAGES) - available:
        raise ValueError('Priority catalog files missing')
    return {'schemaVersion': 1, 'priorityLanguages': PRIORITY_LANGUAGES,
            'scope': 'Exact runtime source keys across all culture descriptions and all PO catalogs; not native-language or regulatory certification.',
            'cultureCount': len(cultures), 'localeCount': len(catalogs),
            'priorityIntroductionFailures': failures, 'catalogs': catalogs}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--require-priority-intros', action='store_true')
    args = parser.parse_args()
    report = build_report()
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ('cultureCount', 'localeCount', 'priorityIntroductionFailures')}, ensure_ascii=False))
    if args.require_priority_intros and report['priorityIntroductionFailures']:
        raise SystemExit('Priority introductions still fall back to source')


if __name__ == '__main__':
    main()
