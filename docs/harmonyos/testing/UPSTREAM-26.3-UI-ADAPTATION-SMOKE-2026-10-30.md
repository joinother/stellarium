# Stellarium 26.3 新功能 ArkUI 适配：构建与模拟器冒烟（2026-10-30）

## 1. 范围

本次在 `merge/upstream-26.3` 工作区完成 26.3 合并后的 ArkUI 适配：

| 功能 | 实现 |
|---|---|
| 十进制度拆分为坐标 / 其它两个开关 | 原生命令 `setDecimalDegrees coords\|other`；`getState` 返回两个字段；设置 → 附加页“角度显示”两个开关 |
| 星空文化“未知 / 至今”哨兵 | `SkyCultureSettingsStore` 精确识别 `-100000` / `9146`，显示“未标注 / 未知 / 至今”，时间匹配同步 |
| Potawatomi 旧安装升级补抽 | 异步资源准备入口定向补抽 `skycultures/potawatomi`；三项哨兵加入全树重抽闸门，避免提前返回后抛错导致 Qt 不初始化 |

## 2. 构建

环境：Windows 11，DevEco Studio `E:\code\Huawei\DevEco Studio`，Qt 6.12 `E:\Qt\6.12.0\harmonyos_arm64_v8a`。

命令：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-ohos-hap-windows.ps1 -SkipDeploy -SkipResources
```

结果：

- 引擎交叉编译：**568/568 成功**，`build/src/libstellarium.so` 链接完成。
- `assembleHap`：**BUILD SUCCESSFUL**。
- 签名 HAP：`build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap`，**720.1 MB**。
- `check-ohos-ui-contract.mjs`：通过（35 panels、30 static ids、18 dynamic prefixes、51 id anchors）。
- `check-ohos-i18n.mjs`：通过（无 ERROR）。
- `check-ohos-command-catalog.mjs`：通过（402 个命令）。
- `CompileArkTS`：通过，仅有既有 `NODE` deprecated / 异常处理警告。

## 3. 模拟器冒烟

设备：Mate 90 Pro，HarmonyOS 7.0.0（26.0.0），x86_64，serial `127.0.0.1:5617`。
安装方式：覆盖安装（保留旧应用数据），用于贴近升级场景。

已验证：

- [x] HAP 覆盖安装成功，启动成功，进程存活（pid 19107）。
- [x] `[ui-only] x86_64 emulator without the Stellarium engine` 按预期出现，UI 外壳正常。
- [x] 主界面 Dock、更多功能、设置面板正常打开。
- [x] 设置 → 附加页渲染“角度显示”分组：
  - “坐标使用十进制度”
  - “其它数据使用十进制度”
  - “坐标与其它角度值可分别选择是否使用十进制度。”
- [x] 无引擎时点击开关：先乐观切换，约 1.5 秒内回退为关闭并提示“应用失败”，进程不崩溃。
- [x] 截图：`build/smoke-2026-10-30/00-start.png` … `06-toggle-reverted.png`（本机构建目录，未提交）。

未验证（模拟器限制）：

- 星图渲染、Qt 命令桥、`setDecimalDegrees` 真实回执。
- 资源提取：`QAbility` 的 `engineLessEmulatorUiOnly()` 路径在加载 `ApplicationRoot` 后直接释放启动门，**不调用 `prepareStellariumResourcesAsync` / `prepareStellariumResources`**，因此 Potawatomi 升级补抽无法在模拟器执行。
- 星空文化列表与哨兵显示（需要引擎返回 `getSkyCultureList`）。

## 4. 关键实现细节

### 4.1 十进制度

- 原生：`src/StelMainView.cpp` 新增 `setDecimalDegrees`，`currentStateJson()` 增加两个字段；`src/StelOhosCommandCatalog.hpp` 登记命令。
- ArkUI：
  - `ViewSettingsStore.decimalDegreesCoords/Other` 为乐观镜像；`decimalDegreesConfirmedCoords/Other` 保存最后一次确认值；`decimalDegreesRequestSeq` 只让最新请求的失败生效；`decimalDegreesPending` 阻止在途请求期间的轮询快照把 UI 顶回旧值。
  - `MainWindowNativeNode` 的 `getState` 回读走 `syncDecimalDegreesFromState`。
  - 设置页开关在“附加”标签页，文案在 `I18n.ets`。

### 4.2 星空文化哨兵

- `StelSkyCultureMgr` 从 `territory.geojson` 推导时间跨度；无可用 territory 时使用 `unknownBeginTime = -100000`、`presentEndTime = 9146`。
- ArkUI 以精确值识别哨兵；`0` 仍作为 ArkTS 缺省值按未知处理。
- 筛选函数仍把哨兵当作“很早 / 至今”，因此不会把文化错误排除；本次只修正显示与匹配文案。

### 4.3 Potawatomi 升级补抽

- `StellariumResourceBootstrap.refreshNewSkyCultures()` 只在 `installRoot` 已存在且三项哨兵缺失时执行定向补抽，避免为 21 个文件重走整棵资源树。
- `hasStartupResourceFiles()` 的 `requiredAssets` 加入 `index.json`、`description.md`、`territory.geojson`，作为补抽失败后的整树重抽兜底。
- `prepareStellariumResources()` 的最终检查同样检查三项，避免半成品目录通过。
- 修复前的问题链：旧安装 `hasStartupResourceFiles()` 为 true → 异步准备提前返回 → `prepareStellariumResources()` 发现 Potawatomi 缺失并抛错 → Qt 初始化被阻断，表现为安装后进程起不来。

## 5. 真机复测清单（必须）

- [x] 旧版本覆盖安装（保留数据）后应用能正常启动，无 `Startup resources require asynchronous repair` / `Qt application context initialization failed`。
- [ ] 日志出现 `[startup] installing new sky culture: potawatomi` 与 `new sky culture potawatomi ready`（本次设备可能已有 Potawatomi，日志缓冲未覆盖提取阶段，待全新/清数据复现）。
- [x] `getSkyCultureList` 包含 Potawatomi，条目数从 63 变为 64。
- [x] 星空文化面板：`modern*` 等哨兵文化显示“年代范围未标注”，时间匹配显示“该文化未标注适用年代”。
- [ ] `chinese` 1756–1911、`egyptian_dendera` -320–30 在 UI 中显示正常（CLI 列表已返回正确 begin/end，UI 未逐条点开）。
- [x] `setDecimalDegrees 1|0` 返回 `ok:true`，`getState` 与 `config.ini` 均变为 `coords=true / other=false`；已恢复 `0|0`。
- [ ] 设置 → 附加 → 角度显示：两个开关在真机 UI 中独立开关、重启后保持；对象资料按开关变化。
- [ ] 快速连点两个开关，最终状态与 `getState` / `config.ini` 一致。
- [ ] 无对象选中、桥未就绪、请求失败时开关回退且不崩溃。

## 5.1 真机验证记录（2026-10-30）

- 设备：HUAWEI SGT-AL00（Mate 80 Pro），HarmonyOS 7.0.0.109(SP6C00E105R3P3)，`192.168.1.5:36717`。
- HAP 覆盖安装成功；启动后进程 12980 存活，星图正常渲染，fps≈25，命令桥可用。
- `getSkyCultureList`：64 条，包含 `potawatomi`（`beginTime:1667`、`endTime:9146`、18 星座、18 幅绘图）。
- 星空文化面板选择“现代”：适用年代显示“年代范围未标注”，时间匹配显示“当前模拟时间：该文化未标注适用年代”。
- `setDecimalDegrees 1|0` → `{"ok":true,"coords":true,"other":false}`；`getState` 回读一致；`getConfigString gui/flag_use_decimal_degrees_coords` 返回 `"true"`。随后 `setDecimalDegrees 0|0` 恢复，`getState` 为 `false/false`。
- 测试后已将天空文化恢复为 `modern`。

## 6. 结论

- 构建、静态检查、模拟器 UI 外壳冒烟通过。
- 真机已安装并完成 Potawatomi 列表、哨兵显示与十进制度命令回执验证；UI 开关交互与对象资料格式仍建议按第 5 节补测。
- 全部通过后再把 `merge/upstream-26.3` 合回 `ohos-master`。
