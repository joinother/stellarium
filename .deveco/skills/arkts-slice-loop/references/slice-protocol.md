# 切片协议与命令库（从本会话 60+ 片实战中提炼）

## 一、每片八步（§13.2）

1. **量化**：统计该域 `@State` 字段数、`this.<name>` 引用数、候选 builder 行数与调用点数。据此判断能否自包含成片。
2. **建 store**：`state/<X>Store.ets`，`@Observed`，只放数据与纯计算，不 import UI/NAPI。字段声明从宿主**逐条复制**（保留类型与默认值）。
3. **建组件**：`panels/<域>/<Y>.ets`，`@ObjectLink` + `@Prop` + 回调注入；**不得**保留参数化 `@Builder`。
4. **单体手术**：删字段声明、删旧 builder、改写全部引用、替换调用点、补 store 字段声明与 import。**删字段声明的同时补宿主 `@State private <x>Store` 与 import，两步必须成对**（只改引用不补声明会让所有引用推断为 `any`，报 `arkts-no-any-unknown` 且行号散落）。
5. **预检 + 静态检查**：`node scripts/check-ohos-refactor-slice.mjs` → `arkts_check`。
6. **构建 + 契约**：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-ohos-hap-windows.ps1 -SkipEngine -SkipDeploy -SkipResources` → `node scripts/check-ohos-ui-contract.mjs`。
7. **测试 + 真机**：跑受影响的 `scripts/*.mjs`（搬迁会打断按文本切片的脚本，见下）→ hdc 安装/启动/交互实测。
8. **CHANGELOG + 提交**：CHANGELOG 用 CRLF 安全脚本前置插入并核对"裸 LF = 0"；提交 `refactor(...)`（+ 需要时 `test(...)` / `docs(...)`）；确认 `git status` 干净后更新 §13.5。

## 二、九条硬规则（§13.1）

| # | 规则 |
|---|---|
| 1 | `@ObjectLink` 的宿主源必须是 `@State` 持有的实例 |
| 2 | 组件成员名**不得与 `CustomComponent` 属性方法同名**（已踩：`borderColor` `scale` `onTouch` `background`） |
| 3 | 迁移后的 UI **不得保留参数化 `@Builder`**（简单类型参数按值捕获 → 子树首帧后冻结） |
| 4 | 宿主改 `@State` 持有的 `@Observed` 实例属性 → 宿主自身也会重绘（所以让宿主读 store 是安全的） |
| 5 | state 与读取它的 UI 必须**同片搬迁** |
| 6 | 跨域 / 桥 / 定时器依赖用**注入**解决，不硬搬 |
| 7 | `@Component` 的 `build()` 只能有**唯一容器根**（原 @Builder 并列多根时要包容器，`space` 取原调用点外层容器的值） |
| 8 | 搬迁会打断**按文本切片单体**的测试脚本；每片必须跑受影响脚本并同步（改读组件文件、假宿主补 store 对象） |
| 9 | **不要把宿主 `@Builder` 经 `@BuilderParam` 传进子组件** —— 真机实测渲染该页即整个应用退出（hilog 无 ArkTS 报错、构建全绿）。正解：先把 builder 改写成组件 |

## 三·补、模拟器验证范围（真机下线时按此执行）

模拟器（`Pura 90 Pro`，`127.0.0.1:5555`，x86_64）走的是 **debug-only UI-only 通道**（`QAbility.engineLessEmulatorUiOnly()`，详见 `docs/harmonyos/testing/PLATFORM-MATRIX.md` §1.5）：ArkUI 壳体与面板正常渲染、`@State`/`@ObjectLink` 的实时刷新可验，但**没有 Stellarium/Qt 引擎**。

- **可在模拟器验证**：面板打开与渲染、组件挂载与切换、开关/滑块/标签点击后的实时刷新、弹层与叠层样式、纯前端状态（store）读写、CLI 面板命令（`openUiPanel` 等）。
- **模拟器无法验证（必须记入报告与 CHANGELOG，留待真机）**：一切依赖 native 桥/引擎的路径 —— 天体搜索与选中（`listMatchingObjects` 依赖引擎 ✗）、详情卡内容与媒体/模型解码、卫星过境、星图渲染与手势、陀螺仪/罗盘（无真实传感器）、时间与坐标的真实计算值、以及任何读写真实天文数据的路径。
- **报告要求**：真机栏写成两段 —— 「模拟器已验证：…」+「模拟器无法覆盖（待真机）：…」。**不得**把模拟器冒烟写成"真机验证通过"。
- 模拟器上的 `pidof` 同样用于判存活（模拟器崩溃同样是回归信号）。
- 安装到模拟器时若 `install` 报签名/架构问题，先确认 `-SkipEngine` 构建产物（arm64 引擎不影响 UI-only 通道）。

## 三、命令库

```powershell
# 0) 切片预检（秒级，先跑它）
node scripts/check-ohos-refactor-slice.mjs

# 1) 构建（约 40–60 s）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-ohos-hap-windows.ps1 -SkipEngine -SkipDeploy -SkipResources

# 2) 契约校验（33 面板 / 22 静态 id / 17 动态前缀 / 42 锚点 / 88 个 .ets）
node scripts/check-ohos-ui-contract.mjs

# 3) 全量切片脚本扫描（只打印失败项；期望只剩 §13.6 的 6 个环境类）
$files = (Get-ChildItem scripts -Filter '*ohos*.mjs' | Where-Object { $_.Name -match '^(test|verify|audit)-ohos' } | Select-Object -ExpandProperty Name)
foreach($t in $files){ $o = node "scripts\$t" 2>&1; $txt=($o|ForEach-Object{"$_"}) -join "`n"
  $fail=([regex]::Matches($txt,'^# fail (\d+)','Multiline')|ForEach-Object{[int]$_.Groups[1].Value}|Measure-Object -Sum).Sum
  if($fail -gt 0 -or $LASTEXITCODE -ne 0){ "FAIL $t" } }
# 扫描会重写 docs/harmonyos/archive/audits/RESOURCE-COVERAGE-AUDIT-*.md，结束后必须还原：
git checkout -- 'docs/harmonyos/archive/audits/RESOURCE-COVERAGE-AUDIT-2026-08-24.md'

# 4) 真机/模拟器（设备号以 hdc list targets 为准）
#    真机 192.168.3.95:40565（IP 会变，先 list targets）；真机下线时改用模拟器 127.0.0.1:5555
#    （devecocli emulator list / start "Pura 90 Pro"；x86_64 UI-only 通道，见 PLATFORM-MATRIX §1.5）
& $hdc -t $dev install -r build\libstellarium-harmonyos\entry\build\default\outputs\default\entry-default-signed.hap
& $hdc -t $dev shell aa start -a QAbility -b <本机调试包名>   # 取自 build-ohos-hap-windows.ps1 -Install 打印
& $hdc -t $dev shell "pidof <本机调试包名>"     # 为空 = 已退出，优先怀疑刚做的改动
devecocli ui layout --device $dev
devecocli ui click/drag/text --device $dev ...
& $hdc -t $dev shell hilog -x | Select-String -Pattern 'detail-media|StellariumArkUI'   # 回调链路实证

# 5) CHANGELOG（CRLF 安全：here-string 是 LF，必须先归一）
$entry = @"
## [日期] DevEco Code - Phase xx：<标题>
- 要点…
"@
$p=(Resolve-Path 'docs\harmonyos\CHANGELOG.md').Path
$entry=$entry -replace "(?<!`r)`n","`r`n"
$cur=[System.IO.File]::ReadAllText($p,[System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($p, $entry+$cur, (New-Object System.Text.UTF8Encoding($false)))
# 立刻核对：裸 LF 必须为 0
```

## 四、踩坑表（都付过代价）

- **命令行内联中文会被代码页改写** → 新建文件的中文表头**先用 write 工具写临时文件**再拼入；否则报 `Declaration or statement expected`。
- **PowerShell `String.Split("`r`n")` 把参数当字符数组**（按 `\r`、`\n` 各切一次 → 行数翻倍、成片空行）→ 一律用 `-split "`r`n"`。
- **用行号算术组装删除区间会间歇性失败**（`@($s-1,$e)` 里 `$s` 被提升为数组 → 区间为空 → 旧 builder 成孤儿/死代码，而构建仍成功）→ **删除一律用 `[regex]::Escape(签名)` + `@Builder` 前缀 + 非贪婪到 `\n  }` 的正则**。
- **提取分支体时所有宿主引用都要列入改写表**：漏 `objectInspector*` 5 处、`gyro*` 13 处各烧掉数轮构建；**提取后先 grep 新文件里 `this\.<被搬前缀>` 再构建**。
- **组件成员名雷区**：`borderColor`（已两次）、`scale`、`onTouch`、`background`。
- **`@Component` 的 `build()` 多根** → 包 `Column({ space: <原外层 space> })`。
- **运行期退出无日志**：hilog 可能没有任何 ArkTS 报错，只能靠 `pidof` 判存活 + `git stash -u` 回上一片重新构建做 A/B。
- **测试夹具 CRLF**：`replace(/^import .*\n/gm,'')` 在 CRLF 下失效（JS 的 `.` 不匹配 `\r`）→ 用 `\r?\n`；`;\n}` 这类换行锚定断言同理。
- **提交前必须核对 `git status`**：本会话出现过"提交命令漏了一个文件"导致已提交源码不能编译（`GyroCalibPanel` 丢 import）。
- **`arkts_check` 会漏结构失衡**，绝不可替代构建。
- **两字段不入 store**：`objectInspectorModelRendering` / `objectInspectorModelTexturePixels` 由渲染管线逐帧写入，放进被观察 store 会造成重渲染风暴 —— 保持宿主字段、以 `@Prop` 传入。

## 五、粒度（本会话实测结论）

- 单片成本 ≈ 构建 50 s + 契约/测试扫描 2–3 min + 真机 3–5 min + CHANGELOG/提交 3 min ≈ **10 min**，且**基本不随片大小变化**；真正的成本是**漏改引用导致的返工**。
- 因此：**按面板/域合片**，一片收 2–4 个 builder（**300–350 行**），并**强制先跑 `check-ohos-refactor-slice.mjs`**（把"漏改引用/括号失衡"从构建期提前到秒级）。
- 保持单片的三类：① 渲染管线/高频写入状态；② 跨原生桥/`.so`；③ 布局变化明显（视觉回归需可二分）。
- 估算换算：69 个剩余 builder / 约 2,400 行 ≈ **9–10 片**（而非按单个 builder 的 15–25 片）。

## 六、Phase 4/5/6 工作口径（Phase 3 收尾后新增，2026-10-02）

### 6.1 目标澄清：`PanelHost` 不是"表驱动"

ArkUI **没有**"按名字动态实例化组件"的能力（不能用 `Record<string, ...>` 存 builder 再调用）。因此 Phase 4 的终态不是"表驱动宿主"，而是：**`panelContent` 的 `if / else if` 链退化为纯分发**——每个分支只剩**一行组件调用**（判定条件 `this.activePanel === 'xxx'` 留在宿主），全部 UI 都在组件里。判定"某分支是否已达标"的口径：分支体 ≤ 8 行且只含一次组件调用。

### 6.2 三类分支的处理方式

| 类 | 特征 | 处理 |
|---|---|---|
| 薄调用 | 体内只是 1 行调用既有组件（`observeHub`/`dataHub`/`automationHub`/`bookmarks`/`pointerCoordinates`/`tools`/`telescope`/`skyCultureMaker`） | **不要再包一层**，保持原样 |
| 实分支（10–30 行） | 体内有真实 UI（开关行、滑块、列表、按钮） | 抽成 `panels/panels/<Name>Panel.ets`：`@ObjectLink store` + `@Prop` + 回调；随 UI 下沉的**纯助手函数一并迁走**；参数化 `@Builder` 不得保留（**禁止** `@BuilderParam`，§13.1 规则 9） |
| 大分支（>100 行） | `settings` / `scripts` / `oculars` / `astro` / `audio` / `settings_quick_legacy` 等 | 单独一片，允许**片内分多个提交**，每个提交点都要预检/`arkts_check`/构建/契约全绿 |

**注意**：`layers`、`skyCultureMaker` 等分支体内还调用未迁的 `private @Builder`（如 `satelliteGroupSelector`、`skyCultureLabelModePicker`、`skyCultureFilterPicker`、`skyCultureFilterOption`、`skyCultureSectionHeader`、`skyCultureMetaItem`、`skyCultureLabelSettingCard`，共约 200 行）→ 先搬这些**叶件**，再搬宿主分支；`floatingPanel` / `compactPanel` 因体内是 `this.panelContent()`，必须与分支收尾同片。

**分支体量口径警告**：用"到下一个 `} else if (this.activePanel === ...)` 头的距离"做体量排序**不可靠**——`settings_quick_legacy` 内含同形旧链，会出现重名与虚高（曾测得 `audio 1954` / `place 3819`）。正确做法：按 `panelContent` 起点逐分支**显式步进到该链的 `} else {` 尾巴**再落数，或直接用 `git diff --stat` 复核每片净减行数。

### 6.3 阶段归属

- **Phase 4（进行中）**：`panelContent` 剩余实分支 + 7 个 skyCulture 叶件 + `floatingPanel`/`compactPanel`。
- **Phase 5（overlay）**：`polarScopeOverlay` 126 / `objectInspectorMediaPreviewOverlay` 66 / `skyCultureArtPreviewOverlay` 60 / `objectInspectorModelOverlay` 45 —— 均为 `Stack` 叠层且涉媒体/模型/渲染，**每片只做一个**，真机走查要求最高。
- **Phase 6（壳层）**：~~`scriptFocusShell`~~（6a）/ ~~`compactShell`~~ / ~~`harmonyShell`~~（6b）已完成；剩余 `hoverObservatoryShell` 142 / `expandedShell` 128 / `interactiveGuideShell` 78 —— 每片 1–2 个壳；`panelHeader` chrome 已抽（3ap），`observationTimeText` / `timeRateText` 仍由宿主算好以 `@Prop` 传入。
- **Phase 7（收口）**：删过渡 getter、校正 `UI-ARCHITECTURE.md` 行号与 `AGENTS.md §2.2`。

### 6.4 设备与验证纪律（2026-10-02 更新）

- **优先真机**（`hdc list targets` 取当前设备号，IP 会变）：用户已在 DevEco 侧开启**屏幕常亮**，长片不再因锁屏中断。
- 真机不可用时用模拟器 `127.0.0.1:5555`（`devecocli emulator start "Pura 90 Pro"`），按"三·补"的范围记录「模拟器无法覆盖（待真机）」。
- **两个同名 App 陷阱**：本仓库本机调试构建装的包名由 DevEco 自动签名决定（`build-ohos-hap-windows.ps1 -Install` 打印，取自 `pack.info`），真机上另有发布身份 `com.joinother.skyinstrument`；`devecocli ui` 跟随前台窗口，而 `stellarium-cli.mjs` 默认可能连到另一个包 → **CLI 一律显式 `--bundle <本机调试包名>`（或设 `STELLARIUM_BUNDLE`）**，并先 `aa dump -l` 确认前台。
- 每片真机实测至少给一处**点按后实时刷新**的证据（坐标/采样值/hilog/CLI 回读）；测后恢复改过的持久化设置。
- 工具链故障（同步失败、hvigor 缓存损坏）**不属于切片回归**：`C:\Users\<user>\.hvigor\project_caches\<hash>\workspace` 缺 `@ohos/hvigor` 会让 IDE 同步报 `00308003`，脚本构建不受影响 —— 记录并请用户在 IDE 侧 `Invalidate Caches` / 修 hvigor 组件，不要试图用 junction 从安装目录链过去（按 realpath 判定无效）。
