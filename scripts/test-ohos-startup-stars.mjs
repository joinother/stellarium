import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const read = name => readFileSync(new URL(`../harmonyos/ets-source/${name}`, import.meta.url), 'utf8');
const geometry = await import(`data:text/javascript,${encodeURIComponent(stripTypeScriptTypes(read('pages/StartupStarGeometry.ts')))}`);

test('particle positions converge exactly and stay finite on phone and Pad', () => {
  for (const [width, height] of [[360, 780], [1280, 800], [800, 1280]]) {
    const target = { x: width / 2, y: height / 2 };
    for (let index = 0; index < 1100; index++) {
      for (const elapsed of [0, 450, 950, 1800, 2600, 60000]) {
        const point = geometry.startupParticle(index, target, width, height, elapsed);
        assert.ok(Number.isFinite(point.x) && Number.isFinite(point.y));
        if (elapsed >= 2600) assert.deepEqual(point, target);
      }
    }
  }
});

test('morph easing has bounded endpoints and is monotonic', () => {
  assert.equal(geometry.startupEase(-1), 0);
  assert.equal(geometry.startupEase(2), 1);
  let previous = 0;
  for (let step = 0; step <= 100; step++) {
    const value = geometry.startupEase(step / 100);
    assert.ok(value >= previous && value <= 1);
    previous = value;
  }
});

test('star appearances have rare bright stars and balanced cool, white and warm colours', () => {
  const appearances = Array.from({ length: 900 }, (_, index) => geometry.startupAppearance(index));
  assert.equal(new Set(appearances.map(star => star.color)).size, 3);
  assert.ok(appearances.filter(star => star.radius < 0.7).length > 500);
  assert.ok(appearances.filter(star => star.radius > 1.35).length < 120);
  assert.ok(Math.max(...appearances.map(star => star.radius)) > 1.6);
  assert.ok(Math.min(...appearances.map(star => star.brightness)) < 0.2);
  assert.ok(Math.max(...appearances.map(star => star.brightness)) > 0.9);
  assert.ok(new Set(appearances.map(star => star.period)).size > 800);
});

test('slow loading keeps the swarm moving until native readiness, then settles exactly', () => {
  const target = { x: 500, y: 300 };
  const earlier = geometry.startupParticle(50, target, 1000, 600, 10000, -1);
  const later = geometry.startupParticle(50, target, 1000, 600, 12000, -1);
  assert.notDeepEqual(earlier, later);
  assert.notDeepEqual(later, target);
  assert.deepEqual(geometry.startupParticle(50, target, 1000, 600, 15000, 1500), target);
  assert.match(read('pages/StartupSky.ets'), /this.skyPrepared && this.assemblyElapsed >= STARTUP_REVEAL_AT_MS/);
});

test('independent drift fills the centre, varies direction and never jumps between frames', () => {
  const target = { x: 500, y: 300 };
  let central = 0;
  let movingLeft = 0;
  let movingRight = 0;
  for (let index = 0; index < 900; index++) {
    const before = geometry.startupDrift(index, 1000, 600, 10000);
    const after = geometry.startupDrift(index, 1000, 600, 10033);
    if (Math.hypot(before.x - target.x, before.y - target.y) < 100) central++;
    if (after.x < before.x) movingLeft++;
    if (after.x > before.x) movingRight++;
    assert.ok(Math.hypot(after.x - before.x, after.y - before.y) < 1);
    assert.deepEqual(before, geometry.startupDrift(index, 1000, 600, 10000));
    assert.deepEqual(geometry.startupParticle(index, target, 1000, 600, 30000, geometry.STARTUP_REVEAL_AT_MS), target);
  }
  assert.ok(central > 20 && movingLeft > 200 && movingRight > 200);
});

