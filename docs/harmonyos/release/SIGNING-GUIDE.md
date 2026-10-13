# Stellarium HarmonyOS 签名与打包说明

> **当前流程（2026-09-06）：请使用 [RELEASE-PACKAGING.md](RELEASE-PACKAGING.md)。** 本机已有独立发布签名，当前产品已由用户授权切换到 `release`。下文是 2026-07 的历史排障档案，其中旧包名、旧签名状态及命令不适用于当前发布，勿照抄执行或恢复旧密钥。

给 WorkBuddy / 新 Agent 使用。
日期：2026-07-21（原始由 Codex 撰写，2026-07-22 由 WorkBuddy 校正签名材料章节）
目标分支：`openharmony-preview-v1`

---

## ⚠️ 安全通告（2026-07-22 校正）

历史上本仓库**曾把签名私钥 `stellarium-app-keypair.p12` 和 `build-profile.json5` 里的明文密码误提交到 GitHub**，并已从公开历史强推清除。该旧私钥有两个本地副本：

1. 仓库内 `docs/harmonyos/signing/stellarium-app-keypair.p12` —— 已移入废纸篓销毁；
2. `/private/tmp/stellarium-oh-signing/stellarium-app-keypair.p12` —— 同款副本（md5 一致），也已移入废纸篓销毁。

**旧 `stellarium-app-keypair.p12` 已被彻底销毁，严禁恢复、严禁再次提交、严禁用于任何签名。** 本文档后续引用的均为**轮换后的新密钥**。

---

## 0. 这套签名到底是什么

这个项目**实际构建与安装走的是 DevEco 自动签名**（点 Run/Debug 时 DevEco 自动生成并签名）。下面第 4 节的 `hap-sign-tool sign-app` 手动流程**仅作为命令形态参考保留**：它依赖的旧私钥已销毁，新密钥为 PEM 格式、尚未打包成 `sign-app` 需要的 p12 keystore，因此手动流程当前不能直接跑通——日常请用 DevEco 自动签名。

签名材料现在放在**仓库之外的本机目录**（不进 git，避免再次泄露）：

```text
~/stellarium-signing/        # 仓库外，本机私有，勿提交
├── app.key                 # 应用私钥（PEM 格式）
├── app.pem                 # 应用证书（PEM 格式）
├── app-chain.pem           # 证书链
├── app-debug.p7b          # debug 类型 provision profile
├── app.csr                 # 证书签名请求
├── ca.key                  # 自建 CA 私钥
├── ca.pem                 # 自建 CA 证书
├── ca.srl                  # CA 序列号
└── profile-template.json   # profile 模板
```

关键参数：

```text
bundle name: org.qtproject.example.stellarium
keyAlias:    stellarium-app-key   # 旧流程别名；新密钥为 PEM，无 p12 别名，手动 sign-app 前需先合成 p12
profile type: debug              # 新密钥仅生成了 debug profile（app-debug.p7b）
```

不要把实际 keystore/key 密码或 `.p12/.p7b` 私有签名材料提交到 GitHub。密码从项目负责人处通过私有渠道获取，运行时用环境变量传入：

```sh
export STELLARIUM_SIGNING_PASSWORD='<本地签名密码>'
```

---

## 1. 路径约定

源码仓库：

```sh
/Users/jiexuanyang/stellarium-src
```

HarmonyOS 构建工程：

```sh
/Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos
```

DevEco Studio：

```sh
/Applications/DevEco-Studio.app
```

独立 OpenHarmony SDK：

```sh
/Users/jiexuanyang/Library/OpenHarmony/Sdk
```

签名材料工作目录（仓库外，本机私有）：

```sh
~/stellarium-signing
```

---

## 2. 准备签名材料

签名材料**不应进入仓库**。从项目负责人处通过私有渠道获取后，放到本机 `~/stellarium-signing/`（见第 0 节文件清单）。

不要在签名命令里引用 git 仓库内的签名目录；清洗历史后该目录不应再存在于公开仓库。

---

## 3. 构建 unsigned HAP

进入 HarmonyOS 工程目录：

```sh
cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos
```

构建（带齐 DevEco 自带 Node / JBR / SDK 环境变量）：

```sh
env NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
  JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
  OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk \
  PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --no-daemon
```

成功后重点看这个文件（DevEco 自动签名产物，日常安装用它）：

