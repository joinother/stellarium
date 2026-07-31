# Codex / 命令行 打包与安装指南（Stellarium HarmonyOS 移植）

本指南面向想在 **不打开 DevEco Studio GUI** 的情况下完成「改代码 → 编译 → 打包 HAP → 装到设备/模拟器」的人（包括 Codex）。
所有路径基于本机 macOS 环境；换机器时只需替换 DevEco 与 Node 路径。

---

## 0. 一句话结论（先读这个）

- 编译用的 SDK 是 **API 24（HarmonyOS 6.1.1）**，它自带 `hms` + `openharmony` 组件，**正好匹配工程的 `compileSdkVersion: 6.1.1(24)`**。
- 工程 `compatibleSdkVersion: 6.0.0(20)` 只是「最低可运行版本」，**不需要本机真的装一个 API 20 SDK**。你机器上 `~/Library/OpenHarmony/Sdk/20` 那个目录**缺 `hms` 组件**，千万别把 `sdk.dir` 指过去，否则必报 `SDK component missing`。
- 真实构建根目录是 **`build/libstellarium-harmonyos/`**，不是 `harmonyos/`（`harmonyos/` 只是被 git 跟踪的源模板）。
- 历史上构建失败的根因是 **`build/libstellarium-harmonyos/local.properties` 为空文件**（读到空 `sdk.dir`）→ 报 `SDK component missing`。写入 `sdk.dir` 即可。

---

## 1. 前置条件

- 已安装 DevEco Studio（`/Applications/DevEco-Studio.app`）。
- 以下路径存在：
  - SDK：`/Applications/DevEco-Studio.app/Contents/sdk`（含 `default/hms`、`default/openharmony`，API 24）
  - JBR：`/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home`
  - hvigor：`/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw`
  - hdc：`/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc`
  - Node：任意 18+，本机用 `/Users/jiexuanyang/.workbuddy/binaries/node/versions/22.22.2`
  - 引擎 cmake：`/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/build-tools/cmake/bin/cmake`

---

## 2. 两种工程布局（最容易踩坑）

| 目录 | 作用 | 是否参与 hvigor 构建 |
|------|------|----------------------|
| `harmonyos/` | 被 git 跟踪的**源模板**：`ets-source/`、`cpp-source/`、`AppScope/`、`resources/`、`module.json5` | 否（只是源） |
| `build/libstellarium-harmonyos/` | **真正被 hvigor 打包的工程**（生成物，不进 git） | **是** |

同步脚本 `scripts/sync-ohos-build-sources.sh` 把 `harmonyos/` 下的源文件 **复制** 到 `build/libstellarium-harmonyos/`。
> 改了 ArkTS 源码后必须跑这个脚本，再 `hvigor assembleHap`，否则打的还是旧代码。

---

## 3. 环境准备（每次构建前）

```bash
export JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home
export NODE_HOME=/Users/jiexuanyang/.workbuddy/binaries/node/versions/22.22.2
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export PATH="$NODE_HOME/bin:$JAVA_HOME/bin:$PATH"
# 杀掉旧 hvigor daemon，避免沿用错误的环境变量缓存
pkill -f hvigor 2>/dev/null; sleep 1
```

### 关键：`local.properties`（SDK 阻塞修复）
确保 `build/libstellarium-harmonyos/local.properties` **不为空**，内容至少包含：
```
sdk.dir=/Applications/DevEco-Studio.app/Contents/sdk
nodejs.dir=/Users/jiexuanyang/.workbuddy/binaries/node/versions/22.22.2
```
> 空文件会让 hvigor 读到空 `sdk.dir` → `SDK component missing`。这是本项目最常见的构建失败原因。

---

## 4. 改了 C++（引擎）后：重编 `libstellarium.so`

引擎 40MB 的 `libstellarium.so` 由顶层 Qt-for-OHOS cmake 独立产出，**hvigor 不会重编它**，只会把 `entry/libs/arm64-v8a/` 里已有的 `.so` 打进包。

```bash
# 在顶层 cmake 构建目录增量重编（只重编改动的 .cpp 再链接）
cd /Users/jiexuanyang/stellarium-src/build
make -j$(sysctl -n hw.ncpu)

# 手动拷到 hvigor 工程的 native libs 目录（hvigor 不会自动同步！）
cp build/src/libstellarium.so \
   build/libstellarium-harmonyos/entry/libs/arm64-v8a/libstellarium.so
```

> 注意：本代码库 `Vec3d::lengthSquared()` 在 `src/core/VecMath.hpp` 被 `= delete`，
> 自定义命令里算向量长度必须用 `normSquared()`，否则编译报 `attempt to use a deleted function`。

