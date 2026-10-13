# Windows 构建与装机指南（Stellarium HarmonyOS 移植）

本指南记录**在 Windows 上**从源码到真机运行的完整链路，全部命令均在本机实测通过。
`CODEX_BUILD_AND_INSTALL.md` 是 macOS 版本，路径、工具链宿主和 `rsync/ffmpeg` 依赖在
Windows 上都不成立，请以本文为准。

---

## 0. 已验证的环境

| 组件 | 版本 / 位置 |
| --- | --- |
| DevEco Studio | 26.0.0.821 @ `D:\Program Files\Huawei\DevEco Studio` |
| HarmonyOS SDK | HarmonyOS 26.0.0（API 26）@ `<DevEco>\sdk\default` |
| Hvigor / hvigor-ohos-plugin | 6.26.4 |
| Qt for HarmonyOS | 6.12.0 `harmonyos_arm64_v8a` @ `E:\Qt\6.12.0\harmonyos_arm64_v8a` |
| Qt 宿主（提供 `harmonydeployqt` / `moc`） | 6.12.0 `mingw_64` @ `E:\Qt\6.12.0\mingw_64` |
| OHOS native 工具链 | `clang 15.0.4` + `cmake 3.28.2` + `ninja` @ `<DevEco>\sdk\default\openharmony\native` |
| 真机 | HUAWEI Mate 80 Pro（SGT-AL00），HarmonyOS 7.0.0（API 26），`arm64-v8a` |

> 真机 ABI 必须是 `arm64-v8a`。本机模拟器镜像全部是 `x86`（`lists.json` 里 `"abi":"x86"`），
> 而 Qt for HarmonyOS 只提供 arm64 目标，**所以模拟器跑不了 Qt 星图**，只能用真机。

---

## 1. 一次性准备

### 1.1 生成构建工程

`harmonyos/` 只是被 git 跟踪的**源码镜像**（没有 `entry/` 模块），真正编译的是
`build/libstellarium-harmonyos/`。生成方式：

```powershell
& "E:\Qt\6.12.0\mingw_64\bin\harmonydeployqt.exe" `
  --input build\src\stellarium-harmony-deployment-settings.json `
  --output build\libstellarium-harmonyos --no-build
```

> `stellarium-harmony-deployment-settings.json` 由第 2 步的 `qt-cmake` 配置生成，
> 所以正确的首次顺序是：先跑一次引擎配置，再执行本节。

### 1.2 在 DevEco Studio 里配置自动签名（只做一次）

1. `File > Open` 打开 `build/libstellarium-harmonyos`
2. 右上角登录华为开发者账号（需实名认证）
3. 连上真机（USB 调试或无线调试）→ `File > Project Structure...`（`Ctrl+Alt+Shift+S`）
   → 左树选 **Project** → 右侧页签 **Signing Configs** → 勾 **Automatically generate signature**
4. 成功标志：`build-profile.json5` 里出现 `signingConfigs`，且 `~/.ohos/config/` 下生成
   `default_*.p12 / .csr / .cer / .p7b`

生成后需要手工在产品里引用它（DevEco 只写数组、不写引用）：

```json5
"products": [
  { "name": "default", "signingConfig": "default", /* ... */ }
]
```

> **包名**：`AppScope/app.json5` 的 `bundleName` 属于本地/发布配置。上游（发布身份）是
> `com.joinother.skyinstrument`（属于原作者的 AGC 账号）；本机调试身份由 DevEco 自动签名决定，
> 可能是另一个已注册包名。`sync-ohos-build-sources.sh` 已经**不再覆盖** `app.json5`，
> 否则包名会被还原、自动签名随即失配并报 `bundleName does not match the generated SigningConfigs`。
> 构建脚本 `build-ohos-hap-windows.ps1 -Install` 从产物 `pack.info` 读取实际包名，不写死任何身份。

---

## 2. 日常构建

