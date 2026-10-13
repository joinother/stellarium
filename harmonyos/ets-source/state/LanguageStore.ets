import { I18n } from '../pages/I18n'

// 「界面语言」域状态 store：持有当前界面语言 selectedLanguage（Stellarium 语言码，默认取系统语言）、
// 语言刷新锚点 languageRevision 与语言刷新代际 languageRefreshSerial。
//
// 消费方以 @Prop 快照接收、宿主在下发点读 store：
//   - selectedLanguage：SettingsPanel / SettingsQuickLegacyPanel / ConfigFallbackPanel 及 LanguageRow；
//   - languageRevision：MorePanel / SearchPanel / SearchCategoryBrowse / SearchConstellationChips /
//     SearchFilterMenu / 三个壳层 / BottomDock / HubActionList。
// languageRevision 经多层组件 @Prop 串接，保持「宿主自增 → 宿主重渲染 → @Prop 下发 → ForEach 重建」
// 链路；setLanguage 中 `languageRevision++` 以 ForEach 键后缀强制语言相关列表/文案重建，该刷新语义不得改动。
//
// languageRefreshSerial 是语言刷新代际：setLanguage 中自增，回包返回时比对以丢弃过期请求；被搜索域
// （fetchSuggestions / loadConstellationNavigation）与目录域（CatalogHostHooks.languageSerial）只读使用。
// 属"语言刷新"语义，故由本 store 单一持有；跨域读者经宿主注入的只读 hooks / 显式传参获取，store 之间不互相持有。
//
// 约束：均为标量整体赋值（含 `++`），可被 @State 宿主观测。
@Observed
export class LanguageStore {
  selectedLanguage: string = I18n.systemLanguage()
  languageRevision: number = 0
  languageRefreshSerial: number = 0
}