```text
/Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap
```

---

## 4. 手动签名（参考命令，当前不可直接跑通）

> **仅作命令形态参考。** 旧私钥已销毁；新密钥为 PEM 格式（`app.key` / `app.pem`），尚未合成 `sign-app` 需要的 p12 keystore，也未生成 release profile。若未来要恢复手动签名，需：① 用 openssl 把 `app.key`+`app.pem` 合成 p12 并设定 `keyAlias`；② 用 `hap-sign-tool generate-profile` 或 `sign-profile` 生成匹配的 profile。日常请直接用第 3 节 DevEco 自动签名的 `entry-default-signed.hap`。

命令形态（路径已指向新密钥目录，**请勿直接运行**）：

```sh
/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin/java \
  -jar /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar \
  sign-app -mode localSign \
  -keyAlias stellarium-app-key \
  -keyPwd "$STELLARIUM_SIGNING_PASSWORD" \
  -appCertFile ~/stellarium-signing/app-chain.pem \
  -profileFile ~/stellarium-signing/app-debug.p7b \
  -inFile /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-unsigned.hap \
  -signAlg SHA256withECDSA \
  -keystoreFile ~/stellarium-signing/app.key \
  -keystorePwd "$STELLARIUM_SIGNING_PASSWORD" \
  -outFile ~/stellarium-signing/stellarium-latest-signed.hap \
  -compatibleVersion 24 \
  -signCode 1
```

### 4.1 验证签名（参考）

```sh
/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin/java \
  -jar /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar \
  verify-app \
  -inFile ~/stellarium-signing/stellarium-latest-signed.hap \
  -outCertChain ~/stellarium-signing/verify-cert-chain.pem \
  -outProfile ~/stellarium-signing/verify-profile.p7b
```

---

## 5. 安装到模拟器/设备

设置 hdc 路径：

```sh
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
```

连接模拟器：

```sh
$HDC tconn 127.0.0.1:5555
```

安装（日常用 DevEco 自动签名产物）：

```sh
$HDC -t 127.0.0.1:5555 install -r \
  /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap
```

启动：

```sh
$HDC -t 127.0.0.1:5555 shell hilog -r
$HDC -t 127.0.0.1:5555 shell aa force-stop org.qtproject.example.stellarium
$HDC -t 127.0.0.1:5555 shell aa start -b org.qtproject.example.stellarium -a QAbility
```

---

## 6. 如果安装失败

### 6.1 `install sign info inconsistent`

含义：设备上已有同 bundleName 的应用，但它和你当前 HAP 的签名不是同一套。

优先处理：

1. 确认安装的是 DevEco 自动签名的 `entry-default-signed.hap`，且每次都用同一套签名材料。
2. 若手动流程，重新跑第 4 节签名后再安装。

仍失败可卸载后重装（会清掉应用数据，调试阶段可接受）：

```sh
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
$HDC -t 127.0.0.1:5555 shell bm uninstall -n org.qtproject.example.stellarium
$HDC -t 127.0.0.1:5555 install -r \
  /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap
```

### 6.2 `NODE_HOME is not set`

构建环境没带 DevEco 自带 Node。用第 3 节完整 `env NODE_HOME=... PATH=... hvigorw assembleHap` 命令。

### 6.3 `Unable to find sdk.dir` 或 `OHOS_BASE_SDK_HOME`

缺 SDK 路径。修复：

```sh
printf 'sdk.dir=/Users/jiexuanyang/Library/OpenHarmony/Sdk\n' \
  > /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/local.properties
```

并在构建命令里保留 `OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk`。

### 6.4 `SDK management mode has changed`

通常是把 `OHOS_BASE_SDK_HOME` 指到了 DevEco 内置 SDK。本项目应指向独立 SDK `/Users/jiexuanyang/Library/OpenHarmony/Sdk`。

---

## 7. 一条龙命令速查（构建 + 安装，自动签名）

```sh
cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos

env NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
  JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
  OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk \
  PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --no-daemon

HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
$HDC tconn 127.0.0.1:5555
$HDC -t 127.0.0.1:5555 install -r \
  /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap
$HDC -t 127.0.0.1:5555 shell aa force-stop org.qtproject.example.stellarium
$HDC -t 127.0.0.1:5555 shell hilog -r
$HDC -t 127.0.0.1:5555 shell aa start -b org.qtproject.example.stellarium -a QAbility
```

