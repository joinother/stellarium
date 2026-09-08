import argparse
import ast
import difflib
import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / 'docs/harmonyos/skyculture-passage-revisions.json'
SECTIONS = ROOT / 'docs/harmonyos/skyculture-section-translations.json'
CORPUS_RULES = ROOT / 'docs/harmonyos/skyculture-corpus-revisions.json'
BATCHES = ROOT / 'docs/harmonyos/culture-review-batches'
FIELD = re.compile(r'^(msgid|msgstr) (".*")(?:\n".*")*', re.M)


def load_reviews(batch_names=None):
    rules = json.loads(RULES.read_text())['rules'] + json.loads(CORPUS_RULES.read_text())['rules']
    sections = json.loads(SECTIONS.read_text())['sections']
    for file in sorted(BATCHES.glob('*.json')):
        if batch_names is not None and file.stem not in batch_names:
            continue
        batch = json.loads(file.read_text())
        rules.extend(batch.get('rules', []))
        sections.extend(batch.get('sections', []))
    if len({rule['id'] for rule in rules}) != len(rules):
        raise ValueError('Duplicate revision IDs')
    return rules, sections


def replace_section(content, section):
    pattern = re.compile(r'(^## +' + re.escape(section['section']) + r'\n)(.*?)(?=^## +|\Z)', re.M | re.S)
    matches = list(pattern.finditer(content))
    if len(matches) != 1:
        raise ValueError(f"Missing or duplicate source section: {section['id']}")
    match = matches[0]
    before = match.group(2).strip()
    if before not in (section['sourceBefore'].strip(), section['sourceAfter'].strip()):
        raise ValueError(f"Changed source section: {section['id']}")
    return content[:match.start(2)] + '\n' + section['sourceAfter'] + '\n\n' + content[match.end(2):]


def catalog_sections(sections):
    result = {}
    for section in sections:
        source = section['sourceBefore']
        if source in result:
            previous = result[source]
            if any(previous.get(key, {}) != section.get(key, {}) for key in
                   ('sourceAfter', 'translations', 'preservedTranslations', 'previousTranslationHashes')):
                raise ValueError(f"Conflicting translations for shared source: {section['id']}")
        else:
            result[source] = section
    return list(result.values())


def decode_field(block):
    lines = block.splitlines()
    return ast.literal_eval(lines[0].split(' ', 1)[1]) + ''.join(
        ast.literal_eval(line) for line in lines[1:])


def replace_checked(text, before, after):
    if before in text:
        return text.replace(before, after)
    if after in text:
        return text
    raise ValueError('Reviewed translation no longer matches; manual review required')


