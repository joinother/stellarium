# Stellarium 鸿蒙版 — 签名与部署手册（傻瓜版）

> **重要前提**：以下步骤**必须在你自己的电脑上的 DevEco Studio 里完成**，本沙箱环境无法真编译、无法签名、也无法连接你的实体设备。以下步骤假设你已完成 Phase 1/2 的本地编译（运行 `ohos-build-stellarium.sh` 并在 `build/libstellarium-harmonyos` 生成了 DevEco 工程）。

---

## 第 0 步：确认编译产物已生成

在 Stellarium 源码目录下确认：

```
ls build/libstellarium-harmonyos
```

能看到一个标准 DevEco 工程（含 `entry/`、`build-profile.json5`、`module.json5` 等）即表示编译成功。

若 `module.json5` 中 `deviceTypes` / `requestPermissions` 不齐，先补丁（主脚本通常已自动调用）：

```bash
python3 path/to/deploy/patch-module-json5.py build/libstellarium-harmonyos
```

---

## 第 1 步：用 DevEco 打开工程

1. 打开 **DevEco Studio**。
2. `File → Open`（或启动页 `Open Project`）。
3. 选择目录：`build/libstellarium-harmonyos`。
4. 等待 Gradle / Hvigor 同步完成（首次可能较慢，需联网下载依赖）。

---

## 第 2 步：配置签名

鸿蒙应用必须签名后才能装到设备。二选一：

### 方式 A：自动签名（推荐，最简单）
1. 顶部菜单 `File → Project Structure`（或 `Ctrl+Alt+Shift+S`）。
2. 左侧选 `Signing Configs`。
3. 勾选 **`Automatically generate signature`**（自动生成签名）。
4. 确认已登录**华为开发者账号**（未登录会提示登录；需要实名认证的华为开发者账号）。
5. 点击 `Apply` / `OK` 保存。

### 方式 B：手动签名
1. 在 `Signing Configs` 中取消自动，手动填入：
   - `Signing file (.p12)`：你已有的调试/发布证书
   - `Key alias` / `Key password`
   - `Profile (.p7b)`：对应设备授权的 Provision Profile
   - `Store password`
2. `Apply` / `OK` 保存。

> 调试阶段用**调试证书**即可，无需发布证书。

---

## 第 3 步：连接设备

- **平板 / 手机**：用 USB 线连接电脑，并在设备上开启「开发者模式 → USB 调试」。
- **鸿蒙电脑（2in1）**：同样开启开发者选项并连接，或使用远程设备。
- 在 DevEco 顶部设备选择栏，应能看到你的设备出现在列表里（状态为 Online）。

> 提示：本环境用户的平板已连接，正常应直接出现在设备列表。

---

## 第 4 步：部署运行

1. 确认设备已选中（顶部设备下拉框）。
2. 点击工具栏的 **Run ▶**（或 `Shift+F10`）进行安装并运行；
   若要调试观察日志，点 **Debug 🐞**（或 `Shift+F9`）。
3. 首次编译会生成 HAP 并自动安装到设备，随后自动启动 Stellarium。

---

## 第 5 步：首次运行权限处理

首次启动可能弹窗请求权限，或在运行中功能受限：

- **传感器权限（加速度计 / 陀螺仪）**：弹窗时点「允许」。若未弹窗但「指哪看哪」不灵，去系统
  `设置 → 应用 → Stellarium OHOS → 权限`，手动开启「传感器 / 运动数据」。
- **存储 / 网络权限**：星表在线更新需要网络，去同一权限页确认「网络」已允许。

---

## 第 6 步：三端验证

装好后按 `QA-CHECKLIST.md` 逐项验收（手机 / 平板 / 鸿蒙电脑各一节）。

---

## 常见问题

- **设备不显示**：重插 USB、确认 USB 调试已开、换线、或重装 HiSuite 驱动。
- **签名失败**：见 `TROUBLESHOOT.md` 的「签名失败」一节。
- **编译红字 / 运行崩溃**：把报错按 `TROUBLESHOOT.md` 格式贴回给 AI，进入「报错回填 → AI 修复」闭环。

---

> 本手册不替代华为官方 DevEco 文档，遇到版本差异以 DevEco 当前界面为准。
