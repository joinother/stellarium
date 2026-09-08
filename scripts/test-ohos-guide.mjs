import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/pages/AstronomyGuide.ts', import.meta.url), 'utf8');
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
  const guideUI = page.slice(page.indexOf('  interactiveGuideShell()'), page.indexOf('  scriptFocusShell()'));
  assert.match(guideUI, /Scroll\(\)/);
  assert.doesNotMatch(guideUI, /maxLines|sendKey/);
  assert.doesNotMatch(guideUI, /this\.guideButton\([^\n]*\?/);
  assert.match(guideUI, /if \(this\.guideState\.phase === 'paused'\)/);
  assert.match(guideUI, /this\.guideButton\('btn_resume', 'resume'\)/);
  assert.match(guideUI, /minHeight: 52.*HitTestMode\.Default/);
  assert.match(page, /lastRequestId: this.guideLastRequest/);
  assert.match(page, /guideState.phase === 'exploring'/);
  const core = readFileSync(new URL('../src/scripting/StelScriptMgr.cpp', import.meta.url), 'utf8');
  assert.match(core, /restoreSessionState\(false\)/);
  assert.match(core, /if \(guidedSession\)\s*return false/);
});
