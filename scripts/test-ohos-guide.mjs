import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/common/derive/AstronomyGuide.ts', import.meta.url), 'utf8');
const { GuidePlayer, ASTRONOMY_GUIDES } = await import(`data:text/javascript,${encodeURIComponent(stripTypeScriptTypes(source))}`);
const setup = (run = async () => ({ ok: true })) => {
  const calls = [];
  const player = new GuidePlayer(async (command, payload) => {
    calls.push([command, payload]);
    return run(command, payload);
  }, () => {});
  return { player, calls };
};

test('known guides only, one session, snapshot precedes mutations', async () => {
  const { player, calls } = setup();
  assert.equal((await player.start('unknown')).ok, false);
  assert.equal(calls.length, 0);
  assert.equal((await player.start('solar-neighbours')).ok, true);
  assert.equal(calls[0][0], 'beginGuidedSession');
  assert.equal(player.snapshot().phase, 'observing');
  assert.equal((await player.start('deep-sky-discovery')).ok, false);
  assert.equal(calls.filter(item => item[0] === 'beginGuidedSession').length, 1);
});

test('manual default, pause and exploration hold the clock', async () => {
  const { player } = setup();
  await player.start('solar-neighbours');
  player.tick(1);
  assert.equal(player.snapshot().remaining, 25);
  await player.action('auto-on');
  player.tick(1);
  assert.equal(player.snapshot().remaining, 24);
  await player.action('pause');
  player.tick(1);
  assert.equal(player.snapshot().remaining, 24);
  await player.action('resume');
  await player.action('explore');
  player.tick(1);
  assert.equal(player.snapshot().remaining, 24);
  assert.equal((await player.action('resume')).ok, false);
  await player.action('return');
  assert.equal(player.snapshot().phase, 'observing');
  assert.equal(player.snapshot().index, 0);
});

test('previous bounds, next and finish restore exactly once', async () => {
  const { player, calls } = setup();
  await player.start('deep-sky-discovery');
  assert.equal((await player.action('previous')).ok, false);
  await player.action('next');
  await player.action('previous');
  assert.equal(player.snapshot().index, 0);
  await player.go(2);
  await player.action('next');
  await player.stop();
  assert.equal(player.snapshot().active, false);
  assert.equal(calls.filter(item => item[0] === 'endGuidedSession').length, 1);
});

test('failed snapshot prevents mutation; failed step can be retried or exited', async () => {
  const blocked = setup(async () => ({ ok: false, error: 'busy' }));
  await blocked.player.start('solar-neighbours');
  assert.deepEqual(blocked.calls, [['beginGuidedSession', '']]);
  assert.equal(blocked.player.snapshot().active, false);
  let fail = true;
  const { player } = setup(async (command, payload) => ({ ok: !(fail && payload === 'Venus|selectOnly') }));
  await player.start('solar-neighbours');
  await player.action('next');
  assert.equal(player.snapshot().phase, 'error');
  assert.equal(player.snapshot().index, 1);
  fail = false;
  await player.action('retry');
  assert.equal(player.snapshot().phase, 'observing');
  await player.stop();
});

test('stop during in-flight step drains before restore and stops remaining commands', async () => {
  let release;
  const { player, calls } = setup(async (command) => {
    if (command === 'setAtmosphereFlag') await new Promise(resolve => { release = resolve; });
    return { ok: true };
  });
  const start = player.start('solar-neighbours');
  while (!release) await new Promise(resolve => setImmediate(resolve));
  const stop = player.stop();
  assert.equal((await player.action('next')).ok, false);
  release();
  await Promise.all([start, stop]);
  assert.equal(calls.at(-1)[0], 'endGuidedSession');
  assert.equal(calls.some(item => item[0] === 'searchObject'), false);
  assert.equal(player.snapshot().active, false);
});

test('failed restoration preserves active ownership and allows retry', async () => {
  let fail = true;
  const { player } = setup(async command => ({ ok: command !== 'endGuidedSession' || !fail }));
  await player.start('solar-neighbours');
  await player.stop();
  assert.equal(player.snapshot().active, true);
  assert.equal(player.snapshot().phase, 'error');
  fail = false;
  assert.equal((await player.stop()).ok, true);
});