```powershell
# 全量：交叉编译引擎 → 修 DT_NEEDED → 部署 Qt 库 → 灌资源 → 同步源码 → 打包
powershell -ExecutionPolicy Bypass -File scripts\build-ohos-hap-windows.ps1

# 只改 ArkTS：跳过引擎与资源
powershell -ExecutionPolicy Bypass -File scripts\build-ohos-hap-windows.ps1 -SkipEngine -SkipResources

# 构建 + 安装 + 启动
powershell -ExecutionPolicy Bypass -File scripts\build-ohos-hap-windows.ps1 `
  -SkipEngine -Install -Device 192.168.3.95:40565
```

产物：`entry-default-signed.hap` ≈ **680 MB**（含 549 MB rawfile 资源 + 41 MB 引擎）。

只想灌资源：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\sync-ohos-resources-windows.ps1
```

---

## 3. 三个必须显式传的编译参数

缺任何一个都编不出来，原因都不是"配置写错了"，而是这台机器/这个平台的客观限制：

| 参数 | 不传的后果 |
| --- | --- |
| `-DQT_CHAINLOAD_TOOLCHAIN_FILE=<SDK>\native\build\cmake\ohos.toolchain.cmake` | Qt 的 `qt.toolchain.cmake` 里写死 `/opt/harmonyos/command-line-tools/...`；不覆盖会**静默回退宿主编译器**并报找不到 Qt6 |
| `-DQT_HOST_PATH=E:/Qt/6.12.0/mingw_64` | `harmonyos_arm64_v8a` 套件**不含宿主工具**，`Qt6Config.cmake` 要求该变量 |
| `-DGLESv3_INCLUDE_DIR=<SDK>\native\sysroot\usr\include`（`EGL_INCLUDE_DIR` 同理） | Windows 宿主下 Qt 的 `FindGLESv3` / `FindEGL` 的 `find_path` 只搜 Qt 前缀，够不到 sysroot → `Qt6Gui` NOT FOUND、configure 直接失败 |

功能开关沿用移植基线：`ENABLE_NLS/QTWEBENGINE/SPEECH/GPS/INDI/MEDIA/SHOWMYSKY/XLSX=0`、
`ENABLE_SCRIPTING=1`。中文界面由运行时的 `.qm` 翻译提供，不依赖 `ENABLE_NLS`。

---

## 4. 踩坑速查（都是实测报错原文）

| 现象 | 根因 | 处理 |
| --- | --- | --- |
| `hvigor ERROR: spawn java ENOENT` | DevEco 开着时它的 hvigor 常驻 daemon 接管任务，而 daemon 的 PATH 里没有 `java` | 加 `--no-daemon`，并把 `<DevEco>\jbr\bin` 加进 PATH（脚本已处理） |
| `Path not found. At file: ...\harmonyos\entry` | 在源码镜像目录里跑 hvigor | 一律在 `build/libstellarium-harmonyos` 下构建 |
| `00303038 Schema validate failed ... easy_go.json` | API 26 已移除 `multiModalInputOptions` | `easy_go.json` 置空 |
| `Class 'QtWindowStageAdapter' incorrectly implements interface 'WindowStage'` | API 26 新增 `setImageForRecent` / `removeImageForRecent` | 在适配器里补这两个委托方法 |
| `Unknown resource name 'ic_globe'` 等 34 个 | `sync-ohos-build-sources.sh` 的显式文件清单过期 | 脚本已改为**整目录镜像** |
| `Cannot find module '../process/QChildProcess'` | 同上，清单漏了 34 个 ets/ts | 同上 |
| `arkts-no-any-unknown`（12 处） | `entry/oh-package.json5` 少了 `"libentry.so": "file:./src/main/cpp/types/libentry"`，原生桥退化成隐式 `any` | 补依赖 |
| `code:9568257 fail to verify pkcs7 file` | 真机不信任 OpenHarmony 自签 CA | 必须用华为签发的证书（DevEco 自动签名） |
| `code:9568322 not trusted app source` | 侧载了 AppGallery 发布签名 | 改用 debug 签名 |
| `aa start` → `10106102 ... screen is locked` | 开发者模式下系统不允许程序自动解锁 | 手动解锁并保持亮屏（息屏时间调长 / 开「充电时屏幕不休眠」） |
| `Startup resources are incomplete after asynchronous extraction` | `rawfile/stellarium/` 缺资源树 | 跑 `sync-ohos-resources-windows.ps1` |
| `dlopen() failed ... Error loading shared library _deps/md4c-build/src/libmd4c-html.so` | md4c / nlopt 由 CPM 引入且没有 SONAME，链接器把构建树路径写进了 `DT_NEEDED` | 构建脚本里的 `Repair-NeededPaths` 改成普通库名，并补 `libmd4c.so` / `libnlopt.so`（见 §5） |
| `install bundle successfully` 但应用不出画面 | 只装了 ArkTS 外壳，引擎 `.so` 没进包 | 检查 HAP 内 `libs/arm64-v8a/` 是否有 `libstellarium.so` + 15 个 `libQt6*.so` |
| configure 阶段 `Failed to clone repository: 'https://github.com/fastfloat/fast_float'` | `github.com:443` 不可达；或中途换了 CMake 版本导致已 populate 的 `_deps` 失效并触发重新克隆 | 见 §4.1 |

