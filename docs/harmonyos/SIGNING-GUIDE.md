# Stellarium HarmonyOS 签名与打包说明

给 WorkBuddy / 新 Agent 使用。  
日期：2026-07-21  
目标分支：`openharmony-preview-v1`

## 0. 这套签名到底是什么

这个项目目前用的是一套**本地调试/预览用 release 签名材料**，不是上架 AppGallery 的正式商业签名。

签名材料曾经放在仓库内的如下路径。**安全清理后不要再依赖仓库内路径**，应由项目负责人通过私有渠道提供到本机目录，例如 `/private/tmp/stellarium-oh-signing/` 或 `~/stellarium-signing/`：

```text
docs/harmonyos/signing/       # legacy path, do not commit again
├── stellarium-app-keypair.p12
├── stellarium-app-cert-chain.cer
├── stellarium-ca-release-profile.p7b
├── stellarium-ca-release-profile.json
├── root.cer
├── ca.cer
└── leaf.cer
```

关键参数：

```text
bundle name: org.qtproject.example.stellarium
keyAlias: stellarium-app-key
keystorePwd: use local env var STELLARIUM_SIGNING_PASSWORD
keyPwd: use local env var STELLARIUM_SIGNING_PASSWORD
profile type: release
profile uuid: stellarium-openharmony-release-20260719-ca-signed
```

不要把实际 keystore/key 密码或 `.p12/.p7b` 私有签名材料提交到 GitHub。WorkBuddy 在本机运行前，从项目负责人处拿到本地预览签名密码和签名材料，然后设置：

```sh
export STELLARIUM_SIGNING_PASSWORD='<local signing password>'
```

为什么需要它：

- `hvigor assembleHap` 会生成 `entry-default-unsigned.hap`。
- DevEco/Hvigor 也可能生成一个默认 signed HAP，但它的签名信息可能和模拟器里已安装版本不一致。
- 如果直接安装默认 signed HAP，常见错误是：

```text
install sign info inconsistent
```

所以我当时采用的稳定流程是：

1. 用 `hvigorw assembleHap` 构建出 unsigned HAP。
2. 用 `hap-sign-tool.jar sign-app` 手动使用同一套证书重签。
3. 安装这个手动签出来的 HAP。

只要后续一直用这套材料签名，覆盖安装就不会因为签名不一致失败。

### 0.1 2026-07-21 实测结论

Codex 已在本机模拟器 `127.0.0.1:5555` 重新实测：

- 使用同一套 `stellarium-app-keypair.p12` + `stellarium-app-cert-chain.cer` + `stellarium-ca-release-profile.p7b`
- 对当前 `entry-default-unsigned.hap` 手动 `sign-app`
- `verify-app` 通过
- `hdc install -r` 安装成功
- `aa start -b org.qtproject.example.stellarium -a QAbility` 启动成功
- `hilog` 中可见 `StellariumArkUI` / `selectAt result`，说明应用实际运行

所以不要再把问题归因成“模拟器只接受 debug profile，release profile 命令行必被拒”。至少在当前这台本地模拟器和当前这套签名材料下，这个判断不成立。

WorkBuddy 遇到的坑更可能是：

- 把 `build-profile.json5` 里的 DevEco/Hvigor 签名材料字段当成了 keystore 明文密码。那类字段不等于可以直接喂给 `keytool` / `hap-sign-tool` 的普通密码。
- 只看了 `stellarium-app-keypair.p12` 内部证书是自签名，却漏掉 `stellarium-app-cert-chain.cer` 已经提供了 sign-app 需要的完整证书链。
- 尝试替换 HAP 内部 profile。OpenHarmony HAP 的签名块不是普通 zip 条目，不能靠解压替换文件解决。

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

签名材料推荐工作目录：

```sh
/private/tmp/stellarium-oh-signing
```

## 2. 第一次准备签名材料

如果 `/private/tmp/stellarium-oh-signing` 不存在，从项目负责人私下提供的签名材料目录复制一份。下面用 `~/stellarium-signing` 举例：