test('one persistent startup canvas spans consent and Qt startup without old splash', () => {
  const root = read('pages/ApplicationRoot.ets');
  assert.equal((root.match(/StartupSky\(\)/g) ?? []).length, 1);
  assert.match(root, /if \(this.loadingVisible\)/);
  assert.match(root, /stellariumStartupSkyReady/);
  const page = read('pages/MainWindowNativeNode.ets');
  assert.doesNotMatch(page, /splashStars|splashOpacity|正在唤醒星空/);
  assert.match(page, /AppStorage.setOrCreate\('stellariumStartupSkyReady', true\)/);
  assert.doesNotMatch(read('pages/PrivacyBootstrap.ets'), /app.media.app_icon|backgroundColor/);
});

test('depth and release stay continuous, bounded and leave the completed title readable first', () => {
  assert.equal(geometry.startupReveal(geometry.STARTUP_REVEAL_AT_MS), 0);
  assert.equal(geometry.startupReveal(geometry.STARTUP_REVEAL_AT_MS + geometry.STARTUP_REVEAL_MS), 1);
  for (const [width, height] of [[360, 780], [1280, 800], [800, 1280]]) {
    const target = { x: width * 0.55, y: height * 0.48 };
    for (let index = 0; index < 900; index++) {
      assert.deepEqual(geometry.startupReleasePoint(index, target, width, height, 0), target);
      const released = geometry.startupReleasePoint(index, target, width, height, 1);
      assert.ok(Math.hypot(released.x - target.x, released.y - target.y) < Math.hypot(width, height) * 0.09);
      const before = geometry.startupDepthPoint(index, width, height, 4999);
      const after = geometry.startupDepthPoint(index, width, height, 5000);
      assert.ok(Math.hypot(after.x - before.x, after.y - before.y) < 0.1);
      const ending = geometry.startupParticle(index, target, width, height, 12000,
        geometry.STARTUP_GATHER_MS + geometry.STARTUP_STAGGER_MS);
      assert.ok(Math.hypot(ending.x - target.x, ending.y - target.y) < 0.01);
    }
  }
});

