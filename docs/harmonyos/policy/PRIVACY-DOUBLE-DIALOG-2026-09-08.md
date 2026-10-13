# Privacy Manager 双弹窗真机核查

## 已确认的现象

2026-09-08 23:14，通过无线调试检查 MatePad Mini，安装包为 `1.0.9 / 1000050`、`debug=false`。不是本地 1000051，也未安装上一轮应用请求合并补丁。仅执行一次启动，未替用户点击同意或撤销同意。

同一次启动，应用主进程 20204、主窗口 604 内出现两个 `ModalPage → UIExtensionComponent`。两者均展示相同隐私正文和同意按钮，拥有不同的 `DisposeAlertAbility` 实例，不是无障碍树同一节点的重复输出。

| 时间 | 证据 |
| --- | --- |
| 23:14:11.382 | 应用唯一一次 `dialog-request-start` 及 `NAPI_RequestAppPrivacyConsent called` |
| 23:14:11.385 | AppGalleryKit 创建第一个隐私 UIExtension；系统 `disposed_observer` 同时收到 `onPageShow` |
| 23:14:11.389 | 主动请求返回 sessionId `1156497410` |
| 23:14:11.390 | 第二个 UIExtension 创建，sessionId `1156497411` |
| 23:14:12.187 / .278 | 两个 AppGallery 隐私实例分别记录 `privacySource:0` 和 `privacySource:1` |

## 根因与官方依据

通过华为开发文档 MCP 取得[隐私管理服务](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/store-privacy)完整正文。该文档说明：接入托管后，未签署时打开应用由系统展示隐私弹框；撤回后重新打开也会再次展示。应用可监听 `usual.event.PRIVACY_STATE_CHANGED` 感知签署结果。`requestAppPrivacyConsent` 用于需要主动请求的场景，不应无条件叠加在托管启动流程上。

结合单次主动调用、系统启动拦截时序及两个真实 UIExtension，本次原因是系统自动展示与应用启动主动展示并行。不能归因于 Qt 子进程，也不能声称上一轮模块内 Promise 合并已解决此次真机现象。

## 修订

- 启动页不再主动调用 `requestAppPrivacyConsent`，改为订阅官方签署结果事件。
- 订阅后立即核验当前协议，覆盖此前已同意及注册期间已完成签署的情况。
- 事件只作为重新核验的提示；不把事件载荷、其他应用事件或旧协议同意当作本应用授权。仍要求当前协议 ID、版本、类型和签署状态匹配。
- 手动“查看隐私提示/重试”入口保留，模块内请求合并和根页面加载锁保留。
- 页面退出退订，异步注册/请求在页面退出后不得放行 Qt；重复事件仅通知一次。
- 不修改签名、Build、权限、协议正文或 SN/UDID 读取策略，不以超时、错误或无弹窗作为同意。

## 验证边界

32 项隐私启动回归通过，包括系统托管启动零主动请求、事件后二次核验、重复事件、注册竞态、退订及订阅失败关闭门禁。源文件与生成工程定点同步。

另有 7 项审核整改回归通过；release `default@CompileArkTS` 成功（4.661 秒），仅保留既有 NODE/onScroll 弃用告警。初次尝试的非限定任务名和带节点前缀任务名未找到任务，改用 module 模式的 `default@CompileArkTS` 后实际编译通过；未改变编译模式或签名绕过错误。

本次设备证据复现的是旧包问题。新代码尚未重新打包安装，不得将单元测试或 ArkTS 编译成功写成真机双弹窗已消失；正式验收需检查首次启动、已同意重启、拒绝、撤回重启及协议版本更新。

原始日志和截图仅保留本机 `/tmp/stellarium-privacy-pad-started.log`、`/tmp/stellarium-privacy-layout.json`、`/tmp/stellarium-privacy-dialog.jpeg`，不提交完整设备日志。