### 4.1 离线依赖（`github.com` 不通时）

引擎的 configure 会通过 CPM / FetchContent 引入三个依赖：

| 依赖 | 版本 | 用途 |
| --- | --- | --- |
| `md4c` / `md4c-html` | 0.5.2 | Markdown 渲染 |
| `nlopt` | 2.9.0 | 数值优化 |
| `fast_float` | 6.1.0 | header-only；**因为 OHOS libc++ 不支持浮点 `std::from_chars`**，Stellarium 才回退到它 |

`github.com` 连不上时 `git clone` 必然失败，但 **`codeload.github.com`（tarball 域名）通常仍可达**：

```powershell
$work = "$env:TEMP\stellarium-deps"; New-Item -ItemType Directory -Path $work -Force | Out-Null
# fast_float（其余两个同理，分别落到 md4c-src / nlopt-src）
Invoke-WebRequest "https://codeload.github.com/fastfloat/fast_float/tar.gz/refs/tags/v6.1.0" -OutFile "$work\fast_float.tar.gz"
tar -xzf "$work\fast_float.tar.gz" -C $work
if (Test-Path build\_deps\fastfloat-src) { Remove-Item build\_deps\fastfloat-src -Recurse -Force }
Move-Item "$work\fast_float-*" build\_deps\fastfloat-src
```

三个 `*-src` 目录齐备后，`build-ohos-hap-windows.ps1` 会**自动**追加
`-DFETCHCONTENT_FULLY_DISCONNECTED=ON`，配置阶段完全离线（实测 5.9 s，零网络动作）。

> ⚠️ **不要中途更换 CMake**。`qt-cmake.bat` 会优先使用 `E:\Qt\Tools\CMake_64\bin\cmake.exe`
> （装 Qt 时一并装上），改用其它版本会让 CMake 判定现有 `_deps` 失效并重新克隆全部依赖——
> 这正是本项目第一次跑脚本就断在 `fastfloat` 的原因。

---

## 5. 已知技术债

1. **`DT_NEEDED` 修复是二进制补丁**（`build-ohos-hap-windows.ps1` 的 `Repair-NeededPaths`）。
   等长短名 + NUL 填充改写 `.dynstr`，安全但**必须在每次重新链接引擎后重跑**。
   根治办法是在 CMake 层给 `md4c` / `md4c-html` / `nlopt` 目标加 `SOVERSION`（或改为静态链接），
   让链接器直接写入普通库名。