def revise_catalog(content, locale, rules, sections=()):
    keys = {decode_field(match.group()) for match in FIELD.finditer(content) if match.group(1) == 'msgid'}
    for section in sections:
        if section['sourceBefore'] not in keys and section['sourceAfter'] not in keys:
            content = content.rstrip('\n') + '\n\n' + '\n'.join([
                '#. Reviewed sky culture section: ' + section['id'],
                'msgid ' + json.dumps(section['sourceAfter'], ensure_ascii=False), 'msgstr ""', ''])
            keys.add(section['sourceAfter'])
    active_rules = []
    active_sections = []
    counts = {'sourceKeys': 0, 'translations': 0, 'fallbacks': 0,
              'sectionKeys': 0, 'sectionTranslations': 0, 'sectionFallbacks': 0}

    def revise_field(match):
        nonlocal active_rules, active_sections
        field = match.group(1)
        original = decode_field(match.group())
        revised = original
        if field == 'msgid':
            active_sections = [section for section in sections
                               if original in (section['sourceBefore'], section['sourceAfter'])]
            if len(active_sections) > 1:
                raise ValueError('Ambiguous section revision')
            active_rules = [rule for rule in rules if rule['sourceBefore'] in original
                            or rule['sourceAfter'] in original]
            for rule in active_rules:
                revised = revised.replace(rule['sourceBefore'], rule['sourceAfter'])
            counts['sourceKeys'] += len(active_rules)
            for section in active_sections:
                revised = section['sourceAfter']
            counts['sectionKeys'] += len(active_sections)
        elif active_sections:
            section = active_sections[0]
            paragraphs = section['translations'].get(locale)
            if paragraphs:
                expected = '\n\n'.join(paragraphs)
                previous_hash = section['previousTranslationHashes'].get(locale)
                if original not in ('', expected) and hashlib.sha256(original.encode()).hexdigest() != previous_hash:
                    raise ValueError(f"Changed section translation: {locale}/{section['id']}")
                revised = expected
                counts['sectionTranslations'] += 1
                counts['translations'] += len(active_rules)
            elif original:
                preserved = section.get('preservedTranslations', {}).get(locale)
                if section['sourceBefore'] != section['sourceAfter'] or original != preserved:
                    raise ValueError(f"Unreviewed section translation: {locale}/{section['id']}")
            else:
                counts['sectionFallbacks'] += 1
                counts['fallbacks'] += len(active_rules)
        elif active_rules:
            if not revised:
                counts['fallbacks'] += len(active_rules)
            else:
                for rule in active_rules:
                    if rule['sourceBefore'] in revised or rule['sourceAfter'] in revised:
                        revised = replace_checked(revised, rule['sourceBefore'], rule['sourceAfter'])
                    elif locale in rule['translations']:
                        translation = rule['translations'][locale]
                        revised = replace_checked(revised, translation['before'], translation['after'])
                    else:
                        raise ValueError(f"Unreviewed nonempty translation: {locale}/{rule['id']}")
                counts['translations'] += len(active_rules)
        if revised == original:
            return match.group()
        return field + ' ""\n' + '\n'.join(json.dumps(line, ensure_ascii=False)
                                            for line in revised.splitlines(keepends=True))

    updated = FIELD.sub(revise_field, content)
    reviewed = {section['sourceAfter']: '\n\n'.join(section['translations'][locale])
                for section in sections if locale in section['translations']}
    blocks = updated.split('\n\n')
    for index, block in enumerate(blocks):
        fields = {match.group(1): decode_field(match.group()) for match in FIELD.finditer(block)}
        expected = reviewed.get(fields.get('msgid'))
        if expected is None or fields.get('msgstr') != expected:
            continue
        def remove_fuzzy(match):
            flags = [flag.strip() for flag in match.group(1).split(',') if flag.strip() != 'fuzzy']
            return '#, ' + ', '.join(flags) + '\n' if flags else ''
        blocks[index] = re.sub(r'^#, ([^\n]+)\n', remove_fuzzy, block, flags=re.M)
    return '\n\n'.join(blocks), counts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--patch-dir', type=Path)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--batches', nargs='+', help='Optional completed batch filenames, without .json')
    args = parser.parse_args()
    rules, sections = load_reviews(args.batches)
    unique_sections = catalog_sections(sections)
    shipped = set(json.loads((ROOT / 'data/skyculture_editorial_context.json').read_text())['languages'])
    for section in sections:
        required = set(section.get('requiredLanguages', shipped))
        if not required.issubset(section['translations']):
            raise ValueError(f"Missing shipped section languages: {section['id']}")
        for locale, paragraphs in section['translations'].items():
            if not paragraphs or any(not isinstance(part, str) or not part.strip() for part in paragraphs):
                raise ValueError(f"Invalid translated section: {locale}/{section['id']}")
    files = sorted((ROOT / 'skycultures').glob('*/description.md'))
    files += sorted((ROOT / 'po/stellarium-skycultures-descriptions').glob('*.po'))
    files += list((ROOT / 'po/stellarium-skycultures-descriptions').glob('*.pot'))
    patches = []
    coverage = {}
    for file in files:
        content = file.read_text()
        updated = content
        if file.suffix == '.md':
            for rule in rules:
                if file.parent.name == rule['culture']:
                    updated = replace_checked(updated, rule['sourceBefore'], rule['sourceAfter'])
            for section in sections:
                if file.parent.name == section['culture']:
                    updated = replace_section(updated, section)
        else:
            updated, coverage[file.stem] = revise_catalog(content, file.stem, rules, unique_sections)
            if coverage[file.stem]['sectionKeys'] != len(unique_sections):
                raise ValueError(f"Missing or duplicate section keys: {file}")
        if updated != content:
            diff = list(difflib.unified_diff(content.splitlines(), updated.splitlines(), n=3))[2:]
            patch = '\n'.join(['*** Begin Patch', f'*** Update File: {file}',
                               *['@@' if line.startswith('@@ ') else line for line in diff],
                               '*** End Patch']) + '\n'
            patches.append((file, patch))
    if args.patch_dir:
        args.patch_dir.mkdir(parents=True, exist_ok=True)
        for index, (file, patch) in enumerate(patches):
            (args.patch_dir / f'{index:03d}.patch').write_text(patch)
    for section in sections:
        missing = set(section['translations']) - set(coverage)
        if missing:
            raise ValueError(f"Missing translation catalogs: {sorted(missing)}")
    print(json.dumps({'changedFiles': len(patches), 'rules': len(rules), 'sections': len(sections),
                      'catalogs': len(coverage), 'coverage': coverage}, ensure_ascii=False))
    if args.check and patches:
        raise SystemExit('Reviewed revisions remain unapplied')


if __name__ == '__main__':
    main()
