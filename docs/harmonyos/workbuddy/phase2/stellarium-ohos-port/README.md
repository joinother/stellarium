# Stellarium → 纯血鸿蒙（HarmonyOS NEXT）全量移植工具包

> 由「Stellarium 鸿蒙移植专家团」交付 · Phase 2 全量移植
> 路线 A：Qt 整包移植（用官方鸿蒙版 Qt 重新编译 Stellarium 桌面开源版）

---

## 一、一句话结论

**这事能成，而且不用重写界面。** 我们已查证：鸿蒙官方 Qt（6.12 Beta2）支持 Qt Widgets，而 Stellarium 桌面版正好是用 Widgets 写的——所以把它的源码用鸿蒙工具链重新编译成 `.hap`，星星就能在华为手机/平板/电脑上显示。本工具包就是把"编译+打包+签名部署"全流程自动化好的脚本与补丁，你本地照跑即可。

---

## 二、我们查证过的硬事实（决定了下面的设计）

**鸿蒙版 Qt 支持（来自 Qt 官方 Wiki 模块清单与示例）：**
- 支持：Core / Gui(含 OpenGL) / **Widgets** / Concurrent / Network / Sql / Svg / Qml / Quick / QuickControls
- 永远不可用（Out of scope）：**WebEngine**（在线百科）、**VirtualKeyboard**（虚拟键盘）
- 安装包通常不含、需自行交叉编译或关功能：Charts / Multimedia / Sensors / Positioning / SerialPort / Speech

**Stellarium 真实构建选项（已读其 CMakeLists.txt）：**
- 默认开启：QTWEBENGINE、SPEECH、GPS、INDI、MEDIA、SHOWMYSKY、XLSX、NLS、SCRIPTING；插件 TELESCOPECONTROL；GUI 模式 Standard
- 第 632 行**无条件** REQUIRE Qt 的 `Positioning` 组件（关掉 GPS 后它其实不再被使用，但会卡住配置）

---

## 三、我们的移植策略（全权替你拍板）

| 类别 | 处理 | 理由 |
|---|---|---|
| WebEngine / VirtualKeyboard | 关闭 / 绕开 | OHOS 永不提供，无替代就关 |
| GPS（Positioning） | 关闭 | OHOS Qt 无 Positioning；已出具补丁移除其 REQUIRE |
| INDI / 望远镜串口 | 关闭 | OHOS Qt 无 SerialPort；移动端望远镜控制非必需 |
| Speech / Media | 关闭 | OHOS Qt 默认无对应模块；关掉不影响看星星 |
| ShowMySky / XLSX / NLS | 关闭 | 大气模型、表格、多语言属增强项，首版从简 |
| **Qt Charts** | **自动交叉编译** | AstroCalc 图表强依赖；脚本探测不到就现场编并装进 OHOS Qt |
| 核心渲染 / 星表 / 星座 / 深空 / 脚本 / 触屏 | **保留** | 看星星主链路，一个不少 |

**主链路零损失**：星空渲染、星表、星座连线、深空天体、AstroCalc（图表）、脚本、触屏拖拽旋转/缩放全部可用。

---

## 四、工具包里有什么（9 个文件）

```
stellarium-ohos-port/
├── build/
│   ├── ohos-build-stellarium.sh   <- 主脚本：一键完成 探测→补丁→编译→打包→修 module.json5
│   ├── build-qt-addons-ohos.sh     <- 给 OHOS Qt 交叉编译 qtcharts（等）并安装进 Qt 前缀
│   └── stellarium-ohos.cmake       <- 工具链与开关的集中缓存默认值（兜底）
├── patches/
│   ├── 0001-ohos-cmake-adapt.patch <- 让 CMake 在关掉 GPS 后不再强求 Positioning
│   └── FEATURES_DISABLED.md        <- 被关闭功能的逐条说明与替代方案
└── deploy/
    ├── patch-module-json5.py       <- 自动给生成的工程加三端设备类型 + 传感器权限
    ├── DEPLOY.md                   <- 你在 DevEco 里签名、装到平板的傻瓜步骤
    ├── QA-CHECKLIST.md             <- 手机/平板/电脑三端逐项验收表
    └── TROUBLESHOOT.md             <- 报错怎么贴回来给我们修 + 常见报错速查
```

---

## 五、你（在本地电脑）怎么跑——只需 3 步

> 前提：你已装好 DevEco Studio 6.1.0、鸿蒙 SDK API 23、Qt 6.12.0 Beta2（勾了 HarmonyOS 组件）、附加包放 ~/.local/opt/ohos/additional-packages，平板已 USB 连接。

```bash
# 1) 准备 Stellarium 源码（必须 git 克隆，因为要打补丁）
git clone --depth 1 https://github.com/Stellarium/stellarium ~/stellarium-src

# 2) 跑主脚本（把源码路径传给它即可，其余路径脚本自动探测）
bash stellarium-ohos-port/build/ohos-build-stellarium.sh ~/stellarium-src
```

脚本会自动：校验工具链 → 探测缺哪些 Qt 模块 → 缺 Charts 现场编 → 应用补丁 → 关掉不可用的功能 → qt-cmake 配置并编译 → harmonydeployqt 生成 DevEco 工程 → 修补 module.json5。

```bash
# 3) 打开生成的工程签名装机（详见 deploy/DEPLOY.md）
#    用 DevEco 打开 ~/stellarium-src/build/libstellarium-harmonyos
#    -> 登录华为开发者账号 -> 自动签名 -> 选已连接的平板 -> 点 Run
```

看到一片能拖着转的星空，就成功了。

---

## 六、一句必须说清的实话

**这个环境（沙箱）里没有 Qt 鸿蒙 SDK、没有 DevEco、也没有你的平板，所以"编译+签名+装真机"这最后一步只能在你自己电脑上发生**——我们已经把它简化成上面 3 步。

如果第 2 步或第 3 步蹦出红字：**把最上面 20–30 行报错截图或复制贴回来给我们**，专家团会改脚本/补丁/代码，再让你重新跑。这就是"报错回填→AI 修复"的闭环（见 deploy/TROUBLESHOOT.md）。除了你点那一下、贴一下报错，中间的活全归我们。

---

## 七、已知风险（先交底）

1. **Qt 鸿蒙版仍 Beta**：可能遇到官方都还没填平的坑，届时按报错迭代。
2. **着色器兼容**：Stellarium 桌面用 OpenGL 着色器，鸿蒙是 OpenGL ES 3.2；若渲染报错，由苏星图专门适配 GLES。
3. **Charts 自编译**：若你的网络取不到 qtcharts 源码，可改用 Stellarium 旧版（v24.x）+ Qt 5.15 鸿蒙开源版（该版 Qt 自带 Charts），详见 TROUBLESHOOT 备选方案。

---

_专家团成员：乔渡星（主理人）· 匡编译（Qt 编译）· 苏星图（源码架构）· 包立成（签名部署）· 赖库通（依赖编译）· 严三端（三端验收）_
