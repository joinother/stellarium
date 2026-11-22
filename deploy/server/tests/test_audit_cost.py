import importlib.machinery
import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch


ROOT = pathlib.Path(__file__).resolve().parents[1]


def load_script(name):
    loader = importlib.machinery.SourceFileLoader(name, str(ROOT / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class AuditCostTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.audit = load_script('skyinstrument-content-audit')
        self.audit.AI_USAGE = str(self.root / 'usage.json')
        self.audit.JUDGMENT_CACHE = str(self.root / 'judgments.json')
        self.audit.AUDIT_CONF = str(self.root / 'absent.conf')
        self.audit.LEXICON = str(self.root / 'words.json')
        self.audit.LEXICON_EXCLUDE = str(self.root / 'exclude.txt')

    def test_legacy_endpoint_config_cannot_trigger_weather(self):
        config = self.root / 'endpoints.conf'
        config.write_text('/v1/world\n/v1/grid\n/v1/week\n')
        self.audit.API_CONF = str(config)
        self.assertEqual(self.audit.api_endpoints(), ['/healthz'])

    def test_status_page_not_in_either_content_discovery(self):
        config = self.root / 'nginx.conf'
        config.write_text('alias /srv/skyinstrument/status/;\nroot /site;\n')
        for module, function in [(self.audit, 'discover_served_dirs'),
                                 (load_script('skyinstrument-quickcheck'), 'served_dirs')]:
            module.NGINX_CONF = str(config)
            module.SITE_DIR = '/site'
            with patch.object(module.os.path, 'isdir', return_value=True):
                self.assertEqual(getattr(module, function)(), ['/site'])

    def test_cache_reuses_verdict_but_content_and_rules_invalidate(self):
        source = self.root / 'page.html'
        source.write_text('first')
        self.audit.ABS_BY_REL['page'] = str(source)
        calls = []

        def invoke():
            calls.append(True)
            return {'verdict': 'false_positive'}

        for unused in range(2):
            self.audit.cached_judgment('rule', 'page', 'same', invoke)
        self.assertEqual(len(calls), 1)
        source.write_text('changed')
        self.audit.cached_judgment('rule', 'page', 'same', invoke)
        pathlib.Path(self.audit.LEXICON).write_text('new rules')
        self.audit.cached_judgment('rule', 'page', 'same', invoke)
        self.assertEqual(len(calls), 3)

    def test_control_files_use_content_digest(self):
        watcher = load_script('skyinstrument-quickcheck')
        source = self.root / 'generator'
        source.write_text('first')
        watcher.CONTROL_FILES = (str(source),)
        with patch.object(watcher, 'served_dirs', return_value=[]):
            before = watcher.snapshot()
            source.write_text('other')
            after = watcher.snapshot()
        self.assertEqual(watcher.changed(before, after), [str(source)])

    def test_unavailable_verdict_is_not_cached(self):
        calls = []
        for unused in range(2):
            self.audit.cached_judgment('rule', 'page', '', lambda: calls.append(True))
        self.assertEqual(len(calls), 2)

    def test_budget_reserves_before_calls_and_survives_reload(self):
        self.audit.AI_MAX_CALLS_PER_DAY = 2
        self.assertTrue(self.audit.reserve_ai_call())
        self.assertTrue(self.audit.reserve_ai_call())
        self.assertFalse(self.audit.reserve_ai_call())
        self.assertEqual(self.audit.load_usage()[1]['calls'], 2)
        self.audit.AI_USAGE = str(self.root / 'missing' / 'nested' / 'usage.json')
        with patch.object(self.audit.os, 'replace', side_effect=OSError('disk full')):
            self.assertFalse(self.audit.reserve_ai_call())

    def test_missing_ai_result_is_not_a_clean_review(self):
        source = self.root / 'page.html'
        source.write_text('<p>' + 'sample page content ' * 90 + '</p>')
        with patch.object(self.audit, 'judge_free', return_value=None):
            self.assertIsNone(self.audit.review_full_page(str(source), 'page'))
        with patch.object(self.audit, 'judge_free', return_value={'verdict': 'ok'}):
            self.assertEqual(self.audit.review_full_page(str(source), 'page')['verdict'], 'ok')

    def test_corrupt_ai_usage_blocks_new_call(self):
        pathlib.Path(self.audit.AI_USAGE).write_text('{invalid')
        self.assertFalse(self.audit.reserve_ai_call())
        self.assertEqual(pathlib.Path(self.audit.AI_USAGE).read_text(), '{invalid')

    def test_cache_survives_past_24h_and_expires_after_7d(self):
        source = self.root / 'page.html'
        source.write_text('stable page')
        self.audit.ABS_BY_REL['page'] = str(source)
        calls = []

        def invoke():
            calls.append(True)
            return {'verdict': 'ok'}

        with patch.object(self.audit.time, 'time', return_value=1_700_000_000.0):
            self.audit.cached_judgment('free', 'page', 'seg', invoke)
        # 3 days later with identical content/rules: still hits cache (no daily fullscan re-billing).
        with patch.object(self.audit.time, 'time', return_value=1_700_000_000.0 + 3 * 86400):
            self.audit.cached_judgment('free', 'page', 'seg', invoke)
        self.assertEqual(len(calls), 1)
        # After 7 days TTL: expires and re-checks.
        with patch.object(self.audit.time, 'time', return_value=1_700_000_000.0 + 7 * 86400 + 10):
            self.audit.cached_judgment('free', 'page', 'seg', invoke)
        self.assertEqual(len(calls), 2)

    def test_mirror_machine_files_skip_free_ai_review(self):
        self.assertTrue(self.audit.should_skip_free_ai_review('tle-mirror/v1/manifest.json'))
        self.assertTrue(self.audit.should_skip_free_ai_review('tle-mirror/v1/calendar/manifest.json'))
        self.assertTrue(self.audit.should_skip_free_ai_review('tle-mirror/v1/catalogs/mpc/comets.txt'))
        self.assertFalse(self.audit.should_skip_free_ai_review('skyinstrument/website/current/index.html'))
        self.assertFalse(self.audit.should_skip_free_ai_review('tle-mirror/v1/injected.html'))

    def test_quickcheck_ignores_periodic_mirror_status_json(self):
        watcher = load_script('skyinstrument-quickcheck')
        status_file = self.root / 'status.json'
        status_file.write_text('{"checkedAt":"t1"}')
        normal_file = self.root / 'page.html'
        normal_file.write_text('<p>hi</p>')
        watcher.CONTROL_FILES = ()
        watcher.IGNORED_DYNAMIC_FILES = (str(status_file),)
        with patch.object(watcher, 'served_dirs', return_value=[str(self.root)]):
            snap = watcher.snapshot()
        self.assertNotIn(str(status_file), snap)
        self.assertIn(str(normal_file), snap)


if __name__ == '__main__':
    unittest.main()
