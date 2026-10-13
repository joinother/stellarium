# HarmonyOS 调试包名清理方案（`com.cnchensh.stellarium`）

- **状态：** 已批准并执行（2026-10-08，S1–S6 一并落地）。
- **目标：** 向上游回馈前，把"本机 DevEco 自动签名身份" `com.cnchensh.stellarium` 从跟踪文件里彻底剔除；
  跟踪层只保留规范身份 `com.joinother.skyinstrument`，本机身份一律**运行时推导或参数传入**，并加护栏防复发。

## 1. 现状梳理（实测）

规范身份（唯一真源）：`harmonyos/AppScope/app.json5` 的 `bundleName = com.joinother.skyinstrument`（AGC 发布身份）；
`scripts/stellarium-cli.mjs` 的 `DEFAULT_BUNDLE` 同为该值。

`com.cnchensh.stellarium` 的实际分布（清理前，共 8 个跟踪文件 / 87 处）：

| 类别 | 文件 | 处数 |
|---|---|---|
| 可执行代码（唯一） | `scripts/build-ohos-hap-windows.ps1` | 4 |
| 开发说明 | `docs/harmonyos/DEVELOPMENT-MCP-WORKFLOW.md` | 1 |
| 开发说明 | `docs/harmonyos/BUILD-WINDOWS.md` | 1 |
| 开发说明 | `docs/harmonyos/KNOWN-ISSUES.md` | 2 |
| 研究计划 | `docs/harmonyos/research/ARKTS-PAGES-REFACTOR-PLAN.md` | 3 |
| 研究计划 | `docs/harmonyos/research/ARKTS-PAGES-REFACTOR-STATE-REVIEW.md` | 2 |
| 研究计划 | `docs/harmonyos/research/QUICK-ACTIONS-PANEL-PLAN.md` | 3 |
| 历史日志（保留） | `docs/harmonyos/CHANGELOG.md` | 71 |
| 本地技能（跟踪） | `.deveco/skills/arkts-slice-loop/references/slice-protocol.md` | 3 |

> **更正**：测试脚本里没有该调试包名——它们硬编码的是**发布身份** `com.joinother.skyinstrument`
> （`test-ohos-*-pad.py` 等）。真正泄漏调试包名的是**构建脚本 + 开发文档**。

**根因**：本机 DevEco「Automatically generate signature」生成个人签名（`bundle-name = com.cnchensh.stellarium`），
写进被 Git 忽略的生成工程 `AppScope/app.json5` / `SigningConfigs`；而 `build-ohos-hap-windows.ps1` 的
`-Install` 段把该包名**写死**在三条 `hdc` shell 命令里，文档再逐处复述。
**旁证**：`pack.info` 的 `summary.app.bundleName` 即本机签名身份——这是脚本可**自动读取**的廉价来源。

**同类旁项（本次不改写）**：`org.qtproject.example.stellarium`（Qt 模板遗留默认名）散见于
`release/SIGNING-GUIDE.md` 等 11 个文件，属独立问题，留待后续。

## 2. 处理方案

**原则：** 跟踪文件只保留一个规范身份；本机签名身份永不写死，一律运行时推导 / 参数传入；加护栏防复发。

| 片 | 内容 |
|---|---|
| **S1** | `build-ohos-hap-windows.ps1`：`-Install` 段从 `pack.info` 解析 `bundleName`（回退读生成工程 `AppScope/app.json5`），新增可选 `-Bundle` 覆盖；三条 `hdc` 命令改用该变量；注释中性化。 |
| **S2** | 7 个测试脚本（`.py`）：新增 `scripts/ohos_test_bundle.py`（`default_bundle()`：`STELLARIUM_BUNDLE` 环境变量 → `harmonyos/AppScope/app.json5` → 兜底发布身份）；各脚本加 `--bundle` 参数，并把 CLI 调用透传 `--bundle`。 |
| **S3** | `stellarium-cli.mjs`：`DEFAULT_BUNDLE = process.env.STELLARIUM_BUNDLE \|\| 'com.joinother.skyinstrument'`；`CLI.md` 补默认/覆盖说明。 |
| **S4** | 开发文档中性化：`BUILD-WINDOWS.md` / `DEVELOPMENT-MCP-WORKFLOW.md` / `KNOWN-ISSUES.md` / 三个 research 文档里的 `com.cnchensh.stellarium` 改为"本机签名身份（构建脚本从 `pack.info` 读取）"或发布身份示例。 |
| **S5** | `CHANGELOG.md` 顶部加一条**身份图例**（保留 71 处历史真机记录，不改历史）。 |
| **S6** | `.deveco/skills/.../slice-protocol.md`（`.deveco/` 下**唯一**被跟踪的文件）中性化；`.gitignore` 增加 `.deveco/`（防 `agents/`、`plans/` 等未跟踪内容误提交）；新增 `scripts/check-ohos-bundle-identity.mjs` 护栏（扫描跟踪文件命中 `com.cnchensh.*` 即失败，白名单 = `CHANGELOG.md` + 本方案文档），并接入 `check-ohos.sh`。 |

## 3. 验证

- `git grep -c "com\.cnchensh"`（排除 `CHANGELOG.md` 与本方案文档）应为空。
- `node scripts/check-ohos-bundle-identity.mjs` 通过。
- `node --check` 护栏脚本；`python -m py_compile` 7 个测试脚本 + 新 helper。
- PowerShell 语法检查 `build-ohos-hap-windows.ps1`；用现有 `pack.info` 做一次 `bundleName` 解析演练（当前无设备，不实机安装）。
- 无 `.ets` 改动，故不触发 UI 契约 / ArkTS 构建。

## 4. 决策记录（用户 2026-10-08）

1. CHANGELOG.md 71 处历史真机记录：**保留 + 顶部加身份图例**。
2. 测试脚本 bundle：**参数化**。
3. 执行方式：**先落本方案文档，再一并执行 S1–S6、统一验证**（不分片）。
