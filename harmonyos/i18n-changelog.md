# 界面中文化 + 多语言资源体系 + 模糊搜索增强

分支：`openharmony-preview-v1`（Stellarium → HarmonyOS NEXT 移植）

## 一、界面中文化（天体名 / 搜索 / 显示）
- 核心吐出的天体名（Moon、Jupiter、M31…）原样显示英文，ArkUI 未做映射。
- 新增 `ALIAS_LIST`（~150 条：行星/太阳/月亮、亮星含北斗七星/北极星、著名深空
  M1/M8/M13/M31/M42/M45/NGC7000/双星团等、常见 88 星座），含 `py` 拼音字段。
- `zhNameOf` / `enNameOf` / `zhType` / `aliasHits` 四个 helper：
  - 详情面板、分类兜底列表、观测列表统一显示中文名 + 别名。
  - 搜索命中中文名 / 拼音子串 / 英文名，都能定位到核心认识的英文标识。
- 搜索建议 `fetchSuggestions` 上限提到 30 条，并合并 `aliasHits` 的中文/拼音命中，
  按中文名排序（详见第六节模糊搜索）。

## 二、正式多语言资源体系（$r() + string.json）
- 把 UI 字面量（Text/Button/infoRow 首参/placeholder/flashHint/CatOption·ShellAction 的 label）
  统一改走 `$r('app.string.iXXXX')` 资源引用，不再硬写死（ets 内约 136 处 `$r()` 调用）。
- 资源目录 `resources/{base,zh_CN,en_US}/element/string.json` 各含 **108 个 `app.string.iXXXX`**
  + **5 个系统级项**（`module_desc`/`QAbility_desc`/`QAbility_label`/
  `qt_permission_reason_read_pasteboard`/`stellarium_permission_reason_location`），**共 113 条**。
- **语言规则（关键）**：本 SDK 没有 `setPreferredLanguage`（见第三节），无法用代码切 UI 语言，
  所以 **`base` 与 `zh_CN` 都是中文**，`en_US` 是英文。
  - 设备 locale = `zh_CN` → 加载 `zh_CN`（中文）。
  - 设备 locale = `en_US` → 加载 `en_US`（英文）。
  - 其它 locale（ja/ko/fr…）→ 回退到 **`base`（中文）**。
  → 即在中文设备上 UI 必为中文；英文 UI 需把设备/模拟器语言设为 English。

### ⚠️ 写这套时踩的坑（已修）
0. **资源 `name` 不能带点（`.`），否则 `CompileResource` 直接报
   `Invalid resource name 'app.string.i0001'. It should match [a-zA-Z0-9_]`。**
   正确约定：JSON 里的 `name` 用裸名 `i0001`（不带 `app.string.` 前缀、不带点），
   代码里引用才写带限定符的 `$r('app.string.i0001')`（`app.string.` 是系统加的模块+类型前缀）。
1. **`$r()` 是 `Resource`，不能和字符串 `+` 拼接。**
   `flashHint($r('x') + name)` 会编译失败。动态拼接待格式串的场景（搜索:xxx、已选中 xxx、打开xxx面板…）
   改成 `flashHint($r('app.string.x', name))`，对应资源值加 `%s` 占位符（共 9 个格式串带 `%s`）。
2. **注入 `Resource` 的槽位要把类型放宽成 `ResourceStr`（= `string | Resource`）。**
   共放宽 11 处：`CatOption.label`、`ShellAction.label`、`@State actionHint`、`flashHint(text)`、
   `zoomButton(label)`、`smallRoundButton(label)`、`infoRow(label)`、
   `switchRow(label)`、`quickChips(labels)`、`zhType()`(含内部 `Record<string,ResourceStr>`)、
   `panelTitle()`/`panelSubtitle()`。这样 `$r()` 能塞进去，普通字符串字面量也仍兼容。
3. **对象字面量不能当类型用（`arkts-no-obj-literals-as-types`）。**
   `Array<{ zh:string; en:string; score:number }>` 编译不过，改成先 `interface AliasHit {...}` 再用
   `Array<AliasHit>`。
4. **方向字母 N/S 必须保留成字符串字面量**（不是 i18n key），因为 `formatDegrees(latitude,'N','S')`
   形参类型是 `string`，且 N/S 是通用方向字母无需翻译。

## 三、语言切换器：核心语言可切，UI 语言跟随设备 locale
- 旧逻辑：`setLanguage` 只调核心 `setLanguage`（改星空文化名/天体名语言），ArkUI 界面语言不变。
- 本轮尝试的新逻辑：核心切换成功后，再调
  `getApplicationContext().setPreferredLanguage(lang.replace('_','-'))` 让 ArkUI 按首选语言加载
  `string.json`。**但经 Grep 全量扫描 SDK 的 `*.d.ts` 确认：本机 SDK
  （`/Applications/DevEco-Studio.app/Contents/sdk`）根本没有 `setPreferredLanguage` 这个 API，
  且 `getApplicationContext` 也不是 `@kit.AbilityKit` 的导出成员。**
