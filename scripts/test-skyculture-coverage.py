import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('coverage', ROOT / 'scripts/audit-skyculture-coverage.py')
COVERAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COVERAGE)


class CoverageTests(unittest.TestCase):
    def test_matches_runtime_whitespace_and_comments(self):
        source = '# Name\r\n\r\n## Introduction\r\n\r\n leading<!-- hidden --> text \r\n\r\n'
        self.assertEqual(COVERAGE.source_sections(source), [('Introduction', ' leading text ')])

    def test_fuzzy_and_source_copy_are_not_translations(self):
        self.assertEqual(COVERAGE.translation_mode('Text', {}, 'fr'), 'source-fallback')
        self.assertEqual(COVERAGE.translation_mode('Text', {('', 'Text'): {'msgstr': 'Texte', 'fuzzy': True}}, 'fr'), 'fuzzy-fallback')
        self.assertEqual(COVERAGE.translation_mode('Text', {('', 'Text'): {'msgstr': 'Text'}}, 'fr'), 'source-copy')
        self.assertEqual(COVERAGE.translation_mode('Text', {}, 'en'), 'source-language')
        self.assertEqual(COVERAGE.translation_mode('Text', {}, 'en_GB'), 'source-language')

    def test_contextual_name_does_not_count_as_body(self):
        self.assertEqual(COVERAGE.translation_mode('Name', {('sky culture', 'Name'): {'msgstr': 'Nom'}}, 'fr'), 'source-fallback')

    def test_constellations_individual_html_and_whole_narration_differ(self):
        source = '##### First\n\nFirst text\n\n##### Second\n\nSecond text'
        entries = {('', 'First text'): {'msgstr': 'Premier texte'}}
        result = COVERAGE.section_coverage('Constellations', source, entries, 'fr')
        self.assertEqual(result['htmlUnits'], 2)
        self.assertEqual(result['htmlTranslatedUnits'], 1)
        self.assertEqual(result['htmlFallbackUnits'], 1)
        self.assertEqual(result['narrationMode'], 'source-fallback')

    def test_whole_section_has_precedence(self):
        source = '##### First\n\nFirst text'
        entries = {('', source): {'msgstr': '##### Premier\n\nPremier texte'}}
        result = COVERAGE.section_coverage('Constellations', source, entries, 'fr')
        self.assertEqual(result['htmlUnits'], 1)
        self.assertEqual(result['wholeSection'], 'translated-draft')

    def test_priority_list_matches_shared_resource(self):
        context = json.loads((ROOT / 'data/skyculture_editorial_context.json').read_text())
        self.assertEqual(COVERAGE.PRIORITY_LANGUAGES, context['priorityLanguages'])


if __name__ == '__main__':
    unittest.main()
