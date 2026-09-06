import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
function controllerFor(names) {
  const methods = names.map(name => {
    const start = source.indexOf('  private ' + name + '(');
    assert.ok(start >= 0, name);
    return source.slice(start, source.indexOf('\n  }', start) + 4);
  });
  const Controller = new Function('Curve', stripTypeScriptTypes('class Controller {\n' + methods.join('\n') + '\n}') + ';return Controller;')({ EaseInOut: 'EaseInOut' });
  return new Controller();
}

test('one catalogue merges core and extension classes by stable module ID', () => {
  const controller = controllerFor(['searchAllCategoryOptions']);
  controller.searchCategoryOptions = () => [{ code: 'planet', moduleId: 'SolarSystem:planet', label: '行星' }];
  controller.searchDynamicCategoryOptions = () => [
    { code: 'duplicate', moduleId: 'SolarSystem:planet', label: 'Planets' },
    { code: 'quasar', moduleId: 'Quasars', label: '类星体' },
    { code: 'future', moduleId: 'FuturePlugin', label: '未来目录' },
    { code: 'duplicate-future', moduleId: 'FuturePlugin', label: 'Another label' }
  ];
  assert.deepEqual(controller.searchAllCategoryOptions().map(option => option.code), ['planet', 'quasar', 'future']);
});

test('choosing a category returns to results without clearing observing filters', () => {
  const controller = controllerFor(['selectSearchFilterCategory']);
  const loads = [];
  const errors = [];
  Object.assign(controller, { searchFilterPage: 'categories', searchVisibilityFilter: 'above',
    searchInstrumentFilter: 'binocular', searchAllCategoryOptions: () => [{ code: 'satellite' }],
    getUIContext: () => ({ animateTo: (_options, callback) => callback() }),
    searchPanelScroller: { scrollTo: () => {} },
    loadCategoryObjects: category => loads.push(category), publishSearchBrowserState: error => errors.push(error) });
  controller.selectSearchFilterCategory('satellite');
  assert.equal(controller.searchFilterPage, '');
  assert.deepEqual(loads, ['satellite']);
  assert.equal(controller.searchVisibilityFilter, 'above');
  assert.equal(controller.searchInstrumentFilter, 'binocular');
  controller.selectSearchFilterCategory('bad');
  assert.deepEqual(loads, ['satellite']);
  assert.deepEqual(errors, ['unknown category']);
});

test('UI has one category picker and one filter picker, no dense extension block', () => {
  assert.equal(source.split(".id('search-category-picker')").length - 1, 1);
  assert.equal(source.split(".id('search-filter-picker')").length - 1, 1);
  assert.doesNotMatch(source, /showExtendedCategories|catalogCategoryChip|I18n.t\('search_add_filter'\)|I18n.t\('search_plugin_catalogs'\)/);
  const start = source.indexOf('  private catalogFilterRow(');
  const row = source.slice(start, source.indexOf('\n  }', start));
  assert.match(row, /maxLines\(2\)/);
  assert.match(row, /height\(60\)/);
  assert.match(row, /margin\(\{ bottom: 8 \}\)/);
  assert.match(row, /width\(24\).height\(24\).objectFit\(ImageFit.Contain\)/);
  assert.match(source, /searchFilterPage === 'root' \|\| this.searchFilterPage === 'categories'/);
  assert.match(source, /align\(Alignment.TopStart\)\s*\.id\('search-browser-scroll'\)/);
  const commandStart = source.indexOf("if (commandName === 'setSearchBrowserPage' || commandName === 'selectSearchCategory')");
  const command = source.slice(commandStart, source.indexOf("if (commandName === 'setAstroTab'", commandStart));
  assert.match(command, /if \(!this.panelVisible \|\| this.activePanel !== 'search'\) this.openPanelFromCli\('search'\)/);
  assert.doesNotMatch(command, /this.setPanel\('search'\)/);
});
