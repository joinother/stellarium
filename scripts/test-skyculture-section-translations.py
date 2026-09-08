import hashlib
import importlib.util
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('passages', ROOT / 'scripts/review-skyculture-passages.py')
PASSAGES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PASSAGES)


class SectionTranslationTests(unittest.TestCase):
    def setUp(self):
        self.section = {
            'id': 'example', 'sourceBefore': 'Before', 'sourceAfter': 'After',
            'translations': {'fr': ['Préliminaire.', 'Auteur.', 'Échanges.']},
            'previousTranslationHashes': {'fr': hashlib.sha256('Ancien'.encode()).hexdigest()},
        }

    def catalog(self, source, translation):
        return f'msgid {json.dumps(source)}\nmsgstr {json.dumps(translation)}\n'

    def test_fills_empty_translation_and_is_idempotent(self):
        updated, counts = PASSAGES.revise_catalog(self.catalog('Before', ''), 'fr', [], [self.section])
        self.assertEqual(counts['sectionTranslations'], 1)
        self.assertIn('Échanges.', updated)
        self.assertEqual(PASSAGES.revise_catalog(updated, 'fr', [], [self.section])[0], updated)

    def test_accepts_only_known_previous_translation(self):
        updated, _ = PASSAGES.revise_catalog(self.catalog('Before', 'Ancien'), 'fr', [], [self.section])
        self.assertIn('Préliminaire.', updated)
        with self.assertRaises(ValueError):
            PASSAGES.revise_catalog(self.catalog('Before', 'User edit'), 'fr', [], [self.section])

    def test_untranslated_locale_stays_an_explicit_fallback(self):
        updated, counts = PASSAGES.revise_catalog(self.catalog('Before', ''), 'other', [], [self.section])
        self.assertIn('msgstr ""', updated)
        self.assertEqual(counts['sectionFallbacks'], 1)
        with self.assertRaises(ValueError):
            PASSAGES.revise_catalog(self.catalog('Before', 'Keep me'), 'other', [], [self.section])

    def test_reviewed_examples_use_direct_descriptions(self):
        rules, sections = PASSAGES.load_reviews()
        indexed = {rule['id']: rule for rule in rules}
        self.assertEqual(indexed['sternenkarten_standard_scope']['sourceAfter'],
                         "Modern astronomy uses the IAU's agreed constellation names and boundaries for locating objects.")
        self.assertEqual(indexed['tukano_knowledge_not_deficiency']['translations']['zh_CN']['after'],
                         '研究者记录了图卡诺人组织星空知识的方式。')
        self.assertNotIn('not a ranking', indexed['modern_chinese_asterism_purpose']['sourceAfter'])
        section = next(item for item in sections if item['culture'] == 'modern_sternenkarten')
        self.assertNotIn('並不意味', ''.join(section['translations']['zh_TW']))
        self.assertNotIn('基準になるわけ', ''.join(section['translations']['ja']))
        self.assertEqual(len(section['translations']), 16)

    def test_unrelated_catalog_entries_are_unchanged(self):
        unrelated = '#. Reference\nmsgctxt "context"\nmsgid "Unrelated"\nmsgstr "Keep me"\n'
        combined = self.catalog('Before', '') + '\n' + unrelated
        updated, _ = PASSAGES.revise_catalog(combined, 'fr', [], [self.section])
        self.assertTrue(updated.endswith(unrelated))

    def test_preserves_nonpriority_translation_only_for_unchanged_source(self):
        self.section['sourceAfter'] = 'Before'
        self.section['preservedTranslations'] = {'other': 'Keep me'}
        original = self.catalog('Before', 'Keep me')
        self.assertEqual(PASSAGES.revise_catalog(original, 'other', [], [self.section])[0], original)
        self.section['sourceAfter'] = 'After'
        with self.assertRaises(ValueError):
            PASSAGES.revise_catalog(original, 'other', [], [self.section])

    def test_removes_fuzzy_only_from_exact_reviewed_section(self):
        source = '#, fuzzy, no-c-format\n' + self.catalog('Before', 'Ancien')
        unrelated = '\n#, fuzzy\n' + self.catalog('Unrelated', 'Untouched')
        updated, _ = PASSAGES.revise_catalog(source + unrelated, 'fr', [], [self.section])
        self.assertTrue(updated.startswith('#, no-c-format\n'))
        self.assertTrue(updated.endswith(unrelated))

    def test_shared_source_requires_identical_translations(self):
        duplicate = dict(self.section, id='duplicate', culture='another')
        self.assertEqual(len(PASSAGES.catalog_sections([self.section, duplicate])), 1)
        duplicate['translations'] = {'fr': ['Different']}
        with self.assertRaises(ValueError):
            PASSAGES.catalog_sections([self.section, duplicate])

    def test_missing_current_source_key_is_added_without_removing_history(self):
        history = self.catalog('Obsolete source', 'Historic translation')
        updated, counts = PASSAGES.revise_catalog(history, 'fr', [], [self.section])
        self.assertTrue(updated.startswith(history))
        self.assertEqual(counts['sectionKeys'], 1)
        self.assertIn('Préliminaire.', updated)
        self.assertEqual(PASSAGES.revise_catalog(updated, 'fr', [], [self.section])[0], updated)

    def test_source_section_trailing_space_is_normalised_without_touching_next_section(self):
        self.section['section'] = 'Introduction'
        content = '# Name\n\n## Introduction\n\nBefore \n\n## Authors\n\nKeep author.\n'
        updated = PASSAGES.replace_section(content, self.section)
        self.assertEqual(updated, content.replace('Before ', 'After'))
        self.assertEqual(PASSAGES.replace_section(updated, self.section), updated)
        with self.assertRaises(ValueError):
            PASSAGES.replace_section(content.replace('Before ', 'User edit'), self.section)

    def test_batch_translations_preserve_images_citations_and_english_source(self):
        _, sections = PASSAGES.load_reviews()
        for section in sections:
            source = section['sourceAfter']
            images = re.findall(r'<img[^>]+src=[\"\']([^\"\']+)', source)
            citations = set(re.findall(r'\[#\d+\]', source))
            self.assertEqual('\n\n'.join(section['translations']['en']), source, section['id'])
            for locale, parts in section['translations'].items():
                translated = '\n\n'.join(parts)
                for image in images:
                    self.assertIn(image, translated, f"{section['id']}/{locale}")
                self.assertTrue(citations.issubset(re.findall(r'\[#\d+\]', translated)), f"{section['id']}/{locale}")

    def test_current_catalogs_match_all_shipped_translations(self):
        sections = json.loads(PASSAGES.SECTIONS.read_text())['sections']
        shipped = json.loads((ROOT / 'data/skyculture_editorial_context.json').read_text())['languages']
        self.assertEqual(len(shipped), 43)
        for section in sections:
            self.assertTrue(set(shipped).issubset(section['translations']))
            for locale, paragraphs in section['translations'].items():
                self.assertEqual(len(paragraphs), 3, locale)
                self.assertIn('2019', paragraphs[1], locale)
                self.assertTrue('Zotti' in paragraphs[1] or 'Цотти' in paragraphs[1] or 'Цотті' in paragraphs[1], locale)
                if locale != 'en':
                    self.assertNotEqual('\n\n'.join(paragraphs), section['sourceAfter'], locale)
                file = ROOT / 'po/stellarium-skycultures-descriptions' / f'{locale}.po'
                content = file.read_text()
                updated, counts = PASSAGES.revise_catalog(content, locale, [], [section])
                self.assertEqual(updated, content, locale)
                self.assertEqual(counts['sectionTranslations'], 1, locale)


if __name__ == '__main__':
    unittest.main()
