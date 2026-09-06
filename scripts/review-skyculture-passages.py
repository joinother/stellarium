import argparse
import ast
import difflib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / 'docs/harmonyos/skyculture-passage-revisions.json'
FIELD = re.compile(r'^(msgid|msgstr) (".*")(?:\n".*")*', re.M)


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


def revise_catalog(content, locale, rules):
    active_rules = []
    counts = {'sourceKeys': 0, 'translations': 0, 'fallbacks': 0}

    def revise_field(match):
        nonlocal active_rules
        field = match.group(1)
        original = decode_field(match.group())
        revised = original
        if field == 'msgid':
            active_rules = [rule for rule in rules if rule['sourceBefore'] in original
                            or rule['sourceAfter'] in original]
            for rule in active_rules:
                revised = revised.replace(rule['sourceBefore'], rule['sourceAfter'])
            counts['sourceKeys'] += len(active_rules)
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

    return FIELD.sub(revise_field, content), counts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--patch-dir', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    rules = json.loads(RULES.read_text())['rules']
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
        else:
            updated, coverage[file.stem] = revise_catalog(content, file.stem, rules)
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
    print(json.dumps({'changedFiles': len(patches), 'rules': len(rules),
                      'catalogs': len(coverage), 'coverage': coverage}, ensure_ascii=False))
    if args.check and patches:
        raise SystemExit('Reviewed revisions remain unapplied')


if __name__ == '__main__':
    main()