- **最终方案（已落地）**：
  - 移除整个 `setPreferredLanguage` 调用块，规避编译错误。
  - `setLanguage(lang)` 现在只调 `this.callNative('setLanguage', lang)` 切**核心/天体名语言**
    （即星空里显示中文/英文星名由它控制）。
  - **UI 文案语言（按钮、提示、搜索框等）由 `string.json` + 设备 locale 决定**，代码无法在运行时切换，
    需要在设备/模拟器系统设置里把语言设为中文（中文 UI）或 English（英文 UI）。
  - 切换器按钮 zh_CN/en/ja/ko 等点击后只切核心语言；UI 语言变化要重启应用或切系统语言才生效。

## 四、模糊搜索增强（ArkUI 层，不碰 C++）
- 用户输入 → `fetchSuggestions(prefix)`：
  1. 先问核心 `listMatchingObjects` 取前缀匹配，参数带 `|30`（核心最多回 30 条）。
  2. 再合并 `aliasHits(prefix)` 的中文/拼音/英文模糊命中，补足核心只做“词首前缀”的不足。
  3. 合并后按中文名 `localeCompare('zh')` 排序，`slice(0, 30)` 截断展示。
- `aliasHits(input)` 模糊规则（任一命中即进建议，按 score 排序、最多 12 条别名）：
  - 英文名完全相等 → score 0；英文名 `startsWith` → score 1；
  - **中文名子串包含**（输入中文能搜到）→ score 1；
  - **拼音子串包含**（输入 pinyin 能搜到，如 `jx`→金星）→ score 2；
  - 英文名子串包含 → score 3。
- 效果：原来只能搜英文精确前缀，现在**中文名 / 拼音 / 英文子串**都能模糊命中，结果扩到 30 条。

## 五、构建 / 验证
- 本项目默认构建即为 **debug**（`module.json` 内 `debug:true`、`buildMode:debug`，
  用 `build-profile.json5` 的 `default` 签名配置 `debugKey`）。
- 增量构建（仅 ets/资源改动，不重编 C++）：
  `hvigorw assembleHap --mode module -p product=default --buildMode debug`
  （需 `JAVA_HOME`/`NODE_HOME`/`DEVECO_SDK_HOME` 指向 DevEco 自带工具链）。
- 模拟器 `127.0.0.1:5555`，包名 `org.qtproject.example.stellarium`，主 Ability `QAbility`。
- **⚠️ 模拟器安装限制（重要）**：本地 Device Simulator 只接受 **DevEco IDE 自动签名**的 debug 包。
  用 hdc 装我们 `debugKey` 签的 HAP 会报 `code:9568450 / must be debug type`
  （即便 `module.json` 里 `debug:true` 也装不进，是证书信任问题不是 debug 标志问题）。
  → **运行期冒烟请在本机用 DevEco 直接 Run 到模拟器/真机**；或用 DevEco 导出的包安装。
  hdc `bm install` 这条路在本机模拟器上行不通。
- 静态校验已通过：string.json 三语言 113 条对齐；ets 136 处 `$r()`；
  `setLanguage`→`callNative('setLanguage')`；`fetchSuggestions`/`aliasHits` 模糊逻辑就位；
  增量构建 `BUILD SUCCESSFUL`（0 错误）。

## 六、本轮（资源体系落地）额外踩坑与修法
- **v2 包裹脚本吞右括号（致命）**：早期自动包裹脚本把 `Text('x')` 末尾 `)` 吞掉，
  变成 `Text($r('key')`，导致后面 `.fontSize()` 链挂到 Resource 上，报 ~189 个 ArkTS 错误
  （`Property 'fontSize' does not exist on type 'Resource'` 等）。
  → 改用**只替换完整引号 token、保留所有括号**的安全替换法重建，错误从 189→23。
- **key 编号错位**：历史 `string.json`（110 key）与本轮 `.new` 包裹（108 key）编号对不上
  （如 json 的 i0068=`位置名称`，`.new` 的 i0068=`星图文化:`），直接套用会显示错乱。
  → 从 `.new` 重新提取 **108 key→字面量映射** 重建全部 6 个 string.json
  （用原 json 的 zh↔en 配对作翻译字典），消除错位。
- **`setPreferredLanguage` 不存在**（见第三节）：Grep 全 SDK `.d.ts` 确认后移除调用，
  改为“核心语言走 callNative + UI 跟随设备 locale + base 回退中文”。

## 七、双副本铁律
`harmonyos/ets-source/`(git 跟踪) 与 `build/libstellarium-harmonyos/entry/src/main/ets/`(构建副本)
的 `MainWindowNativeNode.ets` 必须 md5 一致；`harmonyos/resources/` 与
`build/.../resources/` 的 `string.json` 同样双写。改其一须同步其二。
