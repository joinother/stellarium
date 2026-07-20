# Phase 2 步骤0 — 环境确认（交付物）

**负责人**：包立成（鸿蒙构建与发布专家）
**路线**：A — Qt 整包移植（Qt 6.12 HarmonyOS → 纯血鸿蒙 三端）
**目标**：在你自己的 Mac / Windows 上，反复、无负担地确认前置环境齐不齐。

---

## 一、本目录交付物

| 文件 | 作用 |
|------|------|
| `check_env.sh` | best-effort 环境探测脚本，逐项打印 ✅/⚠️ 与说明，**永远以 0 退出**，可反复跑 |
| `README.md` | 本说明：如何运行、各项不达标的补救方法 |

探测的 5 个前置项（与 Phase 2 步骤0 对齐）：

1. **DevEco Studio >= 6.1.0 (Release)**
2. **HarmonyOS SDK API level >= 23**
3. **Qt 6.12.0 Beta2 已装且含 `harmonyos_arm64_v8a` 组件**
4. **`harmonydeployqt` 可执行存在**（Qt macos 宿主构建 bin 下）
5. **`ohos-additional-packages` 第三方预编译包就位且非空**

> 约定：脚本只做"尽力探测"。任何一项探测不到都给 **⚠️ + 手动确认指引**，绝不因未达标而 `exit 1`，方便你一边补漏一边重跑，直到只剩 ✅。

---

## 二、如何运行

在 `00-环境确认/` 目录内：

```bash
chmod +x check_env.sh
./check_env.sh
```

Windows（Git Bash / WSL / Cygwin 终端）同样可直接 `bash check_env.sh`。
脚本会自动识别平台（mac / win / linux），分别走对应探测路径。

可选环境变量（覆盖默认探测根目录）：

```bash
export QTDIR="$HOME/QtSDK"            # Qt 安装根目录，默认 ~/QtSDK，回退 ~/Qt
export OHOS_SDK_ROOT="$HOME/ohos-sdk" # OpenHarmony SDK 自定义根（其下应有 openharmony/<api>）
./check_env.sh
```

---

## 三、各项不达标的补救方法

### a) DevEco Studio 需 6.1.0 (Release)
- **下载**：华为开发者联盟官网 → DevEco Studio → 下载 6.1.0 Release 版
  （https://developer.huawei.com/consumer/cn/deveco-studio/ ）
- **安装**：
  - Mac：拖入 `/Applications`，即 `/Applications/DevEco-Studio.app`
  - Windows：建议装到 `C:\Program Files\Huawei\DevEco Studio`
- **说明**：6.1.0 Release 是 HarmonyOS SDK API 23 的配套版本，请勿用旧版或 Canary。

### b) HarmonyOS SDK API 23
- 打开 DevEco Studio → **Settings / Preferences → SDK Manager → OpenHarmony**，
  勾选并安装 **API 23**（对应 HarmonyOS NEXT / API level 23）。
- SDK 默认位置：
  - Mac：`~/Library/OpenHarmony/Sdk/openharmony/23`
  - Windows：`%LOCALAPPDATA%\OpenHarmony\Sdk\openharmony\23`
- 若 SDK 装在自定义目录，运行脚本前 `export OHOS_SDK_ROOT=<你的 SDK 根>`。

### c) Qt 6.12.0 Beta2 + HarmonyOS 组件
- **在线安装器**：从 Qt 官方下载 Qt Online Installer，登录后选择
  **Qt 6.12.0 Beta2** → 在组件树里勾选 **HarmonyOS** 目标，安装 `harmonyos_arm64_v8a`。
- **安装根建议**：`~/QtSDK/6.12.0/harmonyos_arm64_v8a`
  （若装在别处，用 `export QTDIR=<Qt 根>` 指向它）。
- 验证：该目录下应有 `bin/qmake`、`lib/` 等。

### d) harmonydeployqt
- 它随 **Qt macos 宿主构建** 提供，位于：
  `~/QtSDK/6.12.0/macos/bin/harmonydeployqt`
- 如果只装了 HarmonyOS 目标而没装 macos 宿主构建，qt 工具链里就没有它：
  回到安装器，确保 **Qt 6.12.0 的 macos 宿主组件** 也勾选安装。
- Windows 宿主对应 `mingw_64/bin/harmonydeployqt.exe`。

### e) ohos-additional-packages（第三方预编译包）
- **作用**：Stellarium 依赖的官方预编译第三方库（如 zlib、libpng、openssl 等的 OHOS 版）。
- **下载**（任选其一，以主理人最新公告为准）：
  - 百度网盘：`https://pan.baidu.com/s/xxxx`（提取码见团队公告）
  - Google Drive：`https://drive.google.com/drive/folders/xxxx`
- **放置路径**：
  ```
  ~/.local/opt/ohos/additional-packages
  ```
  即展开后该目录**非空**（里面是各第三方库文件夹）。
  - Mac 上 `~` 即 `/Users/<你>`
  - Windows 上 `~` 即 `C:\Users\<你>`，如 `C:\Users\<你>\.local\opt\ohos\additional-packages`
- 如网盘链接失效，找主理人或在团队仓库的 `phase2/00-环境确认` 公告处获取最新地址。

---

## 四、判读建议

- 全绿（只剩 ✅）：可以进入 Phase 2 步骤1「获取 Stellarium 源码与 Qt 工程」。
- 有 ⚠️：按上面第三节对应条目补齐后，重跑 `./check_env.sh`。
- 脚本不联网、不改任何文件，纯本地探测，可放心反复执行。
