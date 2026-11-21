import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { MINOR_BODY_MESH_SPECS } from './build-ohos-minor-body-meshes.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const read = rel => readFileSync(root + rel, 'utf8');

test('all 15 spacecraft 3D minor-body source OBJ/texture files exist in models/', () => {
  assert.equal(MINOR_BODY_MESH_SPECS.length, 15);
  for (const spec of MINOR_BODY_MESH_SPECS) {
    assert.ok(existsSync(root + 'models/' + spec.obj), `Missing source OBJ: models/${spec.obj}`);
    if (spec.texture) {
      assert.ok(existsSync(root + 'models/' + spec.texture), `Missing texture: models/${spec.texture}`);
    }
  }
});

test('DetailModelNative.cpp and DetailModelWorker.ets wire SBM1 body-mesh rasterizer', () => {
  const nativeCpp = read('harmonyos/cpp-source/DetailModelNative.cpp');
  assert.ok(nativeCpp.includes('RenderDetailModelBodyMesh'));
  assert.ok(nativeCpp.includes('renderDetailModelBodyMesh'));
  assert.ok(nativeCpp.includes("data[0] != 'S' || data[1] != 'B' || data[2] != 'M' || data[3] != '1'"));

  const dts = read('harmonyos/cpp-source/types/libentry/Index.d.ts');
  assert.ok(dts.includes('renderDetailModelBodyMesh'));

  const worker = read('harmonyos/ets-source/capability/DetailModelWorker.ets');
  assert.ok(worker.includes("res.kind === 'body-mesh'"));
  assert.ok(worker.includes('nativeEntry.renderDetailModelBodyMesh'));

  const mediaCtl = read('harmonyos/ets-source/capability/ObjectInspectorMediaController.ets');
  assert.ok(mediaCtl.includes("detailModel.format === 'sbm1'"));
  assert.ok(mediaCtl.includes('commitObjectInspectorBodyMeshData'));

  const i18n = read('harmonyos/ets-source/capability/I18n.ets');
  assert.ok(i18n.includes("'model_body_3d'"));
  assert.ok(i18n.includes("'model_basis_body-mesh'"));
});

test('C++ engine exposes SBM1 detail model contract and planetary nomenclature atlas commands', () => {
  const cpp = read('src/StelMainView.cpp');
  const catalog = read('src/StelOhosCommandCatalog.hpp');
  for (const cmd of ['getPlanetaryNomenclature', 'flyToNomenclature', 'setNomenclatureSetting']) {
    assert.ok(cpp.includes(`commandName == "${cmd}"`), `Missing C++ handler for ${cmd}`);
    assert.ok(catalog.includes(cmd), `Missing catalog entry for ${cmd}`);
  }
  assert.ok(cpp.includes('models/ohos/%1.sbm'), 'objectDetailModelJson must emit models/ohos/*.sbm');
  assert.ok(cpp.includes('getAllNomenclatureItems()'), 'Nomenclature atlas must read all items even when labels start off');

  const nomMgrHpp = read('src/core/modules/NomenclatureMgr.hpp');
  assert.ok(nomMgrHpp.includes('getAllNomenclatureItems()'));

  const nomItemHpp = read('src/core/modules/NomenclatureItem.hpp');
  assert.ok(nomItemHpp.includes('getSize('));
  assert.ok(nomItemHpp.includes('getOriginI18n('));
  assert.ok(nomItemHpp.includes('getRawNameI18n('));
  assert.ok(nomItemHpp.includes('getRawEnglishName('));
});

test('NomenclaturePanel and MinorBodiesPanel 3D showcase follow HarmonyOS UI & bootstrap invariants', () => {
  const nomPanel = read('harmonyos/ets-source/panels/panels/NomenclaturePanel.ets');
  assert.ok(nomPanel.includes('InfoTipButton'));
  assert.ok(nomPanel.includes('UI_RADIUS_CARD'));
  assert.ok(nomPanel.includes('nomenclature-toggle-labels'));
  assert.ok(nomPanel.includes('nomenclature-toggle-craters'));
  assert.ok(nomPanel.includes('nomenclature-toggle-terminator'));
  assert.ok(nomPanel.includes('nomenclature-featured-'));
  assert.ok(nomPanel.includes('nomenclature-fly-'));

  const minorPanel = read('harmonyos/ets-source/panels/panels/MinorBodiesPanel.ets');
  assert.ok(minorPanel.includes('minor-bodies-3d-'));
  assert.ok(minorPanel.includes('67P/Churyumov-Gerasimenko'));

  const bootstrap = read('harmonyos/ets-source/qability/StellariumResourceBootstrap.ets');
  assert.ok(bootstrap.includes('refreshMinorBodyModels'));
  assert.ok(bootstrap.includes('models\\/'));

  const syncSh = read('scripts/sync-ohos-resources.sh');
  assert.ok(syncSh.includes('build-ohos-minor-body-meshes.mjs'));
  assert.match(syncSh, /^DIRS=\([^)]*\bmodels\b[^)]*\)/m);
});