2. ~~**未生成 `.model.rgba` 侧车文件**~~ → **已修复（2026-10-02）**。
   `sync-ohos-resources-windows.ps1` 生成与 bash 版同口径的侧车：50 个 512×256 行星/卫星 +
   3 个 512×2 行星环，输出为裸 RGBA（`R,G,B,A` 字节序，与 `DetailModelRasterizer.ets` 的读取一致），
   单文件 524288 / 4096 字节。
   **侧车生成器优先级（自 2026-10-02 起）**：优先 `ffmpeg`，缺省回退 `System.Drawing`。
   ffmpeg 的解析顺序与 bash 版一致，另加一步 Windows 便利查找：
   ① `$env:FFMPEG`（可为绝对路径或命令名）→ ② `PATH` 上的 `ffmpeg` →
   ③ WinGet 的 `Gyan.FFmpeg` 包目录（`%LOCALAPPDATA%\Microsoft\WinGet\Packages\Gyan.FFmpeg*\*\bin\ffmpeg.exe`，
   该目录默认不在 `PATH` 上）；三者皆无才回退 `System.Drawing`。
   用 ffmpeg 时参数与 `sync-ohos-resources.sh` 逐字对齐：
   `-hide_banner -loglevel error -y -i <png> -vf 'scale=<w>:<h>:flags=lanczos,format=rgba' -frames:v 1 -pix_fmt rgba -f rawvideo <out>`。
   同步日志会打印本次走的是哪条路径（`binary: ffmpeg (...)` 或 `binary: System.Drawing (ffmpeg not found)`）。
   待确认 ffmpeg 未装时，可显式 `$env:FFMPEG = 'C:\...\ffmpeg.exe'` 再跑脚本。
   ⚠️ 侧车由资源同步阶段生成，因此 `build-ohos-hap-windows.ps1 -SkipResources` 会跳过它。
3. **`qt-platform-patch` 版本对不上**：`scripts/build-ohos-platform-patch.sh` 写死
   qtbase `REVISION=97575d35…`（Qt 6.12.0 Beta2），而本机装的是 6.12.0 Release
   （`sbom` 里是 `a2c0b1ea…`）→ 脚本会在版本校验处硬失败，**剪贴板通知补丁版的
   `libqohos.so` 目前编不出来**，HAP 用的是原版平台插件。
4. `check-ohos.sh` 依赖 `rsync/ffmpeg/du`，在 Windows 上不能整脚本运行；
   JPEG 检查已按实际 `DT_NEEDED` 判定（Qt 6.12 的 `libqjpeg.so` 静态链接了 libjpeg，
   不再需要 `libjpeg.so`）。

---

## 6. 验证清单

构建后按顺序确认（都已实测通过）：

```powershell
# 1. 引擎是给设备架构编的
& "<SDK>\native\llvm\bin\llvm-readelf.exe" -h build\src\libstellarium.so   # AArch64 / DYN
# 2. 依赖名干净
& "<SDK>\native\llvm\bin\llvm-readelf.exe" -d build\...\libs\arm64-v8a\libstellarium.so
#    应看到 libmd4c-html.so / libmd4c.so / libnlopt.so，而不是 _deps/... 路径
# 3. HAP 内含引擎与 Qt 运行库
#    libs/arm64-v8a/{libstellarium.so, libqohos.so, libQt6Core.so, ...}
# 4. 装机后日志
hdc -t <device> shell hilog -x | Select-String "StelRootItem paint reached|zero-copy frame bridge resolved|startOhosRenderPump entered|command on Qt thread"
# 5. 截图确认星图
hdc -t <device> shell "snapshot_display -f /data/local/tmp/s.png"
hdc -t <device> file recv /data/local/tmp/s.png .\screenshot.png
```

期望画面：星点 + 银河、地平线地景、选中天体标注（如「河鼓二 Altair」）、
方位标注（如红色「南」），底部 ArkUI Dock「搜索 / 时间 / 位置 / 图层 / 更多功能」。
