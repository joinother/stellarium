# 上游 Stellarium 26.3 合并：冒烟结果与真机测试清单

## 1. 合并信息

- 合并分支：`merge/upstream-26.3`
- 合并提交：`556bfa45ca`（基于 `ohos-master` `11c2e69a39`）
- 上游版本：Stellarium **26.3**，`master` `3f23cf3a1a`
- 共同祖先：`af253c6b`
- 上游提交：1123 个；变更文件：672 个
- 冲突：29 个（22 个 `po`、2 个 RemoteControl、1 个 CMake、1 个 skyculture 描述、3 个 `src`）

关键冲突处理：

| 文件 | 处理 |
|---|---|
| `CMakeLists.txt` | 保留 OHOS 构建配置（不引入 Qt Positioning），合并 26.3 版本号、Qt 6.10 Private 模块与 `StellariumPlatform` |
| `src/StelMainView.cpp` | 保留 OHOS `moveEvent` 特殊处理；非 OHOS 采用上游 `frameGeometry()` + DPR 保存 |
| `src/main.cpp` | 保留 OHOS 屏幕尺寸逻辑；移除上游已删除的 Windows 专用分支 |
| `src/core/StelSkyCultureMgr.cpp` | 同时保留 OHOS editorial context 与上游 territory 时间跨度逻辑 |
| `RemoteControl` | 保留 OHOS host/port 字段；合并上游 maxRequestSize/maxMultipartSize、OpenAPI 设置 |
| `skycultures/egyptian_dendera/description.md` | 采用上游新格式，保留 OHOS 的 Champollion/卢浮宫年代修正 |
| `po/*` | 中文 union 保留；非中文与 `.pot` 取上游 |

## 2. 构建结果

- 引擎交叉编译：**613/613 成功**，`libstellarium.so` 链接完成
- HAP：**BUILD SUCCESSFUL**，signed HAP **720.0 MB**
- `check-ohos-ui-contract.mjs`：通过（35 panels、30 static ids、18 dynamic prefixes、51 id anchors）
- `check-ohos-i18n.mjs`：通过（输出 INFO，无 ERROR）
- 环境警告（既有，不是本次合并引入）：缺少 `libjpeg.so`、缺少 `build/qt-platform-patch/manifest.json`

## 3. 模拟器冒烟结果

环境：Windows x86_64 模拟器 **Mate 90 Pro**，HarmonyOS 7.0.0（26.0.0），serial `127.0.0.1:5617`。

已验证：

- [x] HAP 安装成功
- [x] 应用启动，进程存活（PID 20020063）
- [x] `[ui-only] x86_64 emulator without the Stellarium engine` 日志出现，符合项目已知限制
- [x] 主界面 UI 外壳、底部 Dock（搜索/时间/快捷开关/图层/更多功能）显示正常
- [x] 中文 UI 文案正常
- [x] 点击 Dock “时间”可打开时间面板
- [x] 点击 Dock “快捷开关”可打开快捷面板
- [x] 面板切换、无崩溃
- [x] `[startup] sky-revealed` 日志出现

未验证（模拟器限制）：

- 星图渲染（黑色，arm64 `libstellarium.so` 无法在 x86_64 模拟器加载）
- Qt 命令桥（CLI 返回超时；日志为 `Stellarium command bridge not loaded yet`）
- 时间面板引擎数据（显示 `--`）、FOV、时间速率、天体搜索等
- 真实帧率、GPU/触摸/陀螺仪/折叠状态

> 项目文档 `docs/harmonyos/testing/PLATFORM-MATRIX.md` 已记录：Windows x86 模拟器只能验证 ArkUI 外壳/布局，不能验证星图与 Qt 引擎。真机测试是必需的。

## 4. 真机测试清单

### A. 启动与引擎

- [ ] 安装签名的 720 MB HAP 到 arm64 真机（手机/平板）
- [ ] 启动后星图正常渲染，不是黑色；无 `[ui-only]` 日志
- [ ] Qt 命令桥加载，`getState`/`getAppState` 返回数据
- [ ] 时间面板显示真实时间、时间速率、恒星时（不再是 `--`）
- [ ] 隐私门控、首次启动流程正常
- [ ] 版本/关于页显示 26.3
- [ ] 配置文件/旧设置迁移正常，无启动崩溃

