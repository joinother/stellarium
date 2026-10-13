# 托管隐私启动状态衔接（2026-09-09）

## 根因和修复

`PrivacyBootstrap.observeSystemConsent` 原先把订阅完成后的“当前尚无有效同意”立即写为 `requestFailed=true`。这是等待状态，并非服务失败。系统自动弹窗打开前会因此闪出“星图尚未启动”；同意核验成功时未清除错误状态，Qt 异步准备期间又继续显示这段提示。

- 正常等待只保留原有 StartupSky 星点背景，不自动调用第二次系统弹窗。
- 等待15秒后只提供手动查看隐私提示和关闭入口，不认定拒绝、不自动重试、不放行 Qt。用户长时间阅读协议不显示失败文案。
- 实际订阅异常、手动请求返回拒绝或错误才显示恢复提示。手动请求期间隐藏旧错误，保留并发锁与点击间隔。
- 核验当前协议同意后立即清空错误、帮助及请求状态，并取消等待计时器。晚到的失败回调不能重新覆盖已核验状态。
- `stellariumPrivacyConsentVerifiedUi` 只提前显示同一个根页面里的加载说明和转圈；不用于资源、设备信息、Qt 或子进程授权。根页面初始化重置为 false；真正 NativeNode 仍要求原有 nativeAllowed 与 qtContentReady 同时满足。
- 没有修改 SN/UDID 读取代码、协议、签名、构建号、联网权限或已有锚定改动。

## 官方依据

通过华为开发文档 MCP 查询：[PrivacyManager](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/store-privacymanager)、[系统公共事件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/commoneventmanager-definitions)。隐私签署事件是核验时机，不把“收到事件”直接当作授权；仍检查当前协议 id、版本、类型与 FULL_MODE_AGREED。没有结果与结果为不同意不能混为一谈。

## 验证

- 58项隐私、启动星点及锚定回归通过，覆盖等待不报错、长期等待只显示帮助、订阅失败恢复、手动拒绝、并发重试、同意清空旧错误、晚到异常隔离及销毁计时器。
- 生成工程同步成功；CompileArkTS/Release assembleHap成功，用时9.091秒，保留既有废弃API告警。
- HAP产物审计通过：主初始化3处隐私检查、子进程门禁保留，Qt平台28个运行内容节匹配。不是穷尽控制流证明，也不是系统隐私扫描。
- 无线 MatePad Mini 覆盖安装成功，仍为1000052、Default签名、Release编译。签名配置SHA256不变，未清除数据、未卸载、未生成发布APP。
- 未同意启动进程54280：从创建至用户取消约38秒，探针保持 accepted=false、qtAbilityCreated=false、qtInitialized=false；截图为单个系统隐私弹窗。依据截图对系统“取消”做触摸命中测试，成功退出，未代点同意。
- 用户亲自同意后，进程54916记录：00:37:57.853核验通过，00:37:58.134释放Qt门禁，00:37:58.730进入SDK设备信息读取，00:38:08.068完成星图呈现。CLI返回ready=true、2560×1600，截图确认星图及详情可见，无残留恢复窗口。
- 没有捕获用户点同意瞬间的连续视频，不将最终截图当成逐帧无闪烁证明。恢复页“重试/关闭”的异常服务场景本轮通过逻辑测试，未在正式设备伪造云服务错误强行展示。隐私同意入口不接入自动接受CLI。

## 本机证据

- `/tmp/privacy-ui-tests.log`、`privacy-ui-sync.log`、`privacy-ui-hap.log`、`privacy-ui-install.log`。
- `/tmp/privacy-ui-artifact.json`，HAP SHA256：`80796596138d8510985a13f51b43bde4125f5fdb87bf2e9e6229aac09e955655`。
- `/tmp/privacy-ui-device-start.log`、`privacy-ui-second-start.log`、`privacy-ui-accepted.log`及`privacy-fixed-prompt.jpeg`、`privacy-fixed-accepted.jpeg`。
- 日志只作本机诊断，不提交完整设备日志。QAbility旧探针名 `privacy-request-start` 当前表示同意复核，不是再次调用 requestAppPrivacyConsent；后续诊断不要仅凭这条旧名称判断重复弹窗。