test('startup art is local, bounded, and stops in background or on removal', () => {
  const sky = read('pages/StartupSky.ets');
  assert.doesNotMatch(sky, /libqohos|callNative|deviceInfo|sensor\.|geoLocation|http\.|fetch\(/);
  assert.match(sky, /candidates.length \/ 900/);
  assert.match(sky, /this.stopMotion\(\)\s+if \(!this.ready \|\| !this.foreground\) return/);
  assert.match(sky, /aboutToDisappear\(\): void \{\s+this.ready = false\s+this.stopMotion\(\)/);
  assert.match(sky, /app.string.QAbility_label/);
  assert.match(sky, /星象仪/);
  assert.match(sky, /星象儀/);
});

test('native cover removal is tied to a painted frame and supported manifest option', () => {
  assert.match(read('pages/StartupSky.ets'), /postFrameCallback\(new StartupFirstFrame\(\)\)/);
  assert.match(read('qability/QAbility.ets'), /pendingWindowStage.removeStartingWindow\(\)/);
  const manifest = readFileSync(new URL('../harmonyos/module.json5', import.meta.url), 'utf8');
  assert.match(manifest, /"name": "enable.remove.starting.window", "value": "true"/);
});

test('quiet localized loading caption replaces ellipsis with a small trailing official spinner', () => {
  const root = read('pages/ApplicationRoot.ets');
  assert.doesNotMatch(root, /backgroundColor\('#8505070F'\)/);
  assert.match(root, /LoadingProgress\(\).width\(14\).height\(14\)/);
  assert.match(root, /enableLoading\(this.foreground\)/);
  assert.ok(root.indexOf('Text(this.loadingLabel)') < root.indexOf('LoadingProgress()'));
  assert.match(root, /translate\(\{ y: 88 \}\)/);
  assert.match(root, /startupLoadingLabel\(I18n.t\('msg_loading'\)\)/);
  assert.match(root, /Watch\('onLanguageChanged'\)/);
  assert.match(root, /if \(this.nativeAllowed\)/);
});

test('loading punctuation is removed locally without changing translated words', () => {
  for (const [input, expected] of [['正在加载…', '正在加载'], ['Loading...', 'Loading'],
    ['Chargement… ', 'Chargement'], ['جار التحميل...', 'جار التحميل'], ['読み込み中', '読み込み中']]) {
    assert.equal(geometry.startupLoadingLabel(input), expected);
  }
});

test('gather and release have gentle endpoint acceleration and an explicit readable hold', () => {
  const endpointStep = 0.001;
  assert.ok(geometry.startupEase(endpointStep) < 1e-7);
  assert.ok(1 - geometry.startupEase(1 - endpointStep) < 1e-7);
  assert.ok(geometry.STARTUP_GATHER_MS >= 1200);
  assert.ok(geometry.STARTUP_REVEAL_MS >= 1000);
  const settledAt = geometry.STARTUP_GATHER_MS + geometry.STARTUP_STAGGER_MS;
  assert.ok(geometry.STARTUP_REVEAL_AT_MS - settledAt >= 200);
  assert.equal(geometry.startupReveal(settledAt + 100), 0);
  assert.match(read('pages/ApplicationRoot.ets'), /duration: STARTUP_REVEAL_MS/);
});

test('letter particles avoid a square raster and have a bounded sampling budget', () => {
  const sky = read('pages/StartupSky.ets');
  assert.match(sky, /sample <= 30000 && candidates.length < 900/);
  assert.match(sky, /pen.arc\(point.x, point.y, radius/);
  assert.doesNotMatch(sky, /fillRect\(point.x, point.y/);
  assert.match(sky, /maximumX - minimumX/);
  assert.match(sky, /maximumY - minimumY/);
  assert.match(sky, /radii\[group\] \* \(1 \+ emphasis \* 0.5\)/);
  assert.match(sky, /Math.min\(1, brightness\[group\] \+ emphasis \* 0.2\)/);
});

test('reveal requires letter formation and stable viewport instead of a fixed loading delay', () => {
  assert.match(read('pages/ApplicationRoot.ets'), /!this.skyReady \|\| !this.artComplete/);
  assert.match(read('pages/MainWindowNativeNode.ets'), /callNative\('getPresentationState'/);
});

test('only a ready actually presented frame with matching aspect reveals the chart', () => {
  const page = read('pages/MainWindowNativeNode.ets');
  const method = page.match(/  private dismissSplash\(\): void \{[\s\S]*?\n  \}/)[0];
  const published = new Map();
  const Fixture = new Function('AppStorage', 'hilog', stripTypeScriptTypes(`class Fixture { ${method} };`) + 'return Fixture;')(
    { setOrCreate: (key, value) => published.set(key, value) }, { info() {} });
  const fixture = new Fixture();
  Object.assign(fixture, { skyWidth: 1078, skyHeight: 674, splashGone: false,
    startupViewportCheckedAt: 0, stopTwinkle() {} });
  for (const response of [{ pending: true }, { ok: true, ready: true, width: 1023, height: 767 },
    { ok: true, ready: false, width: 2560, height: 1600 }, { pending: true }]) {
    fixture.startupViewportCheckedAt = 0;
    fixture.callNative = () => response;
    fixture.dismissSplash();
    assert.equal(fixture.splashGone, false);
  }
  fixture.startupViewportCheckedAt = 0;
  fixture.callNative = () => ({ ok: true, ready: true, width: 2560, height: 1600 });
  fixture.dismissSplash();
  assert.equal(fixture.splashGone, true);
  assert.equal(published.get('stellariumStartupSkyReady'), true);
});

test('withdrawing privacy stops the host before removing native content', () => {
  const page = read('pages/MainWindowNativeNode.ets');
  const method = page.slice(page.indexOf('  private revokePrivacyConsent()'), page.indexOf('  private startGyroscope()'));
  assert.ok(method.indexOf("setOrCreate('stellariumPrivacyHostReady', false)") < method.indexOf('this.privacyNativeStartupAllowed = false'));
});