```sh
mkdir -p /private/tmp/stellarium-oh-signing

cp ~/stellarium-signing/stellarium-app-keypair.p12 \
  /private/tmp/stellarium-oh-signing/stellarium-app-keypair.p12

cp ~/stellarium-signing/stellarium-app-cert-chain.cer \
  /private/tmp/stellarium-oh-signing/stellarium-app-cert-chain.cer

cp ~/stellarium-signing/stellarium-ca-release-profile.p7b \
  /private/tmp/stellarium-oh-signing/stellarium-ca-release-profile.p7b
```

不要在签名命令里引用 git 仓库内的签名目录；清洗历史后该目录不应再存在于公开仓库。

## 3. 构建 unsigned HAP

进入 HarmonyOS 工程目录：

```sh
cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos
```

构建：

```sh
env NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
  JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
  OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk \
  PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --no-daemon
```

成功后重点看这个文件：

```text
/Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-unsigned.hap
```

有时同目录也会有：

```text
entry-default-signed.hap
```

但是为了覆盖安装稳定，优先使用下一步手动签出来的 HAP。

## 4. 手动签名

签名命令：

```sh
/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin/java \
  -jar /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar \
  sign-app -mode localSign \
  -keyAlias stellarium-app-key \
  -keyPwd "$STELLARIUM_SIGNING_PASSWORD" \
  -appCertFile /private/tmp/stellarium-oh-signing/stellarium-app-cert-chain.cer \
  -profileFile /private/tmp/stellarium-oh-signing/stellarium-ca-release-profile.p7b \
  -inFile /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-unsigned.hap \
  -signAlg SHA256withECDSA \
  -keystoreFile /private/tmp/stellarium-oh-signing/stellarium-app-keypair.p12 \
  -keystorePwd "$STELLARIUM_SIGNING_PASSWORD" \
  -outFile /private/tmp/stellarium-oh-signing/stellarium-latest-signed.hap \
  -compatibleVersion 24 \
  -signCode 1
```

成功时会看到类似：

```text
Start sign-app
Start to sign code.
Sign Hap success!
sign-app success
```

产物：

```text
/private/tmp/stellarium-oh-signing/stellarium-latest-signed.hap
```

### 4.1 验证签名

可选但推荐跑一次：

```sh
/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin/java \
  -jar /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar \
  verify-app \
  -inFile /private/tmp/stellarium-oh-signing/stellarium-latest-signed.hap \
  -outCertChain /private/tmp/stellarium-oh-signing/verify-cert-chain.cer \
  -outProfile /private/tmp/stellarium-oh-signing/verify-profile.p7b
```

正常现象：

```text
Find Hap Signing Block success
profile type is: release
verify codesign success
verify: Verify success
verify-app success
```

如果这里过不了，不要继续安装，先回到第 4 节重新签名。

## 5. 安装到模拟器/设备

设置 hdc 路径：

```sh
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
```

连接模拟器：

```sh
$HDC tconn 127.0.0.1:5555
```

安装：

```sh
$HDC -t 127.0.0.1:5555 install -r /private/tmp/stellarium-oh-signing/stellarium-latest-signed.hap
```

启动：

```sh
$HDC -t 127.0.0.1:5555 shell hilog -r
$HDC -t 127.0.0.1:5555 shell aa force-stop org.qtproject.example.stellarium
$HDC -t 127.0.0.1:5555 shell aa start -b org.qtproject.example.stellarium -a QAbility
```

## 6. 如果安装失败

### 6.1 `install sign info inconsistent`

含义：设备上已有同 bundleName 的应用，但它和你当前 HAP 的签名不是同一套。

优先处理：

1. 确认你安装的是 `/private/tmp/stellarium-oh-signing/stellarium-latest-signed.hap`，不是 hvigor 默认生成的 `entry-default-signed.hap`。
2. 重新跑第 4 节手动签名。
3. 再安装。

如果仍失败，可以卸载后重装：

