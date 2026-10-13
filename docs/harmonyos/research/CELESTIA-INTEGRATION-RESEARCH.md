# Celestia Mobile 集成预研

> 研究日期：2026-08-29
> 目标：评估是否将 Celestia Mobile 相关代码用于独立的三维太阳系模式，同时保持 Stellarium 星图、天文计算和插件系统的业务边界。

## 结论

暂不把 Celestia Mobile 整体引入当前 HAP。当前需求中的行星详情球体、纹理、自由旋转、缩放和晨昏线，现有 Stellarium 原生渲染及鸿蒙离线球面渲染已经能够承载；引入第二套完整天文核心会增加包体、内存、启动时间、坐标转换和资源校验成本，也会让两个时间系统、选中系统和相机系统互相争抢状态。

如果后续确定增加“独立三维太阳系探索”模式，采用一个独立的 `Astro3DSession` 适配层。Celestia 只负责三维场景的计算与渲染，Stellarium 仍是星图、天文计算、位置、插件和脚本的权威来源。两者通过版本化快照和事件传递少量状态，不共享内部对象指针、渲染上下文或主循环。

## 仓库职责与优先级

| 优先级 | 仓库 | 主要内容 | 对本项目的用途 | 不能直接复用的部分 |
| --- | --- | --- | --- | --- |
| 1 | [Celestia](https://github.com/celestiamobile/Celestia) | C++ 三维宇宙核心和桌面实现，GPL-2.0 | 研究行星系统、轨道、模型、光照、阴影和资源格式 | 不能作为当前 Stellarium 核心的替换品；仍需单独做鸿蒙渲染适配 |
| 2 | [AndroidCelestia](https://github.com/celestiamobile/AndroidCelestia) | Kotlin/Compose 应用、JNI C++ 层、移动端 GLES 渲染宿主，GPL-2.0 | 最接近鸿蒙移动设备的线程、生命周期、触摸和资源加载参考 | Android Activity、Compose、JNI、Gradle 和 Android 权限不能直接搬到 ArkTS/HAP |
| 3 | [MobileCelestia](https://github.com/celestiamobile/MobileCelestia) | Swift 应用、UIKit、AsyncGL、CelestiaCore、iPad/macOS 交互，GPL-2.0 | 参考 iPad 三维模式、独立显示控制器、手势控制、加载状态和会话管理 | Swift/UIKit、Metal/OpenGLES 宿主和 Apple 生命周期不能直接搬到 ArkUI |
| 4 | [CelestiaCore](https://github.com/celestiamobile/CelestiaCore) | Apple 平台的 Objective-C++ 包装层和对象 API，GPL-2.0 | 参考“核心与 UI 分离”的 API 形状 | 它是 Apple 桥接层，不是鸿蒙可直接链接的库 |
| 5 | [CelestiaDependency](https://github.com/celestiamobile/CelestiaDependency) | Celestia 构建所需的依赖封装 | 识别第三方依赖和许可证，评估移植工作量 | 不能未经逐项许可审计直接打进 HAP |
| 6 | [AsyncGL](https://github.com/celestiamobile/AsyncGL) | 异步 OpenGL 执行器，MIT | 参考渲染线程与 UI 线程隔离 | API、上下文和鸿蒙 XComponent 生命周期不同，不能直接假设可用 |
| 7 | [CelestiaUWP](https://github.com/celestiamobile/CelestiaUWP) | C++/WinUI Windows 宿主，GPL-2.0 | 参考桌面窗口、键鼠和 WinUI 的渲染宿主组织 | WinUI、UWP 和 Windows 图形接口与鸿蒙无关 |
| 8 | [CelestiaApp](https://github.com/celestiamobile/CelestiaApp) | macOS Swift 应用，GPL-2.0 | 仅在未来做桌面版适配时参考 | 平台耦合强，不作为移动端起点 |
| 9 | [celestia.mobi](https://github.com/celestiamobile/celestia.mobi)、[celestia-web](https://github.com/celestiamobile/celestia-web) | 网站 HTML/CSS/JS | 只能参考网页展示内容和资源目录 | 不包含可嵌入鸿蒙的三维核心 |
| 10 | `CelestiaLocalization`、`celestia-i18n`、`celestia-mobi-content-localization` | 本地化和网页语言资源 | 参考语言资源组织方式和译文来源 | 不能覆盖当前 Stellarium 自带的天空文化和翻译资源 |
| 11 | `angle-*`、`windows-dependencies`、`apple-android-dependencies`、`vcpkg`、`release` | 平台依赖、预编译 ANGLE 和发布脚本 | 只用于后续构建可行性调查 | 不应将 Android/Windows 预编译库当作鸿蒙二进制依赖 |

## 为什么 Android 版排在 Apple 版之前

AndroidCelestia 的应用层是 Kotlin/Compose，底层是 C++ + JNI + OpenGL ES，设备形态、触控和移动生命周期与鸿蒙更接近。它适合研究：

- native renderer 如何独立于 UI 状态运行；
- 资源解压、缓存、失败重试和前后台恢复；
- 触控、键鼠、面板和三维相机的事件分发；
- Java/Kotlin 与 C++ 之间只传对象路径、时间、相机和动作。

MobileCelestia 对 iPad 交互更有参考价值。它把 `CelestiaDisplayController`、`CelestiaInteractionController` 和 `StateManager` 分开，并使用初始化等待队列、独立绘制循环、搜索/跳转/脚本请求队列。这个架构思想应当移植，Swift/UIKit 代码本身不应移植。

## 当前工程已经具备的可复用边界

当前 Stellarium 命令桥已经能提供以下权威数据：

- `getSessionState`：JD、观测位置、J2000 视线、FOV、选中英文 ID 和关键显示状态；
- `getSelectedObjectInfo`：稳定选中目标、类型、结构化详情和详情媒体；
- `getObjectDetailModel`：详情模型能力契约和二维资源回退；
- `setJD`、`setTimeRate`、`searchObject`、`moveToSelected`：现有星图控制；
- `getCommandCatalog`：CLI、脚本和 ArkUI 共享的机器可读命令目录。

因此三维模式不需要读取 Stellarium 的内部 C++ 对象，也不需要让 Celestia 直接操作主星图。第一版适配器只读取快照，用户明确点击“同步时间”或“在星图中定位”时才发送单向动作。

## 建议的状态边界

```text
Stellarium authority
  time: JD / timeRate
  observer: planet / latitude / longitude / altitude
  target: stable English object ID / selected type
  sky view: J2000 direction / FOV
        |
        | Astro3DSession snapshot + explicit events
        v
Celestia 3D authority
  scene camera / model pose / render quality
  local 3D resource state
  local animation playback
```

必须禁止以下耦合：

- Celestia 的时间步进不得偷偷修改 Stellarium 的 JD；
- Celestia 的选中不得自动触发星图避让、跟踪或居中；
- 3D 相机拖动不得改变星图视线，除非用户点击“同步到星图”；
- 两个渲染器不得共用 EGL/OpenGL context、帧定时器或纹理所有权；
- Celestia 的网络资源、插件商店、推送和在线 Add-on 逻辑不得进入未备案离线 HAP。

## 共享协议

机器可读协议已落在 `data/ohos/celestia-bridge-contract.json`。协议只描述边界，不代表 Celestia 已经接入运行时。

### 输入快照

- `schemaVersion`：协议版本；
- `jd`、`timeRate`：模拟时间和时间速率；
- `observer`：观测所在星球及位置；
- `target`：稳定英文 ID、显示名和对象类型；
- `skyView`：J2000 视线和 FOV，仅作为“从星图进入三维模式”的初始视角；
- `locale`：界面语言提示，不把翻译资源交给第二套核心接管；
- `offline`：必须为 `true`。

### 回传事件

第一阶段只允许 `ready`、`failed`、`closed`、`targetRequested` 和 `timeSyncRequested`。回传请求必须经过适配器和现有 CLI/命令桥，不能直接写 Stellarium 状态。所有事件都带 `requestId`、`schemaVersion` 和 `source`，防止旧异步结果覆盖新状态。

## 分阶段实施

1. **阶段 A：只做当前详情模型**。继续使用现有离线球面渲染；补充资源校验、交互测试和失败回退，不引入 Celestia。
2. **阶段 B：建立独立 3D 页面骨架**。只实现 `Astro3DSession`、快照显示、关闭恢复和 CLI 状态查询，先用现有行星纹理验证生命周期。
3. **阶段 C：验证 Celestia 核心**。在独立实验工程中编译 `Celestia` 核心，确认 OpenGL ES、C++ 标准库、模型格式、阴影和内存占用；不改主 HAP 的签名和业务配置。
4. **阶段 D：单目标接入**。只接入太阳、地球、月球和一个时间同步动作；所有模型和纹理必须有离线许可证、SHA-256 和大小记录。
5. **阶段 E：扩展太阳系**。完成轨道、行星模型、晨昏线、阴影和相机控制后，再评估是否值得加入更多 Celestia 资源。

## 合规与离线要求

`AndroidCelestia`、`MobileCelestia`、`CelestiaCore`、`Celestia` 和 `CelestiaUWP` 页面均标注 GPL-2.0。若将其代码或修改后的核心链接进可分发 HAP，需要保留版权和许可证，并按 GPL 义务准备对应源代码、修改说明和第三方许可清单；最终发布前应由项目负责人确认链接方式和发布策略。

Celestia Mobile 仓库还包含在线 Add-on、网页资源更新、推送通知和商店/订阅相关代码。这些不是三维核心的必要组成部分，当前未备案版本必须排除，不得因引入三维引擎而新增网络、推送或个人信息采集路径。

## 最终建议

实施顺序采用：**现有 Stellarium 三维详情能力 → 独立 `Astro3DSession` 骨架 → AndroidCelestia 的移动渲染架构参考 → Celestia 核心实验 → 再决定是否正式引入**。

不建议直接复制整个 Android 或 Apple 应用，也不建议把两个核心合并进同一套星图循环。这样既能获得 Celestia 的完整三维能力，又能保持星图、天文计算、插件、脚本、时间和离线合规边界清晰。
