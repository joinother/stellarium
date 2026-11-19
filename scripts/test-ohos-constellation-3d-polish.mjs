import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = p => readFileSync(new URL(p, import.meta.url), 'utf8');

const constellationCpp = read('../src/core/modules/Constellation.cpp');
const constellationMgrCpp = read('../src/core/modules/ConstellationMgr.cpp');
const touchPickerCpp = read('../src/core/TouchPicker.cpp');
const mainViewCpp = read('../src/StelMainView.cpp');
const catalogHpp = read('../src/StelOhosCommandCatalog.hpp');
const typesEts = read('../harmonyos/ets-source/common/types/StellariumTypes.ets');
const storeEts = read('../harmonyos/ets-source/state/SkyCultureSettingsStore.ets');
const i18nEts = read('../harmonyos/ets-source/capability/I18n.ets');
const viewTabEts = read('../harmonyos/ets-source/panels/skyculture/SkyCultureViewTab.ets');

test('ConstellationMgr partitions 3D models into disjoint back-to-front depth slices', () => {
  assert.match(constellationMgrCpp, /gl->glDepthRangef\(sliceNear, sliceFar\);/);
  assert.match(constellationMgrCpp, /gl->glDepthRangef\(0\.0f, 1\.0f\);/);
  assert.match(constellationMgrCpp, /std::sort\(models3d\.begin\(\), models3d\.begin\(\) \+ active3dCount/);
  assert.match(constellationCpp, /qBound\(-0\.95f, static_cast<float>\(\(1\.0 - norm\) \* 2\.0\), 0\.95f\)/);
});

test('Constellation loadArtModel applies calibrated rigid SO(3) alignments with normal rotation', () => {
  assert.match(constellationCpp, /kModelPoseAlignments/);
  for (const id of ['Leo', 'UMa', 'Tau', 'Sco', 'Sge', 'Cyg', 'Cam', 'Cap', 'Boo', 'Lac', 'Mus', 'Pyx', 'Sex', 'Nor']) {
    assert.match(constellationCpp, new RegExp(`QStringLiteral\\("${id}"\\)`), `Missing alignment for ${id}`);
  }
  assert.match(constellationCpp, /rotateVec\(nx, ny, nz\)/);
});

test('TouchPicker and Constellation make 3D models reliably selectable without faint-star stealing', () => {
  assert.match(constellationCpp, /modelIntensity\(\) <= 0\.003f/);
  assert.match(constellationCpp, /artPolygonContainsPoint\(/);
  assert.match(touchPickerCpp, /hasConstellationModelHit/);
  assert.match(touchPickerCpp, /faintMinorBody/);
  assert.match(touchPickerCpp, /priorityRadiusVp = -1\.0;/);
  assert.match(touchPickerCpp, /else if \(tierA == 5\)/);
  assert.match(touchPickerCpp, /std::abs\(a\.salience - b\.salience\) > 0\.05/);
  assert.match(touchPickerCpp, /getLinePresentation\(\) > 0\.05f/);
  assert.match(touchPickerCpp, /getLineAnimProgress\(\) > 0\.05f/);
});

test('Center line-drawing animation switch is wired end-to-end across C++ and HarmonyOS UI', () => {
  assert.match(constellationMgrCpp, /viewing\/flag_constellation_line_center_anim/);
  assert.match(constellationMgrCpp, /CenterLineAnimation/);
  assert.match(constellationCpp, /ConstellationPresentation::segmentDrawFraction/);
  assert.match(mainViewCpp, /result\["constellationLineCenterAnim"\] = cmgr->getFlagLineCenterAnim\(\)/);
  assert.match(mainViewCpp, /setting == "constellationLineCenterAnim"/);
  assert.match(catalogHpp, /constellationLineCenterAnim/);
  assert.match(typesEts, /constellationLineCenterAnim\?: boolean/);
  assert.match(storeEts, /skyCultureConstellationLineCenterAnim/);
  assert.match(i18nEts, /'culture_line_center_anim':/);
  assert.match(i18nEts, /'culture_line_center_anim_hint':/);
  assert.match(viewTabEts, /skyculture-line-center-anim-toggle/);
});