```sh
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
$HDC -t 127.0.0.1:5555 shell bm uninstall -n org.qtproject.example.stellarium
$HDC -t 127.0.0.1:5555 install -r /private/tmp/stellarium-oh-signing/stellarium-latest-signed.hap
```

注意：卸载会清掉应用数据。一般调试阶段可以接受。

### 6.2 `NODE_HOME is not set`

构建环境没带 DevEco 自带 Node。

修复：使用第 3 节完整 `env NODE_HOME=... PATH=... hvigorw assembleHap` 命令。

### 6.3 `Unable to find sdk.dir` 或 `OHOS_BASE_SDK_HOME`

缺 SDK 路径。

修复：

```sh
printf 'sdk.dir=/Users/jiexuanyang/Library/OpenHarmony/Sdk\n' \
  > /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/local.properties
```

并且构建命令里保留：

```sh
OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk
```

### 6.4 `SDK management mode has changed`

通常是把 `OHOS_BASE_SDK_HOME` 指到了 DevEco 内置 SDK：

```text
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony
```

这个项目构建时应指向独立 SDK：

```text
/Users/jiexuanyang/Library/OpenHarmony/Sdk
```

## 7. 一条龙命令速查

```sh
cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos

env NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
  JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
  OHOS_BASE_SDK_HOME=/Users/jiexuanyang/Library/OpenHarmony/Sdk \
  PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --no-daemon

mkdir -p /private/tmp/stellarium-oh-signing
cp ~/stellarium-signing/stellarium-app-keypair.p12 /private/tmp/stellarium-oh-signing/
cp ~/stellarium-signing/stellarium-app-cert-chain.cer /private/tmp/stellarium-oh-signing/
cp ~/stellarium-signing/stellarium-ca-release-profile.p7b /private/tmp/stellarium-oh-signing/

/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin/java \
  -jar /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar \
  sign-app -mode localSign \
  -keyAlias stellarium-app-key -keyPwd "$STELLARIUM_SIGNING_PASSWORD" \
  -appCertFile /private/tmp/stellarium-oh-signing/stellarium-app-cert-chain.cer \
  -profileFile /private/tmp/stellarium-oh-signing/stellarium-ca-release-profile.p7b \
  -inFile /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-unsigned.hap \
  -signAlg SHA256withECDSA \
  -keystoreFile /private/tmp/stellarium-oh-signing/stellarium-app-keypair.p12 \
  -keystorePwd "$STELLARIUM_SIGNING_PASSWORD" \
  -outFile /private/tmp/stellarium-oh-signing/stellarium-latest-signed.hap \
  -compatibleVersion 24 -signCode 1

HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
$HDC tconn 127.0.0.1:5555
$HDC -t 127.0.0.1:5555 install -r /private/tmp/stellarium-oh-signing/stellarium-latest-signed.hap
$HDC -t 127.0.0.1:5555 shell aa force-stop org.qtproject.example.stellarium
$HDC -t 127.0.0.1:5555 shell hilog -r
$HDC -t 127.0.0.1:5555 shell aa start -b org.qtproject.example.stellarium -a QAbility
```

## 8. WorkBuddy 接手时要记住

- 不要直接相信 `entry-default-signed.hap`，优先手动签 `entry-default-unsigned.hap`。
- 只要覆盖安装，必须保持同一套 p12/cert/profile。
- `bundle-name` 必须仍是 `org.qtproject.example.stellarium`，否则 profile 不匹配。
- 这套证书是本地预览用途，不是正式商店分发凭据。
- 不要用 `build-profile.json5` 里的 DevEco/Hvigor 签名材料字段直接开 `.ohos/config/*.p12`；那不是本手册这套签名流程需要的密码。
- 不要把实际 keystore/key 密码写进 GitHub 文档或提交信息。
- 不要尝试改 HAP 里的签名/profile 文件；签名块由 `hap-sign-tool.jar sign-app` 生成。
- 每次修改构建/签名流程后，更新 `docs/harmonyos/CHANGELOG.md`。
