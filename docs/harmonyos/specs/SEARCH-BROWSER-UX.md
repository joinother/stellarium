# 搜索分类与筛选统一（2026-09-06）

## 用户路径

- 搜索框负责名称、编号、跨语言检索，检索逻辑保持不变。
- 无搜索词时只展示一个分类入口（含当前类别）和一个筛选按钮；条件生效时显示可移除的条件标签，不重复展示“+ 筛选”。
- 分类页合并基础目录与动态插件目录，按 moduleId 去重；一行一类，24vp 等比图标、14fp 双行名称、60vp 行高及 8vp 间隔。保留原数据模块、离线目录、专属图标和自动加载路径。
- 不再显示单独的“扩展目录”、横排类别标签或密集换行图标。Pad 搜索不再把旧探索首页塞在分类上面；原观测、月相、升降等功能入口仍在对应工作区。
- 筛选页只管理可见性和观测设备，不兼任分类导航。选分类不清除已有条件；选择后回结果页顶端。返回关系：分类→浏览、筛选→浏览、筛选子页→筛选。
- 手机/Pad/桌面共用同一份列表和导航，使用既有圆角与 220ms 非线性切换；子页不混入底部星座导航和坐标输入。
- 搜索 Scroll 显式 `align(Alignment.TopStart)`；短筛选页不能使用默认居中。华为 MCP 的通用位置属性文档确认 align 对 Scroll 子内容生效，默认值为 Center；真机对比分类/筛选标题纵坐标防止回归。

## CLI

通过 `scripts/stellarium-cli.mjs --command <命令> --payload <参数>` 调用 ArkUI 桥。

| 命令 | 参数/反馈 |
|---|---|
| setSearchBrowserPage | browse / categories / root / visibility / instrument；打开搜索并切换对应页 |
| selectSearchCategory | getSearchBrowserState.categories 中的 code；未知项拒绝 |
| setSearchBrowserFilter | visibility\|all/above/good，instrument\|all/naked/binocular/telescope |
| getSearchBrowserState | 当前 page、category、moduleId、条件、合并后的 categories、真实 scrollY |

状态在导航、分类/条件选择、动态目录更新时发布；滚动只更新独立数字，不每帧排序和序列化整个目录。命令收到 accepted 表示进入 UI 事件队列，测试需轮询反馈确认落地。新命令走 ArkUI 桥，不在本轮修改原生 C++ 命令目录。

## 官方参考与验证

已查询华为开发知识 MCP 的列表、动态布局和热区文档。当前 API 24 继续复用 Row/Column/Scroll、整行点击和常规文字换行，不引入检索结果中要求 API 26 的 ComposeListItemV2，也不扩大热区覆盖邻行。

- `scripts/test-ohos-search-browser.mjs`：目录去重、条件保留、非法分类拒绝、单入口与行布局。
- `scripts/test-ohos-search-browser-pad.py --device <设备> --output <报告>`：CLI 导航与反馈、真实返回/分类行点击、插件行滚动可达、条件保留、截图；结束恢复原分类和条件。
- 同步生成工程后运行 `scripts/check-ohos.sh`；Pad 通过语义 CLI 导航，并检查截图和真实行点击/滚动。
