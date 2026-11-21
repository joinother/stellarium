import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

async function sourceModule(relativePath) {
  const source = readFileSync(new URL('../harmonyos/ets-source/' + relativePath, import.meta.url), 'utf8')
    .replace(/@Observed\r?\n/, '')
    .replace(/^import .*$/gm, '');
  return import('data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source)));
}

const { TimeWheelStore } = await sourceModule('state/TimeWheelStore.ets');
const { TimeWheelController } = await sourceModule('state/TimeWheelController.ets');

globalThis.TouchType = { Down: 0, Move: 1, Up: 2, Cancel: 3 };
const touchEvent = (type, x, y) => ({ type, touches: [{ x, y }], changedTouches: [{ x, y }] });

test('calendar units (year / month / day) keep hours, minutes, and seconds completely frozen during adjustment', () => {
  const store = new TimeWheelStore();
  const baseMs = Date.UTC(2026, 10, 16, 22, 32, 47);

  for (const unit of ['day', 'month', 'year']) {
    store.timeWheelUnit = unit;
    for (const steps of [-2.7, -1.4, -0.6, -0.3, 0, 0.3, 0.6, 1.4, 2.7, 5.2]) {
      const d = store.dateAtFraction(baseMs, steps);
      assert.equal(d.getUTCHours(), 22, `${unit} steps=${steps} hour drifted`);
      assert.equal(d.getUTCMinutes(), 32, `${unit} steps=${steps} minute drifted`);
      assert.equal(d.getUTCSeconds(), 47, `${unit} steps=${steps} second drifted`);
    }
  }

  // Selecting calendar unit pauses live simulation clock so seconds never tick while adjusting date
  let stops = 0;
  const wheel = new TimeWheelController(store, () => {}, () => { stops += 1; }, () => 8, () => {});
  wheel.selectUnit('day');
  assert.equal(stops, 1);
  wheel.selectUnit('month');
  assert.equal(stops, 2);
  wheel.selectUnit('year');
  assert.equal(stops, 3);
  wheel.stop();
});

test('time wheel flywheel accumulates velocity like a spinning top with zero damping and brakes on tap', () => {
  const store = new TimeWheelStore();
  store.timeWheelYear = 2026;
  store.timeWheelMonth = 11;
  store.timeWheelDay = 21;
  store.timeWheelHour = 22;
  store.timeWheelMinute = 0;
  store.timeWheelSecond = 0;
  store.timeWheelUnit = 'hour';
  store.refreshTicks();

  const wheel = new TimeWheelController(store, () => {}, () => {}, () => 8, () => {});
  try {
    // First gentle flick to the left -> launches spinning flywheel well below cap
    wheel.beginPan(300, 100);
    wheel.updatePan(296);
    wheel.updatePan(292);
    wheel.endPan(false);
    assert.equal(wheel.isSpinning(), true);
    const v1 = Math.abs(wheel.inertiaVelocity);
    assert.ok(v1 > 0.1 && v1 < 8.0, `expected moderate launch velocity, got ${v1}`);

    // Second flick in the SAME direction -> accumulates speed (like whipping a spinning top!)
    wheel.captureSpinOnTouchDown();
    wheel.beginPan(300, 100);
    wheel.updatePan(296);
    wheel.updatePan(292);
    wheel.endPan(false);
    assert.equal(wheel.isSpinning(), true);
    const v2 = Math.abs(wheel.inertiaVelocity);
    assert.ok(v2 > v1 * 1.4, `expected accumulated velocity v2=${v2} > v1=${v1}`);

    // Tap without drag -> brakes flywheel cleanly to a stop
    const captured = wheel.captureSpinOnTouchDown();
    assert.equal(captured, true);
    wheel.brakeFromTap();
    assert.equal(wheel.isSpinning(), false);
    assert.equal(wheel.inertiaVelocity, 0);
  } finally {
    wheel.stop();
  }
});

test('C++ star and satellite motion trails implement true spherical arcs, smoothstep fade, and invalidation guards', () => {
  const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
  const starMgr = read('src/core/modules/StarMgr.cpp');
  const zoneArray = read('src/core/modules/ZoneArray.cpp');
  const satCpp = read('plugins/Satellites/src/Satellite.cpp');
  const satsCpp = read('plugins/Satellites/src/Satellites.cpp');
  const mainView = read('src/StelMainView.cpp');
  const tabs = read('harmonyos/ets-source/panels/layers/LayerViewTabs.ets');
  const wheelSrc = read('harmonyos/ets-source/state/TimeWheelController.ets');

  assert.match(starMgr, /void StarMgr::drawMotionTrails\(/);
  assert.match(starMgr, /equinoxEquToJ2000\(Vec3d\(0\.0, 0\.0, 1\.0\)/);
  assert.match(starMgr, /MountAltAzimuthal/);
  assert.match(starMgr, /!mmgr->getFlagTracking\(\)/);
  assert.match(starMgr, /observerKey != m_prevTrailObserverKey/);
  assert.match(starMgr, /std::fmod\(deltaTheta \+ M_PI, 2\.0 \* M_PI\)/);
  assert.match(zoneArray, /trailSamples->append\(/);

  assert.match(satCpp, /clearMotionTrail\(\)/);
  assert.match(satCpp, /motionTrail\.append\(/);
  assert.match(satsCpp, /motionTrailActivity/);
  assert.match(satsCpp, /satTrailVerts/);
  assert.match(satsCpp, /sat->clearMotionTrail\(\)/);

  assert.match(mainView, /"starMotionTrails"/);
  assert.match(mainView, /"starMotionTrailAngleDeg"/);
  assert.match(tabs, /调时星轨拖尾/);
  assert.doesNotMatch(wheelSrc, /INERTIA_TIME_CONSTANT_MS/);
  assert.match(wheelSrc, /FLYWHEEL_ACCUMULATE_GAIN/);
});

test('vivid star spectral coloration, uniform photographic star trails, satellite selection suppression, and zero-stutter satellite cadence', () => {
  const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
  const skyDrawer = read('src/core/StelSkyDrawer.cpp');
  const starMgr = read('src/core/modules/StarMgr.cpp');
  const satsCpp = read('plugins/Satellites/src/Satellites.cpp');
  const mainView = read('src/StelMainView.cpp');

  // Rich physically-monotonic B-V palette + chromatic halo / incandescent core fragment shader
  assert.match(skyDrawer, /kSpectralStops/);
  assert.match(skyDrawer, /coreHot/);
  assert.match(skyDrawer, /haloBoost/);

  // Suppress star trails when an artificial satellite is selected; uniform photographic ribbon otherwise
  assert.match(starMgr, /const bool satelliteSelected = objectMgr && !objectMgr->getSelectedObject\("Satellite"\)\.isEmpty\(\);/);
  assert.match(starMgr, /&& !satelliteSelected;/);
  assert.match(starMgr, /auto endCapAlpha = \[\]\(float u\)/);
  assert.doesNotMatch(starMgr, /1\.0 - 0\.56 \* static_cast<double>\(u0\)/);

  // Zero-stutter satellite propagation: all on-screen satellites update every frame + analytic Keplerian streaks
  assert.match(satsCpp, /\|\| sat->lastFrameOnScreen/);
  assert.match(satsCpp, /smoothedTimeVelSecPerSec/);
  assert.match(satsCpp, /constexpr double kMuEarth = 398600\.4418;/);

  // HarmonyOS keeps interactive refresh rate when deeply zoomed in or tracking a selected satellite
  assert.match(mainView, /const bool zoomedLiveMotion = fabs\(timeRate\) > 0\.0/);
});
