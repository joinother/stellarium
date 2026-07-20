# Stellarium 鸿蒙移植 · Phase 2 进度汇总

> **阶段**：Phase 2 — 工程脚手架与编译前置（进行中）
> **调度**：乔渡星（主理人）统筹，三位成员并行产出
> **日期**：2026-07-19
> **重要前提**：本沙箱无 Qt 鸿蒙 SDK / DevEco，以下均为**可在用户本地环境直接编译运行的工程骨架与脚本**，真编译验证由用户在自己的电脑完成。

---

## 一、本轮专家团产出（文件树）

```
phase2/
├── 00-环境确认/
│   ├── check_env.sh        # 包立成：跨 Mac/Windows 探测 5 项前置环境，恒以 0 退出
│   └── README.md           # 运行方式 + 各项不达标补救指引
├── stellarium-poc/         # 匡编译 + 苏星图：最小渲染验证工程
│   ├── CMakeLists.txt      # qt-cmake + SHARED(.so)导出 main + QT_HARMONYOS_TARGET_ARCHS
│   ├── module.json5        # phone/tablet/2in1 + 传感器权限预留
│   ├── build_ohos.sh       # qt-cmake → cmake build → harmonydeployqt 示例
│   ├── README.md           # 本地编译运行步骤 + 预期现象
│   └── src/
│       ├── main.cpp        # QGuiApplication + QQmlApplicationEngine 入口
│       ├── stel_poc.qml    # DragHandler 单指/鼠标拖拽旋转
│       ├── stelrenderer.h/.cpp  # QQuickItem + QSGRenderNode 走 GLES 3.2 画旋转星点
└── 依赖与验收/
    ├── 依赖交叉编译清单.md   # 赖库通：11 个第三方库 + 6 个 Qt 冲突模块逐项处置
    └── 三端验收checklist.md  # 严三端：手机/平板/电脑 9 类可勾选验收项
```

## 二、各成员交付说明

| 成员 | 交付物 | 用途 |
|---|---|---|
| 包立成 | `00-环境确认/` | 你本地一键跑 `./check_env.sh`，看 DevEco 版本/SDK API/Qt6.12/部署工具/附加包是否齐 |
| 匡编译 + 苏星图 | `stellarium-poc/` | 最小可编译工程：验证 GLES 渲染 + harmonydeployqt 打包 + 触屏旋转，不打全量 Stellarium |
| 赖库通 | `依赖交叉编译清单.md` | 明确哪些库被官方包覆盖、哪些需 vcpkg OHOS 编译、哪些可禁用 |
| 严三端 | `三端验收checklist.md` | 三端安装/渲染/交互/传感器/性能验收标准，便于你逐项打勾 |

## 三、你这边下一步（两步走）

**第 1 步：确认环境（5 分钟）**
1. 进终端，跑：
   ```bash
   cd /Users/jiexuanyang/WorkBuddy/2026-07-19-01-20-21/phase2/00-环境确认
   chmod +x check_env.sh && ./check_env.sh
   ```
2. 看输出，把 ⚠️ 项按 README 补齐（主要是确认 DevEco=6.1.0、Qt6.12 勾了 HarmonyOS 组件、附加包就位）。

**第 2 步：编译最小 PoC（验证链路）**
1. 按 `stellarium-poc/README.md`，用 qt-cmake 配置 → cmake build → harmonydeployqt 打包。
2. 用 DevEco 打开生成的工程，签名后运行到模拟器/真机。
3. 预期：看到可旋转的星点/球体，触屏能拖着转。✅ 则此路打通，进入全量 Stellarium 编译。

## 四、当前风险与注意

- **Beta 坑**：Qt 6.12 HarmonyOS 仍 Beta，PoC 若编译/运行报错，先定位是工具链问题还是代码问题，记录后反馈专家团。
- **PoC 非全量**：它只验证"能渲染+能打包+能触屏"，不含真实星表；全量 Stellarium 编译是下一子阶段。
- **沙箱限制**：以上文件本环境未真编译，属待验证脚手架；首次在你本地编译可能需微调路径/版本。

## 五、下一步子阶段（待你验证 PoC 通过后）

全量 Stellarium 编译 + 冲突模块裁剪（WebEngine/Positioning/SerialPort 等按清单关闭或替换）→ 触屏/传感器适配 → 资源打包三端验证 → 你签字上架。

---

*本汇总由主理人乔渡星记录。专家团持续待命中。*
