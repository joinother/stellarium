# Release 签名、手动打包与上传

核对日期：2026-09-06。适用本机 DevEco Studio 6.1.1.300、当前 API 24 工程。

## 当前本机配置

- 实际工程：`build/libstellarium-harmonyos/`，不是源码根目录，也不是 `harmonyos/` 模板目录。
- 实际工程的 `build-profile.json5`：`app.products` 中 `name=default` 的 `signingConfig` 已从 `default` 改为 `release`。
- 原 `default` 调试签名和 `release` 发布签名均保留，未重建、替换或修改材料。仅检查引用的三个材料文件存在，并解析 Profile 确认类型及包名匹配；没有验证私钥密码、证书链及完整签名成功性。
- 包名 `com.joinother.skyinstrument`；2026-09-08 按用户要求，本地构建号由 `1000049` 升至 `1000050`，展示版本保持 `1.0.9`。AGC 当前测试版本仍绑定 9 月 7 日上传的 `1000049`。本地构建号不是平台自动产生的“构建版本”序号。

### 2026-09-08 审核日志复核：尚不具备重新提交条件

已核对 default 产品仍引用已有 release 签名，没有替换证书、密钥或 Profile。正式托管隐私协议仍缺重力传感器，按用户要求待故障验证后处理。Qt 剪贴板变化通知同步读路径已修补，主工程 Release CompileArkTS、独立 Debug 打包及 Pad 20 次复制回归通过；不等同于 Release 系统隐私与长时间压力测试通过。详见 `PRIVACY-REVIEW-2026-09-08.md`。

打包前运行 `node scripts/check-ohos-platform-patch.mjs`，确认生成工程使用修复库。首次构建先执行 `bash scripts/build-ohos-platform-patch.sh`；Qt SDK 升级或重新部署后不得绕过门禁。生成的旧 APP/HAP 不会被本轮 CompileArkTS 自动更新，用户最终必须重新 Build APP。
- `buildModeSet` 同时保留 `debug` 和 `release`。它是可选模式集合，不代表当前选中模式；`signingConfig=release` 选择签名方案，不能代替 Release 构建模式。签名方案的 `type` 仍为 `HarmonyOS`，不能写成 `release`。
- 本机签名 JSON 被 Git 忽略；不复制到源码模板，不提交密码、证书、私钥或 Profile。后续调试需要时，仅由用户明确选择切回 `default`，同步脚本不应偷偷切换。

## 用户手动打包

1. 在 DevEco Studio 打开上述实际工程。如果编辑器提示文件被外部修改，重新从磁盘载入，不要用旧缓冲区覆盖新引用。
2. `File > Project Structure > Project > Signing Configs` 检查已有的 `release`，确认它使用发布证书和发布 Profile。不要覆盖现有 Debug 配置，不要重新生成本来已有的密钥。
3. 点击 DevEco 编辑区右上角的构建配置入口，选择产品 `default`，把 **Build Mode** 选为 `release`。官方文档说明：`<Default>` 下 Build APP 默认 Release，但 Build HAP/HSP/HAR 默认 Debug，建议显式确认。当前配置没有额外强制 `debuggable=true`；不要再添加这种覆盖项。
4. 执行 `Build > Build Hap(s)/APP(s) > Build APP(s)`，不是仅 Build HAP。
5. 到工程的 `build/outputs/default/` 中取得本次生成的 `.app`。核对生成时间、版本、构建日志中的 release 模式和发布签名；不要误用旧产物或调试 HAP。

仅供用户手动执行的等价构建任务（本轮未执行）：

```sh
cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --mode project -p product=default -p buildMode=release assembleApp --no-daemon
```

命令行须已有 DevEco 的 Node/JDK/SDK 环境。IDE 可自行管理这些环境，优先使用菜单打包。

`scripts/prepare-ohos-release.sh` 只同步源码/资源与应用身份，不会选择发布签名、不会切换构建模式，也不会执行构建或上传。不能把脚本名称当成发布资格证明。构建后的原生库仍来自独立 CMake 交叉编译；Hvigor 不会自动替你重编 Stellarium 核心。

## 用户上传

1. 确认 AGC 中已创建正确包名对应的 HarmonyOS 应用，账号和团队正确。
2. 可在 DevEco 使用 `Build > Upload Product` 登录后选择正确产品和本次 `.app`；测试发布与正式发布是不同选择，按自己的计划选择。也可在 AppGallery Connect 对应应用的版本页面上传 `.app`。
3. 查看包检测/云测试结果，完善应用介绍、截图、隐私声明及平台要求的上架资料，再由用户提交审核。上传包不等于审核通过或已经发布。
4. 原生崩溃定位需要符号表，按上传界面的符号表选项处理；不上传个人日志、源代码、密钥或调试安装包。

## 版本与验证边界

- 华为文档把 26.0.0 及以上的云管理证书、上传时重新签名作为另一套流程；当前本机 6.1.1 不据此假定能免配置 Release 签名，也不为使用新流程自行升级 SDK。
- 本轮只修改签名引用并做只读配置检查。没有打包、没有安装 Release 产物、没有访问开发者账号或上传任何包。
- 之前在 Pad 上通过的是开发包回归，不等同于 Release 包验证。用户打包后仍应验证混淆后的 Worker 加载、三维模型、图片资源、插件、脚本和隐私启动流程。

## 官方资料（通过华为开发文档 MCP 核对）

- [发布应用：发布签名、Build APP 与上传步骤](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-publish-app)
- [工程级 build-profile：签名方案、产品及构建模式的区别](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-build-profile-app)
- [指定构建模式：右上角 Build Mode 与命令行参数](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-compilation-options-customizing-guide)
