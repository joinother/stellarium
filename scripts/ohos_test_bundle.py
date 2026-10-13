"""Shared bundle-name resolution for the HarmonyOS device test scripts.

The tracked source of truth is ``harmonyos/AppScope/app.json5``. A local Debug
signing profile may use a different bundle name, so callers can override it via
``--bundle`` or the ``STELLARIUM_BUNDLE`` environment variable.
"""

import json
import os
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_FALLBACK = 'com.joinother.skyinstrument'


def default_bundle():
    """Return the bundle name to drive: env override -> app.json5 -> fallback."""
    override = os.environ.get('STELLARIUM_BUNDLE')
    if override:
        return override
    try:
        app = json.loads((_ROOT / 'harmonyos' / 'AppScope' / 'app.json5').read_text(encoding='utf-8'))
        return app['app']['bundleName']
    except (OSError, ValueError, KeyError, TypeError):
        return _FALLBACK
