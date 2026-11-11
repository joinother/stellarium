# 代理提醒 Debug Profile 核查（2026-11-11）

> 当前状态：Profile 与代理提醒 `1700002` 权益阻塞已解除。timer 提醒跨重启恢复、去重、进程退出后到点通知及点击满月详情已验证；calendar 秒精度修复后发布、严格指纹核验和重启去重也已通过。旧提醒迁移与分类自动补排尚未完成；详见 [Pad 验收](../testing/NOTIFICATION-CALENDAR-PAD-2026-11-11.md)。当前组合见 [Debug 签名材料清单](DEBUG-SIGNING-MANIFEST-2026-11-11.md)。

## 当前结论（已解决）

已复用云端 Debug 证书 `2079138516628955008` 及已验证匹配的现有本地 P12，创建唯一替代 Profile `2081506375845865984`（`skyinstrument-debug-capabilities-2026-11-11`）。完整 Profile 中已确认 `com.huawei.service.notification.agentreminder`，原六设备集合和全部旧能力保留。默认 Debug 配置已切换至 `.certs/debug-capabilities-2026-11-11/`，Release 材料未改，旧配置已归档。

## 父任务设备验证进展

### 23 时实测补充

- timer 测试 ID9：发布后 force-stop，重新查询仍保留事件元数据；相同请求返回 `unchanged:true`、同 ID。再次 force-stop 后系统到点显示通知，点击进入 `moon-phase-1795532081-2` 满月详情，`getCalendarState` 与截图一致。测试项已清理；系统勿扰保持开启，因此没有声响或振动验收结论。
- 证据：`/tmp/stellar-final-timer-restart-list.json`、`/tmp/stellar-final-timer-dedup.json`、`/tmp/stellar-final-delivery.jpeg`、`/tmp/stellar-final-click-calendar.json`、`/tmp/stellar-final-click.jpeg`。系统通知截图含其他私人通知，仅本地核验，不纳入仓库或发布。
- 诊断版再次构建、覆盖安装成功；77 项通知行为测试通过。calendar ID10 请求 `12:34:37`，系统回读 `12:34:00`，其他指纹字段一致；整分钟对照 ID11 成功。两测试项已取消，原 ID2–7 未改。证据 `/tmp/stellar-calendar-seconds-diagnostics.json`、`/tmp/stellar-calendar-minute-schedule.json`。这是请求精度与归属校验问题，不是 Profile 权益失败。
- 以下首次发布阶段记录保留作历史，不代表后续 timer 全流程仍未验证；calendar 分类订阅不能由 timer 成功替代验收。

- 父任务报告 `assembleHap` 成功，新 Profile 签名包已在 MatePadMini（`192.168.31.234:42713`）覆盖安装成功。安装日志 `/tmp/stellarium-new-profile-install.log` 已核对，包含 `install bundle successfully`。
- 父任务确认未卸载应用，用户数据保留；新旧 Debug 公钥不同并未阻止本次覆盖安装。
- 父任务报告 `scheduleAstronomyReminder` 成功，返回 `reminderId: 1`，证明本次单条提醒发布的 `1700002` 权益阻塞已解除。
- 验收边界：系统 list 返回结果剥离 `parameters`，分类订阅及实际到点触发尚未完整验收，Dalton 正在修复相关路径。发布成功不等于提醒全流程已通过；后续列表/分类问题不得继续表述为已确认的 Profile 权益缺失。
- 本轮仅更新文档，未修改签名配置或材料，未执行构建、安装或卸载。

## 历史：首次核查结论

首次核查时尚无经过验证、可切换的新 Debug Profile；当时未修改签名材料或创建 Profile。随后用户授权复用较新签名组合，完成了上述验证与切换。以下保留旧过程证据，不代表当前激活状态。

## 历史：首次核查非敏感证据

- 应用：`6917612145896121937`，包名 `com.joinother.skyinstrument`。
- 华为开发者中心 → 基础信息 → 开放能力管理：“代理提醒”显示审核通过，更新时间 `2026-11-03 17:33:23`；对应能力开关已勾选。无需再次提交申请或启用开关。
- CLI `acl-status` 返回空列表，`acl-query` 成功但无权限列表；这不代表代理提醒未通过。官方文档把它列为开放能力；`ohos.permission.PUBLISH_AGENT_REMINDER` 为 normal/system_grant 权限，不能仅凭受限 ACL 查询判断权益。
- 首次核查时，`default` 产品使用 `default` 签名配置，Profile 为 `.certs/debug-map-2026-11/skyinstrument-debug-map-2026-11.p7b`，现已归档为 inactive。
- 原云端 Debug Profile：`2075053451884114240`，`skyinstrument-debug-map-2026-11`，绑定六台设备。重新下载并解码，仍只有原有透明卡片、IAP、Map Kit、Push、待机屏保卡片及 AI 问答联网能力；`allowed-acls` 为空，未发现 reminder 标记。
- 使用完全相同的六个设备记录 ID 尝试更新原 Profile，AGC 返回 `204144642` / `[AppGalleryConnectProvisionService]provision can not be modified.`，未成功更新。
- 当时云端证书列表只返回一张 Debug 证书：`2079138516628955008` / `auto_debug_2850086000493876986.cer`。其叶证书及公钥与工程旧 `.cer` 和旧 Profile 内嵌叶证书不一致；旧工程证书链中的叶证书与旧 Profile 匹配。后续在 DevEco 现有材料中找到并验证了较新证书对应的 P12。
- 旧叶证书有效期至 `2027-10-29 13:21:38`（北京时间）；云端现存 Debug 叶证书有效期至 `2027-11-08 15:47:05`。不能仅比较 PEM 链中的第一张根证书，必须比较叶证书。

## 历史：原阻塞及解除方式

原 Profile 无法通过现有 CLI 更新，旧签名叶证书也不在云端可用证书列表中，因此当时没有直接替换 p7b。后续复用 DevEco 已有的较新证书、P12 和密码配置，验证私钥与证书匹配后生成一个替代 Profile，验证设备与能力后整体切换默认 Debug 材料，解除该阻塞。

原阻塞已解除；后续覆盖安装、timer 到点与点击结果见上文“父任务设备验证进展”。calendar 分类订阅仍需独立验收，不能把单条 timer 成功描述为全部提醒流程已通过。

## 官方依据

- [代理提醒开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/agent-powered-reminder)：审批通过并开启能力后，调试/发布应用需重新生成 Profile 并手动签名。
- [代理提醒错误码](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/errorcode-reminderagentmanager)：`1700002` 也可表示未获权益、上限为零；空提醒列表不能排除此原因。

仅保留非敏感结论；未记录 UDID、私钥、口令、访问令牌或签名下载 URL。
