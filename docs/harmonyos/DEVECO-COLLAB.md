# DevEco Code 协作指南（Stellarium HarmonyOS 项目专用）

> **版本：** 2026-07-21
> **适用对象：** Trae、WorkBuddy 或其他通用 AI Agent
> **核心目标：** 把鸿蒙开发的"重活"外包给 DevEco Code 的免费 GLM-5.1，自己只收结论，节省 token 消耗约 200 倍。

---

## 一、为什么要协作？

DevEco Code（`@deveco/deveco-code`，npm 全局包）是华为推出的终端内鸿蒙 AI 开发助手，拥有通用 AI 助手不具备的独家能力：

| 能力 | DevEco Code | 通用 AI（Trae/WorkBuddy） |
|---|---|---|
| 内置鸿蒙知识库检索 (`arkts_knowledge_search`) | ✅ | ❌（需联网搜） |
| ArkTS 静态语法检查 | ✅ | ⚠️ 靠复制来的 skill |
| 编译日志分析 | ✅ | ⚠️ 需把日志塞进上下文 |
| 管文件 / 写文档 / GitHub 操作 | ⚠️ 弱 | ✅ 强 |

**分工原则**：知识能共享（复制 skill），行动能外包（`deveco run` 把编译/修 bug 整段丢给它）。

---

## 二、Skill 状态（已集成到 TRAE）

以下 DevEco Code skill 已复制到 `~/.trae-cn/skills/`，**Agent 可直接调用**，无需额外安装：

| Skill | 用途 | 文件数 |
|---|---|---|
| `arkts-error-fixes` | 21 种 ArkTS 编译错误修复方案 | 30+ |
| `arkts-grammar-standards` | ArkTS 语法规范、TS→ArkTS 改写、UI 质量检查 | 8 |
| `arkts-runtime-fix` | jscrash、运行时崩溃、faultlog 诊断、hilog 收集 | 20+ |
| `deveco-create-project` | 从零创建 ArkTS 工程模板 | 全套 |
| `harmonyos-deveco-bridge` | 协调 TRAE 与 DevEco Code，利用免费 GLM-5.1 | 1 |

**使用方式**：遇到对应场景时，TRAE 会自动加载相关 skill。例如修改 `.ets` 文件前，`arkts-grammar-standards` 会自动提供语法约束提示。

---

## 三、`deveco run` 委派（主路径）

如果本地 skill 无法解决，用 `deveco run` 一句话外包给免费 GLM-5.1：

```bash
# 示例：分析 ArkTS 编译错误
deveco run "当前工程 ArkTS 编译报错：Property 'magnitude' does not exist on type 'StellariumBridgeResponse'。请给出修复方案。" --format json

# 示例：鸿蒙 UI 规范咨询
deveco run "ArkTS 中 Row 嵌套 Scroll 时如何正确处理 hitTestBehavior？" --format json
```

**Token 账单实证**（2026-07-21 实测）：
- 13822 输入 token（系统提示 + 鸿蒙知识检索）全算在 DevEco Code 免费额度上
- Trae 只收最终答案（约 200 token）
- 省约 **200 倍**

**前置条件**：
1. `npm install -g @deveco/deveco-code`
2. `deveco providers login`（OAuth 授权，一次即可）
3. 确保 `~/.zshrc` 有 `eval "$(/opt/homebrew/bin/brew shellenv)"`

---

## 四、底层命令直接调用（最省 token）

编译、部署、截屏不需要 AI，纯命令行：

```bash
# 编译 HAP
cd build/libstellarium-harmonyos
env NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
  JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
  OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk \
  hvigorw assembleHap --no-daemon

# 部署到设备
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap

# 截屏验证 UI
hdc shell snapshot_display -f /data/local/tmp/ui.jpeg
hdc file recv /data/local/tmp/ui.jpeg /tmp/ui.jpeg
```

---

## 五、Agent 决策树

```
遇到鸿蒙相关问题？
    │
    ├─ 是 ArkTS 编译/语法错误？
    │   ├─ 先查本地 skill（arkts-error-fixes / arkts-grammar-standards）
    │   └─ 复杂/罕见错误 → deveco run 外包分析
    │
    ├─ 是运行时崩溃/白屏？
    │   └─ 查 arkts-runtime-fix skill，或 deveco run 分析 hilog
    │
    ├─ 是鸿蒙 UI/设计规范问题？
    │   └─ deveco run 外包（内置知识库比联网搜准）
    │
    ├─ 是编译 / 部署 / 截屏？
    │   └─ 直接用 hvigorw / hdc 命令，零 token
    │
    └─ 是写代码 / 改代码？
        └─ 自己能写就写，不确定时查 skill 或 deveco run 确认
```

---

## 六、GitHub Actions 整合

项目已配置 `.github/workflows/ohos-pr-check.yml`，PR 修改 ETS 文件时自动：
- 检查 ArkTS 文件是否有明显语法问题
- 提醒开发者是否已用 deveco 检查过
- 验证修改是否同步到了 git-tracked 备份目录

---

## 七、踩坑记录

| 问题 | 现象 | 解决 |
|---|---|---|
| deveco 命令找不到 | `zsh: command not found: deveco` | 确保 `~/.zshrc` 有 Homebrew PATH，`source ~/.zshrc` |
| 未登录报错 | `ProviderNoProvidersError` | 先执行 `deveco providers login` |
| ACP 走不通 | `deveco acp` 启动后立即退出 | 它是 stdio 客户端模式，需被 ACP 客户端驱动；单独启动会自杀。暂不使用。 |
| MCP 方向反了 | `deveco mcp` 是 MCP 客户端 | 它消费外部 MCP 服务器，不能把自己暴露成服务器给 Trae 调用 |

---

> **最后更新：** 2026-07-21
> **关联文档：** [AGENTS.md](AGENTS.md)、[CHANGELOG.md](CHANGELOG.md)