### B. 26.3 新功能

- [ ] Object Visibility 插件：出现在插件列表/入口；打开设置和对话框
- [ ] Object Visibility：Twilight map 标签页、Twilight limits 标签页、可见性计算
- [ ] AstroCalc/日月食：跳转到日食/月食/凌日具体阶段；NASA/Espenak 时间术语；凌日线
- [ ] Satellites：Alpha-5 TLE 数据解析、卫星列表/轨道/测光数据
- [ ] RemoteControl：OpenAPI/SwaggerUI、Scenery3D 端点、设置对话框、host/port、maxRequestSize/maxMultipartSize
- [ ] Oculars：CCD 中心标记隐藏选项
- [ ] Planes：斜距/地面距离、海里单位（若 OHOS 构建启用该插件）
- [ ] 脚本：`core.moveToObject()` / `core.moveToSelectedObject()` dome mode
- [ ] 星空文化：Potawatomi 出现在列表；描述/插图/星座正常
- [ ] 星空文化：territory 时间跨度、egyptian 新描述格式
- [ ] 新星/彗星/系外行星/卫星数据更新

### C. Core / GUI 回归

- [ ] 工具栏位置调整选项
- [ ] Lightweight atmosphere 默认值
- [ ] HiPS 视口外瓦片淘汰
- [ ] 星座显示名查找
- [ ] 十进制角度选项拆分
- [ ] 恒星/深空天体/小行星/彗星排序
- [ ] 缩放屏幕/多显示器窗口尺寸与位置（PC/平板）
- [ ] 文字可读性与截图显示

### D. OHOS 既有功能回归

- [ ] 夜间模式切换与面板切换竞态（之前的 requestEpoch 修复）
- [ ] Dock 命中、面板打开/关闭/返回、compact/expanded 布局
- [ ] 搜索（中文/英文/多语言别名）、选中天体、详情卡
- [ ] 图层、时间、设置、快捷开关、更多功能
- [ ] 设置持久化、语言切换、离线资源
- [ ] Qt 生命周期、XComponent 表面、命令桥、config.ini 持久化
- [ ] 触摸/拖动/缩放手势、陀螺仪/指南针
- [ ] 平板/PC/分屏/折叠屏适配（如适用）
- [ ] 帧率、内存、长时间运行稳定性
- [ ] 离线/隐私/权限：无新增网络请求或权限

### E. 重点冲突区域

- [ ] `StelMainView` 窗口移动/尺寸变更（DPI/缩放屏幕）
- [ ] `main.cpp` 屏幕尺寸初始化（OHOS 全屏/窗口）
- [ ] `CMakeLists` 构建配置（Qt 6.10/StellariumPlatform/插件启用）
- [ ] `StelSkyCultureMgr` editorial context + territory 时间跨度
- [ ] RemoteControl 设置对话框（host/port/limits）
- [ ] 中文 `po` 翻译（Object Visibility 新词条、egyptian 描述）

## 5. 已知遗留

- `skycultures/egyptian_dendera/description.md` 已采用上游新文本并保留 OHOS 年代修正；对应的 `po/stellarium-skycultures-descriptions/zh_CN.po` 新条目暂无中文翻译，真机中文界面会回退英文，需后续补译。
- `data/search/multilingual-sky-aliases.tsv` 在构建时由 `build-ohos-multilingual-search-index.mjs` 重新生成；源码树已恢复原文件，HAP 内使用构建时生成的版本。若要让源码索引与 26.3 翻译同步，可单独重新生成并提交。
- Object Visibility 是 26.3 新增插件；需确认 OHOS 构建配置/插件列表是否实际启用，以及是否需要补 ArkUI 命令/UI 入口。
- `master` 仍落后 `stellarium_upstream/master` 141 个提交；本次只合并 26.3，不包含 26.3 之后的 upstream 变更。
- 模拟器截图保存在本机临时目录 `C:\Users\cnchensh\AppData\Local\Temp\stellarium-26.3-emulator-smoke\`，未提交到仓库。

## 6. 结论

- 合并分支构建通过，模拟器 UI 外壳冒烟通过。
- 星图/引擎/命令桥必须由真机验证；请按以上清单执行。
- 真机通过后再将 `merge/upstream-26.3` 合并回 `ohos-master`。