---

## 5. 改了 ArkTS 后：同步源

```bash
cd /Users/jiexuanyang/stellarium-src
bash scripts/sync-ohos-build-sources.sh
# 校验：grep 一下你的改动是否进了构建工程
grep -c "你的关键字" build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets
```

---

## 6. 打包 HAP

```bash
cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos
# 环境见第 3 节
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default
```

产物：
- `entry/build/default/outputs/default/entry-default-signed.hap`（按 `build-profile.json5` 里 product 的 `signingConfig` 签名）
- `entry-default-unsigned.hap`（未签名副本）

---

## 7. 安装到设备 / 模拟器

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc

# 先看连了哪些目标
"$HDC" list targets
# 本地模拟器：hdc tconn 127.0.0.1:5555

DEVICE=7LZBB26323200303   # 真机序列号；模拟器用 127.0.0.1:5555

# 1) 传包（大包 600MB 用 file send 比 hdc install 稳）
"$HDC" -t "$DEVICE" file send entry-default-signed.hap /data/local/tmp/app.hap

# 2) 安装
"$HDC" -t "$DEVICE" shell "bm install -p /data/local/tmp/app.hap -g -w 600"
# 成功会打印：install bundle successfully.
```

### 签名现实（最容易卡住的一步）
- **release 签名**（`build-profile.json5` product 默认曾设为 `release`）：是 AppGallery 发布用的 `app_gallery` profile，
  **真机侧载会直接拒绝** → 报 `code:9568322 signature verification failed due to not trusted app source`。
  模拟器（`127.0.0.1:5555`）不校验，能直接装；真机不行。
- **debug 签名**（`signingConfig: "default"`，即 `debugKey`）：真机才能侧载。
  但本工程的 debug profile 的 `bundle-name` 是 **`org.qtproject.example.stellarium`**（Qt 模板遗留默认值），
  与工程实际 `bundleName: com.joinother.skyinstrument` **不一致**，hvigor 签名阶段会报
  `bundleName does not match the generated SigningConfigs`。

  **真机调试安装的两种可行做法：**
  1. （推荐）在 DevEco Studio 里连上设备点一次 Run，让它自动生成匹配 `com.joinother.skyinstrument` 的 debug profile；
  2. （本机已验证可用）临时把 `build/libstellarium-harmonyos/AppScope/app.json5` 的
     `bundleName` 改成 `org.qtproject.example.stellarium`（只改构建工程、别改 `harmonyos/` 源），
     再把 product 的 `signingConfig` 设为 `default`，重新 assembleHap —— 本机 tablet 的 UDID 已经在这个 debug profile 的
     `device-ids` 里，能直接装。装完是 `org.qtproject.example.stellarium` 这个包名，纯属调试用途。

---

## 8. 启动应用

```bash
# bundleName 取决于上面用的签名：
#  - release / 真包名：com.joinother.skyinstrument
#  - 临时 debug 包名：org.qtproject.example.stellarium
"$HDC" -t "$DEVICE" shell aa start -b org.qtproject.example.stellarium -a QAbility
```

---

## 9. 一句话排查清单

| 现象 | 原因 | 修复 |
|------|------|------|
| `SDK component missing` | `local.properties` 空 / `sdk.dir` 指到缺 `hms` 的目录 | 写 `sdk.dir=/Applications/DevEco-Studio.app/Contents/sdk` |
| `Hvigor config file .../hvigor/hvigor-config.json5 does not exist` | 在 `harmonyos/` 目录跑了 hvigor | 改到 `build/libstellarium-harmonyos/` 下跑 |
| `attempt to use a deleted function` | 用了 `Vec3d::lengthSquared()` | 改用 `normSquared()` |
| `bundleName does not match the generated SigningConfigs` | debug profile 的 bundle 名是 Qt 模板默认名 | 见第 7 节 |
| `code:9568322 not trusted app source` | 真机侧载 release 包 | 改用 debug 签名（见第 7 节） |
| 改了代码但打包没生效 | 没跑同步脚本 / 没重编引擎 `.so` | 见第 4、5 节 |

---

## 10. 关于「API 20 编不出来」

不用去找 API 20 的 SDK。工程 `compileSdkVersion` 是 24，本机 DevEco SDK 就是 24（含 `hms`），直接能编。
「API 20」只是 `compatibleSdkVersion`（最低运行版本）。之前编不出是 `local.properties` 为空导致 `sdk.dir` 缺失，
不是 API 版本问题。
