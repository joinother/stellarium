import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')
const mainView = read('src/StelMainView.cpp')
const moduleMgr = read('src/core/StelModuleMgr.cpp')

test('all bundled plugins load synchronously behind the startup splash', () => {
  // The OHOS-only deferred queue and its MeteorShowers preload must stay removed:
  // the first interactive frame must already have every plugin's persisted state.
  assert.doesNotMatch(mainView, /Defer heavy optional plugins/)
  assert.doesNotMatch(mainView, /QTimer::singleShot\(1800/)
  assert.doesNotMatch(mainView, /deferred plugin & script initialization/)
  assert.match(mainView, /stelApp->initPlugIns\(\);/)
  // Satellite command handlers no longer need the lazy-load fallback.
  assert.doesNotMatch(mainView, /loadPlugin\(QStringLiteral\("Satellites"\)\)/)
})

test('the module manager keeps loading bundled plugins at startup', () => {
  assert.match(moduleMgr, /Q_UNUSED\(iter\.value\(\)\.info\.startByDefault\);/)
  assert.match(moduleMgr, /iter->loadAtStartup = true;/)
  assert.match(moduleMgr, /Q_UNUSED\(b\);/)
  assert.match(moduleMgr, /conf->setValue\("plugins_load_at_startup\/"\+key, true\);/)
})
