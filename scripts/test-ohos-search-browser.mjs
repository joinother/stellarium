import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
// §14 A2-3：分类选项族（searchCategoryOptions / searchAllCategoryOptions 等）已下沉 CatalogStore。
const catalogStore = readFileSync(new URL('../harmonyos/ets-source/state/CatalogStore.ets', import.meta.url), 'utf8');
const read = name => readFileSync(new URL('../harmonyos/ets-source/panels/search/' + name + '.ets', import.meta.url), 'utf8');
// 搜索面板已组件化：分类/筛选选择器在 SearchCategoryBrowse，筛选页切换在 SearchFilterMenu，目录行在 CatalogFilterRow。
const searchPanels = ['SearchBar', 'SearchSuggestions', 'SearchFilterMenu', 'SearchFilterChips', 'CatalogFilterRow',
  'SearchCategoryBrowse', 'SearchConstellationChips', 'SearchCoordinateInput'].map(read).join('\n');
// 搜索面板分支已下沉为 SearchPanel 组件（Phase 4e），浏览器 Scroll 的 id/align 现在组件内。
const searchPanelFile = readFileSync(new URL('../harmonyos/ets-source/panels/panels/SearchPanel.ets', import.meta.url), 'utf8');
// E4：搜索筛选行为（selectSearchFilterCategory 等）已自宿主下沉 capability/SearchController.ets。
const searchController = readFileSync(new URL('../harmonyos/ets-source/capability/SearchController.ets', import.meta.url), 'utf8');

const methodSources = [source, catalogStore, searchController];
function controllerFor(names) {
  const methods = names.map(name => {
    for (const src of methodSources) {
      let start = src.indexOf('  private ' + name + '(');
      if (start < 0) start = src.indexOf('\n  ' + name + '(');
      if (start >= 0) return src.slice(start, src.indexOf('\n  }', start) + 4);
    }
    assert.ok(false, name);
    return '';
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
  Object.assign(controller, { searchStore: { searchFilterPage: 'categories', searchVisibilityFilter: 'above',
    searchInstrumentFilter: 'binocular', loadCategoryObjects: category => loads.push(category) },
    catalogStore: { searchAllCategoryOptions: () => [{ code: 'satellite' }] },
    hooks: {
      animateFilterChange: callback => callback(),
      resetSearchScroll: () => {},
      publishSearchBrowserState: error => errors.push(error)
    } });
  controller.selectSearchFilterCategory('satellite');
  assert.equal(controller.searchStore.searchFilterPage, '');
  assert.deepEqual(loads, ['satellite']);
  assert.equal(controller.searchStore.searchVisibilityFilter, 'above');
  assert.equal(controller.searchStore.searchInstrumentFilter, 'binocular');
  controller.selectSearchFilterCategory('bad');
  assert.deepEqual(loads, ['satellite']);
  assert.deepEqual(errors, ['unknown category']);
});

test('UI has one category picker and one filter picker, no dense extension block', () => {
  assert.equal(searchPanels.split(".id('search-category-picker')").length - 1, 1);
  assert.equal(searchPanels.split(".id('search-filter-picker')").length - 1, 1);
  assert.doesNotMatch(source + searchPanels, /showExtendedCategories|catalogCategoryChip|I18n.t\('search_add_filter'\)|I18n.t\('search_plugin_catalogs'\)/);
  const row = read('CatalogFilterRow');
  assert.match(row, /maxLines\(2\)/);
  assert.match(row, /height\(60\)/);
  assert.match(row, /margin\(\{ bottom: 8 \}\)/);
  assert.match(row, /width\(24\)\.height\(24\)\.objectFit\(ImageFit\.Contain\)/);
  assert.match(searchPanels, /this\.store\.searchFilterPage === 'root' \|\| this\.store\.searchFilterPage === 'categories'/);
  assert.match(searchPanelFile, /align\(Alignment\.TopStart\)\s*\.id\('search-browser-scroll'\)/);
  const commandStart = source.indexOf("if (commandName === 'setSearchBrowserPage' || commandName === 'selectSearchCategory')");
  const command = source.slice(commandStart, source.indexOf("if (commandName === 'setAstroTab'", commandStart));
  assert.match(command, /if \(!this\.panelVisible \|\| this\.activePanel !== 'search'\) this\.openPanelFromCli\('search'\)/);
  assert.doesNotMatch(command, /this\.setPanel\('search'\)/);
});