test('manifest is offline data, not executable user code', () => {
  assert.equal(new Set(ASTRONOMY_GUIDES.map(item => item.id)).size, ASTRONOMY_GUIDES.length);
  for (const guide of ASTRONOMY_GUIDES) {
    assert.ok(guide.credit);
    for (const step of guide.steps) {
      assert.ok(step.fov > 0 && step.fov <= 360);
      assert.ok(step.seconds >= 20);
      assert.ok(!/https?:|eval\(/.test(JSON.stringify(step)));
    }
  }
});

test('guide bridge actions use implemented commands and atmosphere payloads', async () => {
  const { player, calls } = setup();
  await player.start('solar-neighbours');
  await player.action('closer');
  await player.action('wider');
  await player.stop();
  const core = readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8');
  const names = new Set([...core.matchAll(/commandName\s*==\s*"([A-Za-z][A-Za-z0-9_]*)"/g)].map(match => match[1]));
  for (const [command, payload] of calls) {
    assert.ok(names.has(command), command);
    if (command === 'setAtmosphereFlag') assert.match(payload, /^(atmosphere|landscape)\|0$/);
  }
});

test('UI and CLI share semantic player, scrollable text and actual result', () => {
  const page = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
  // Phase 6d 把 interactiveGuideShell 抽成 `panels/shell/InteractiveGuideShell.ets`；
  // UI 断言随之改读组件文件（导览 shell 本体），宿主只保留 `guideState.active` 分发。
  const guideShell = readFileSync(new URL('../harmonyos/ets-source/panels/shell/InteractiveGuideShell.ets', import.meta.url), 'utf8');
  assert.match(guideShell, /Scroll\(\)/);
  assert.doesNotMatch(guideShell, /maxLines|sendKey/);
  assert.doesNotMatch(guideShell, /GuideButton\(\{[^\n]*\?/);
  assert.match(guideShell, /if \(this\.guidePhase === 'paused'\)/);
  assert.match(guideShell, /GuideButton\(\{ label: 'btn_resume', action: 'resume'/);
  assert.match(guideShell, /minHeight: 52.*HitTestMode\.Default/);
  assert.match(guideShell, /guidePhase === 'exploring'/);
  // §9 P0 S6：导览引擎/请求序号/定时器迁入 capability/GuideController；
  // CLI 结果读取随之改经控制器 getter（宿主 publishGuideState）。
  assert.match(page, /lastRequestId: this\.guideCtl\(\)\.lastRequestId\(\)/);
  assert.match(page, /result: this\.guideCtl\(\)\.lastResult\(\)/);
  assert.match(page, /guideState\.active/);
  const core = readFileSync(new URL('../src/scripting/StelScriptMgr.cpp', import.meta.url), 'utf8');
  assert.match(core, /restoreSessionState\(false\)/);
  assert.match(core, /if \(guidedSession\)\s*return false/);
  assert.match(core, /clearGuideOverlayLines\(\)/);
  assert.match(core, /sessionState\.skyCultureID/);
});

test('all curated guides emit valid core commands, complete i18n keys, and deterministic step scenes', async () => {
  assert.ok(ASTRONOMY_GUIDES.length >= 11, `expected >= 11 guides, got ${ASTRONOMY_GUIDES.length}`);
  const i18n = readFileSync(new URL('../harmonyos/ets-source/capability/I18n.ets', import.meta.url), 'utf8');
  const core = readFileSync(new URL('../src/StelMainView.cpp', import.meta.url), 'utf8');
  const names = new Set([...core.matchAll(/commandName\s*==\s*"([A-Za-z][A-Za-z0-9_]*)"/g)].map(match => match[1]));
  const categories = new Set(['stargazing', 'solar_system', 'deep_sky', 'events', 'sky_culture']);

  for (const guide of ASTRONOMY_GUIDES) {
    assert.ok(categories.has(guide.category), `invalid category on ${guide.id}: ${guide.category}`);
    assert.ok(i18n.includes(`'${guide.title}':`), `missing i18n title ${guide.title}`);
    assert.ok(i18n.includes(`'${guide.summary}':`), `missing i18n summary ${guide.summary}`);
    assert.ok(i18n.includes(`'${guide.credit}':`), `missing i18n credit ${guide.credit}`);
    for (const step of guide.steps) {
      assert.ok(i18n.includes(`'${step.text}':`), `missing i18n text ${step.text}`);
      if (step.title.startsWith('guide_')) {
        assert.ok(i18n.includes(`'${step.title}':`), `missing i18n step title ${step.title}`);
      }
    }
    const { player, calls } = setup();
    assert.equal((await player.start(guide.id)).ok, true, guide.id);
    for (let i = 1; i < guide.steps.length; ++i) {
      assert.equal((await player.action('next')).ok, true, `${guide.id}[${i}]`);
    }
    assert.equal((await player.stop()).ok, true, `${guide.id} stop`);
    for (const [command] of calls) {
      assert.ok(names.has(command), `unknown command ${command} in ${guide.id}`);
    }
  }
});

test('star-hopping, eclipses, sky-cultures, and planetary Sun guides emit scene overrides and overlay arcs', async () => {
  // Star-hopping: stop 0 has no lines (clears overlay), stop 1 emits Merak|Dubhe|Polaris, stop 5 closes Summer Triangle
  const summer = setup();
  await summer.player.start('summer-star-hopping');
  assert.ok(summer.calls.some(([c, p]) => c === 'setLocation' && p.startsWith('Taipei|')));
  assert.ok(summer.calls.some(([c, p]) => c === 'setAtmosphereFlag' && p === 'atmosphere|1'));
  assert.ok(summer.calls.some(([c, p]) => c === 'setGuideOverlayLines' && p === ''));
  await summer.player.go(1);
  assert.ok(summer.calls.some(([c, p]) => c === 'setGuideOverlayLines' && p === 'Merak|Dubhe|Polaris'));
  await summer.player.go(5);
  assert.ok(summer.calls.some(([c, p]) => c === 'setGuideOverlayLines' && p === 'Vega|Deneb|Altair|Vega'));
  await summer.player.stop();

  // Sky cultures: switches sky culture per stop
  const cultures = setup();
  await cultures.player.start('world-sky-cultures');
  await cultures.player.go(1);
  assert.ok(cultures.calls.some(([c, p]) => c === 'setSkyCulture' && p === 'chinese'));
  await cultures.player.stop();

  // Sun across planets: teleports observer planet per stop
  const sun = setup();
  await sun.player.start('sun-across-planets');
  assert.ok(sun.calls.some(([c, p]) => c === 'setObserverPlanet' && p === 'Mercury'));
  await sun.player.go(6);
  assert.ok(sun.calls.some(([c, p]) => c === 'setObserverPlanet' && p === 'Pluto'));
  await sun.player.stop();
});