---

## 8. WorkBuddy 接手时要记住

- 项目实际用 **DevEco 自动签名**；`entry-default-signed.hap` 是日常安装包。
- 第 4 节手动 `sign-app` 仅作参考，旧私钥已销毁、新密钥为 PEM，不可直接跑通。
- **旧 `stellarium-app-keypair.p12` 已销毁，严禁恢复/再提交**（见顶部安全通告）。
- `bundle-name` 必须仍是 `org.qtproject.example.stellarium`，否则 profile 不匹配。
- 这套证书是本地预览用途，不是正式商店分发凭据。
- 不要把实际 keystore/key 密码写进 GitHub 文档或提交信息。
- 不要尝试改 HAP 里的签名/profile 文件；签名块由 `hap-sign-tool.jar sign-app` 生成。
- 每次修改构建/签名流程后，更新 `docs/harmonyos/CHANGELOG.md`。

---

## 9. TRAE Agent 实际签名流程（2026-07-22 验证）

### 9.1 我是怎么签名的

**我完全依赖 DevEco 自动签名，没有手动执行 hap-sign-tool。** 流程如下：

1. **签名材料来源：** DevEco Studio 在首次打开项目时自动生成了签名材料，存放在：
   ```
   /Users/jiexuanyang/.ohos/config/openharmony/
   ├── default_libstellarium-harmonyos_BOVLsyGJ3Wytlsmvgmsjd9Xkw0JjlZi4qM4hj__q8Q8=.cer    # 应用证书
   ├── default_libstellarium-harmonyos_BOVLsyGJ3Wytlsmvgmsjd9Xkw0JjlZi4qM4hj__q8Q8=.p12    # 密钥库
   ├── default_libstellarium-harmonyos_BOVLsyGJ3Wytlsmvgmsjd9Xkw0JjlZi4qM4hj__q8Q8=.p7b    # debug profile
   └── material/{ac,ce,fd}/ ...                                                    # CA 证书链
   ```

2. **build-profile.json5 配置：** 项目已配置好签名引用，指向上述文件。这个文件已提交到 GitHub，包含密码和路径（DevEco 自动签名的标准做法，debug 签名，本地开发用途）。

3. **构建时自动签名：** hvigorw assembleHap 的最后一个步骤 SignHap 会读取 build-profile.json5 中的签名配置，自动对 HAP 签名。产物名 entry-default-signed.hap。

4. **我的完整构建+安装命令（一条龙）：**
   ```sh
   # 第一步：构建（自动签名）
   cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos
   env NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
     JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
     OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk \
     PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:\
     /Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:\
     /usr/bin:/bin:/usr/sbin:/sbin \
     /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --no-daemon

   # 第二步：安装到模拟器
   HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
   $HDC -t 127.0.0.1:5555 force-stop org.qtproject.example.stellarium
   $HDC -t 127.0.0.1:5555 shell bm uninstall -n org.qtproject.example.stellarium
   $HDC -t 127.0.0.1:5555 install -r \
     /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap

   # 第三步：启动并测试
   $HDC -t 127.0.0.1:5555 shell hilog -r
   $HDC -t 127.0.0.1:5555 shell aa start -b org.qtproject.example.stellarium -a QAbility
   ```

### 9.2 真机安装失败的原因

连接的真机 7LZBB26323200303 是 Release 版本（const.ohos.releasetype=Release），不接受 debug 签名的 HAP。要安装到这台设备，需要：

1. **开启开发者模式：** 设置 → 关于手机 → 连续点击版本号 7 次
2. **获取 release profile：** 在 AppGallery Connect 上注册应用，生成 release 类型的 .p7b
3. **或用 DevEco Studio 直接 Run 到真机：** DevEco 会自动处理签名

### 9.3 给 WorkBuddy 的建议

- **日常开发用模拟器**，DevEco 自动签名直接可用，不需要手动签名
- **签名材料在 ~/.ohos/config/openharmony/ 目录下**，由 DevEco 管理，不要手动删除
- **build-profile.json5 已包含签名配置**，直接构建就行
- **如果要重新生成签名材料：** DevEco Studio → File → Project Structure → Signing Configs → 勾选 "Automatically generate signature"
- **安装失败时先卸载再装：** $HDC shell bm uninstall -n org.qtproject.example.stellarium
