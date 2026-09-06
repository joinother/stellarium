import argparse
import ast
import hashlib
import json
from pathlib import Path
import re


def read_catalog(file):
    entries = []
    entry = {}
    field = None
    for number, line in enumerate(file.read_text(encoding='utf-8').splitlines() + [''], 1):
        if not line.strip():
            if entry.get('msgid'):
                entries.append(entry)
            entry = {}
            field = None
        elif line.startswith('#,'):
            entry['fuzzy'] = 'fuzzy' in line
        elif line.startswith(('msgid ', 'msgstr ', 'msgctxt ')):
            field, literal = line.split(' ', 1)
            entry[field] = ast.literal_eval(literal)
            if field == 'msgid':
                entry['line'] = number
        elif line.startswith('"') and field:
            entry[field] += ast.literal_eval(line)
    return entries


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    patterns = {
        'geographic-context': r'\b(?:Tibet(?:an)?|Xizang|Xinjiang|Taiwan|Hong Kong|Macau|Macao)\b|西藏|新疆|台湾|臺灣|香港|澳门|澳門',
        'cultural-comparison': r'\b(?:Western|Eurocentric|primitive|civilized|uncivilized|superior|inferior|colonial\w*|coloniz\w*)\b|西方|殖民|原始|落后|落後|优越|優越',
        'author-attribution': r'\b(?:I|we|our|my|ours|mine|us)\b|我(?:们|們)?|私(?:たち)?|わたし|저희|우리|\b(?:je|nous|notre|ich|wir|unser|я|мы|наш)\b',
    }
    compiled = {key: re.compile(value, re.I) for key, value in patterns.items()}
    cultures = []
    source_sections = {}
    for file in sorted((root / 'skycultures').glob('*/description.md')):
        content = file.read_text(encoding='utf-8')
        sections = re.split(r'^## +(.+)$', content, flags=re.M)
        for index in range(1, len(sections), 2):
            source_sections.setdefault(sections[index + 1].strip(), []).append({
                'culture': file.parent.name, 'section': sections[index]})
        candidates = [{'line': number, 'reasons': [key for key, pattern in compiled.items() if pattern.search(line)],
                       'text': line} for number, line in enumerate(content.splitlines(), 1)
                      if any(pattern.search(line) for pattern in compiled.values())]
        cultures.append({'id': file.parent.name, 'path': str(file.relative_to(root)),
                         'sha256': hashlib.sha256(file.read_bytes()).hexdigest(),
                         'reviewStatus': 'pending', 'candidates': candidates})
    catalogs = []
    for file in sorted((root / 'po/stellarium-skycultures-descriptions').glob('*.po')):
        entries = read_catalog(file)
        current_translations = {entry['msgid'].strip() for entry in entries
                                if entry.get('msgstr') and not entry.get('fuzzy', False)
                                and entry['msgid'].strip() in source_sections}
        candidates = []
        for entry in entries:
            reasons = [key for key, pattern in compiled.items()
                       if pattern.search(entry['msgid']) or pattern.search(entry.get('msgstr', ''))]
            if reasons:
                candidates.append({'line': entry['line'], 'reasons': reasons,
                                   'sourceHash': hashlib.sha256(entry['msgid'].encode()).hexdigest(),
                                   'sourceExcerpt': entry['msgid'][:280],
                                   'translationExcerpt': entry.get('msgstr', '')[:280],
                                   'cultures': source_sections.get(entry['msgid'].strip(), []),
                                   'fuzzy': entry.get('fuzzy', False), 'reviewStatus': 'pending'})
        catalogs.append({'locale': file.stem, 'path': str(file.relative_to(root)),
                         'sha256': hashlib.sha256(file.read_bytes()).hexdigest(),
                         'entries': len(entries),
                         'currentSourceSections': len(source_sections),
                         'currentTranslatedSections': len(current_translations),
                         'currentSectionFallbacks': len(source_sections) - len(current_translations),
                         'missing': sum(not entry.get('msgstr') for entry in entries),
                         'fuzzy': sum(entry.get('fuzzy', False) for entry in entries),
                         'reviewStatus': 'pending', 'candidates': candidates})
    report = {'schemaVersion': 1,
              'scope': 'All source descriptions and all description PO catalogs, including unshipped locales',
              'limitations': 'Keyword matches are review candidates, not violations. No matches do not establish semantic consistency or approval. Historical colonialism and author quotations require context, not automatic removal.',
              'cultures': cultures, 'catalogs': catalogs}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'cultures': len(cultures), 'locales': len(catalogs),
                      'sourceCandidates': sum(len(item['candidates']) for item in cultures),
                      'translationCandidates': sum(len(item['candidates']) for item in catalogs),
                      'missingTranslations': sum(item['missing'] for item in catalogs)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
