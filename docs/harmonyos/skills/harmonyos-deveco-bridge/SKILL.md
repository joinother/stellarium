---
name: "harmonyos-deveco-bridge"
description: "协调 TRAE 与 DevEco Code 完成鸿蒙开发任务，利用 DevEco Code 的免费 GLM-5.1 模型和鸿蒙知识库减少 TRAE token 消耗。Invoke when user mentions HarmonyOS, 鸿蒙, ArkTS, ArkUI, DevEco, Hvigor, or any HarmonyOS development task."
---

# HarmonyOS DevEco Bridge

## 作用

本 Skill 用于在 TRAE 中调用本地已安装的 DevEco Code (`/opt/homebrew/bin/deveco`)，将鸿蒙专属开发任务外包给 DevEco Code 的免费 GLM-5.1 模型处理，从而节省 TRAE 的模型 token 消耗。

DevEco Code 拥有 2000 万字鸿蒙官方知识库和 7 个 HarmonyOS 专属工具，在鸿蒙代码生成、语法检查、构建调试、多设备适配等场景下比通用 AI 更精准。

## 触发条件

当用户提到以下关键词或需求时，自动加载本 Skill：
- HarmonyOS / 鸿蒙 / 鸿蒙开发 / 鸿蒙应用
- ArkTS / ArkUI / ArkUI-X
- DevEco Studio / DevEco Code / Hvigor
- HDC / 鸿蒙模拟器 / 鸿蒙真机调试
- 鸿蒙页面 / 鸿蒙组件 / 鸿蒙工程

## 工作流

### 第一步：识别任务类型

判断用户的鸿蒙开发需求属于哪一类：

| 任务类型 | 特征 | 处理策略 |
|---------|------|---------|
| **代码生成** | 创建页面、组件、工程 | 交给 DevEco Code 生成骨架，TRAE 做润色 |
| **语法检查** | 修复报错、检查语法 | 直接用 `deveco run` 调用 `arkts_check` |
| **知识查询** | API 用法、组件属性 | 交给 DevEco Code 查询知识库 |
| **编译构建** | build、打包、签名 | 调用 DevEco Code 的 `build_project` |
| **UI 验证** | 界面是否符合需求 | 调用 DevEco Code 的 `verify_ui` |
| **多设备适配** | 折叠屏、手表、平板 | 调用 DevEco Code 的适配能力 |
| **端到端交付** | 从需求到完整功能 | 使用 DevEco Code Goal 模式 |

### 第二步：调用 DevEco Code

通过终端命令调用 DevEco Code：

```bash
# 通用任务
deveco run "你的鸿蒙开发需求描述"

# 示例
deveco run "创建一个鸿蒙登录页面，使用 ArkUI 的 Column + TextInput + Button"
deveco run "检查 src/main/ets/pages/Index.ets 的语法错误"
deveco run "将当前工程适配到折叠屏"
```

**调用前检查：**
1. 确认 deveco 可执行：`/opt/homebrew/bin/deveco --version`
2. 确认用户在鸿蒙工程目录下（检查是否有 `build-profile.json5` 或 `hvigorfile.ts`）
3. 如果不在工程目录，先使用 `switch_cwd` 或提示用户切换

### 第三步：处理返回结果

DevEco Code 返回的结果需要经过以下处理：

1. **提取代码**：如果返回中包含代码块，提取并格式化
2. **验证可用性**：检查代码是否符合 ArkTS 语法规范（可再次调用 `arkts_check`）
3. **整合到项目**：将代码写入正确的文件路径
4. **补充 TRAE 优势**：
   - 添加详细注释和文档
   - 编写单元测试
   - 做跨平台对比（如与 iOS/Android 的类似实现）
   - 生成 README 或技术方案文档

### 第四步：Token 节省统计

记录本次任务节省的 TRAE token 消耗：
- 简单查询（1-2 轮对话）：约节省 500-1000 tokens
- 代码生成（多文件）：约节省 2000-5000 tokens
- 端到端交付（完整功能）：约节省 5000-10000+ tokens

## 具体场景指令

### 场景 1：从零创建鸿蒙工程

```
用户：帮我创建一个鸿蒙待办事项应用

执行：
1. deveco run "创建一个鸿蒙待办事项应用，包含添加、删除、标记完成功能，使用 ArkUI 开发"
2. 等待 DevEco Code 返回工程结构和代码
3. 检查返回结果的完整性
4. 将代码写入本地文件
5. 用 TRAE 补充：添加 README.md、编写测试用例、生成技术方案文档
```

### 场景 2：修复编译错误

```
用户：我的鸿蒙工程编译报错了

执行：
1. 先查看错误日志（如果有）
2. deveco run "修复以下编译错误：[错误信息]"
3. 或者调用语法检查：deveco run "对当前工程执行 arkts_check"
4. 应用修复方案
5. 验证修复结果
```

### 场景 3：多设备适配

```
用户：帮我适配折叠屏

执行：
1. deveco run "将当前工程适配到折叠屏，使用 ArkUI 的响应式布局"
2. 获取适配后的代码
3. 检查是否使用了 Display、windowSize 等 API
4. 用 TRAE 补充：生成适配说明文档、对比不同设备的实现差异
```

### 场景 4：知识查询

```
用户：ArkUI 的 List 组件怎么实现下拉刷新？

执行：
1. deveco run "ArkUI 的 List 组件如何实现下拉刷新功能？"
2. DevEco Code 利用 2000 万字知识库返回准确答案
3. 用 TRAE 补充：提供完整示例代码、解释原理、对比其他框架的实现
```

## 注意事项

1. **DevEco Code 限制**：
   - GLM-5.1 免费模型每分钟限 50 次请求
   - 需要华为账号登录（首次使用需引导用户登录）
   - 编译构建和真机调试需要 DevEco Studio（检查 `DEVECO_HOME` 环境变量）

2. **路径问题**：
   - DevEco Code 安装在 `/opt/homebrew/bin/deveco`
   - 如果命令找不到，检查 PATH 是否包含 `/opt/homebrew/bin`

3. **结果质量**：
   - DevEco Code 的代码生成质量高，但可能需要手动调整
   - 始终建议对生成的代码进行人工 review

4. **TRAE 与 DevEco Code 分工**：
   - **DevEco Code 负责**：鸿蒙专属知识、代码生成、语法检查、构建、设备调试
   - **TRAE 负责**：通用逻辑、跨平台对比、文档生成、测试编写、项目管理

## 配置项

如需自定义 DevEco Code 配置，编辑 `~/.config/deveco/deveco.jsonc`：

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "deveco": {
      "name": "DevEco Code",
      "models": {
        "glm-5": {
          "tool_call": true
        }
      }
    }
  }
}
```
