# Stellarium 鸿蒙版 — 报错回填 → AI 修复闭环说明

> **核心机制**：本沙箱无法真编译/签名/部署（这些只能在用户本地 DevEco + 已连设备上做）。
> 因此采用「**用户本地跑 → 报错贴回 → AI 改代码/补丁/CMake → 重新出包**」的循环修复模式。

---

## 一、怎么把报错贴给 AI（标准姿势）

1. **在 DevEco 的 Build / Run 输出窗口**复制最上面 **20–30 行红色报错**（最关键的是第一条错误，往往决定根因）。
2. 或直接**截图**报错窗口贴回（确保文字清晰可读）。
3. 附带一句上下文：
   - 卡在「编译」还是「运行时」？
   - 哪端（手机/平板/鸿蒙电脑）？
   - 是否刚跑过 `patch-module-json5.py`、是否改过 `ENABLE_*` 开关？
4. 把以上内容发回给 AI（乔渡星 / 包立成 / 严三端），AI 会定位并给出补丁、CMake 开关或代码改动，你本地重跑 `ohos-build-stellarium.sh` 再出包验证。

> 一句话总结：**只贴红字最上面 20–30 行 + 一句上下文**，别贴整屏日志。

---

## 二、常见报错速查（给方向，不保证全覆盖）

| 报错关键词 | 可能原因 | AI 处理方向 |
|-----------|----------|-------------|
| `Could NOT find Qt6::Positioning` | Qt Positioning 模块未编/未找着 | 确认定位补丁已应用、`ENABLE_GPS=0` 已设；或补编 positioning |
| `Could NOT find Qt6::Charts` | 未编 Qt Charts | 运行 `build-qt-addons-ohos.sh` 编译 qtcharts 后再编 Stellarium |
| `WebEngine ... not found` / `TextToSpeech ... not found` | 未关闭对应模块 | 确认 `ENABLE_WEBENGINE=0`、`ENABLE_TEXTTOSPEECH=0` 等开关已置 0 |
| `shader / GLSL compile error` / `fragment shader failed` | GLES 着色器不兼容 | 提交渲染报错，AI 适配 GLES / 修着色器宏 |
| `module.json5 deviceTypes invalid` | 设备类型声明缺失/非法 | 重跑 `python3 patch-module-json5.py <工程目录>` |
| `signing failed` / 签名失败 | 华为开发者账号未登录 / 自动签名未开 / 证书过期 | 检查账号登录与 `Signing Configs → Automatically generate signature` 开关 |
| `hdc / device not found` | 设备未连接 / USB 调试未开 | 检查连线与开发者选项（见 DEPLOY.md 第 3 步） |
| `INSTALL_FAILED` 系列 | 签名不一致 / 旧包残留 | 卸载旧包后重装；确认调试证书一致 |
| `Permission denied` (传感器) | 权限未授予 | 设置里手动开传感器/网络权限（见 DEPLOY.md 第 5 步） |
| 运行时黑屏/花屏 | 渲染后端或纹理问题 | 提交截图+日志，AI 查渲染路径 |

---

## 三、闭环流转示例

```
用户本地: ohos-build-stellarium.sh → 出包 / 报错
      │
      │ 贴回「最上面 20–30 行红字 + 上下文」
      ▼
AI: 定位根因 → 改 CMake 开关 / 补丁 / 源码 → 给新改动
      │
      ▼
用户本地: 重跑 ohos-build-stellarium.sh → 重新出包 → DevEco 签名部署
      │
      ▼
验收 (QA-CHECKLIST.md) 通过 → 闭环结束
      │
      └─ 仍报错 → 再次贴回，进入下一轮
```

---

## 四、回填模板（建议直接复制使用）

```
【环节】编译 / 运行
【设备】手机 / 平板 / 鸿蒙电脑
【上下文】是否重跑 patch 脚本、是否改 ENABLE_*、Stellarium 版本
【报错】（DevEco 输出最上面 20–30 行红字，或截图）
```

> 越具体，AI 修复越快。模糊的“跑不起来”会拖慢闭环。
