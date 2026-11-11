# Debug 签名材料清单（2026-11-11）

## Active

- 应用 `6917612145896121937`，包名 `com.joinother.skyinstrument`。
- `build/libstellarium-harmonyos/build-profile.json5` 的 `default` 签名配置使用 `.certs/debug-capabilities-2026-11-11/` 中的 `debug.cer`、`debug.p12`、`skyinstrument-debug-capabilities-2026-11-11.p7b` 和配套 `material/`。`default` 产品继续指向 `default`，Release 配置和材料未改动。
- 复用云端证书 `2079138516628955008`（`auto_debug_2850086000493876986.cer`），未新建证书。对应本地材料来自 DevEco 的 `default_nightwindow_*` 组合，已有密码配置只在内存中使用，未猜测、输出或记录明文。
- 唯一新建 Profile：`2081506375845865984`，`skyinstrument-debug-capabilities-2026-11-11`，类型 Debug。未传 `--acls`，未删除或修改其他云端记录。
- 已验证：CMS 内容签名有效（未单独验证完整 CA 信任链）；包名正确；Profile 内嵌叶证书匹配复制的证书；P12 私钥签名可由该叶证书验证；六设备集合与旧 Profile 完全一致；全部旧能力键和值均保留。
- 叶证书到期：`2027-11-08 15:47:05`（北京时间）。
- 配置 `keyAlias` 为 P12 中实际别名 `debugkey`。复制后的本地材料再次验证可解密并匹配证书；配置比对确认仅 `default.material` 改变。
- Active p7b SHA-256：`aa9ca7c016bb2ac8f7b9e124a0e9ecbac3beaa1cc53f3d3be72abc2a057eb72e`。

## 完整 app-services-capabilities

以下十项在下载后的 Profile 中均为存在的对象字段：

```text
com.huawei.service.desktop.transparentForm
com.huawei.service.device_security.device_verify
com.huawei.service.device_security.safety_detect
com.huawei.service.iap
com.huawei.service.liveView.entry
com.huawei.service.mapkit
com.huawei.service.notification.agentreminder
com.huawei.service.push.base_service
com.huawei.service.standby.form
webAccessServiceForAIQA
```

`acls.allowed-acls` 仍为空，`app-privilege-capabilities` 为空数组。代理提醒权益依据是 `com.huawei.service.notification.agentreminder`，不以 `strings PUBLISH_AGENT_REMINDER` 或受限 ACL 列表作为判定标准。新增实况窗等字段由 AGC 按已启用能力签发，未修改应用 manifest 或启用卡片。

## 本次 Skill 纠偏记录

- `agc-profile-acl` 中将代理提醒直接称为 ACL/system_basic 的表述不适用于本次官方资料：`ohos.permission.PUBLISH_AGENT_REMINDER` 为 normal/system_grant，手机等设备还受独立开放能力权益管控。ACL API 空列表不能证明开放能力未审批。
- 不使用 `strings PUBLISH_AGENT_REMINDER` 作为权益有无的充分判据；解码完整 Profile，核对 `app-services-capabilities` 中的 `com.huawei.service.notification.agentreminder`，结合控制台审批/开关状态及官方指南，最后由设备实际发布和触发验证。本次未传未知 `--acls` 权限。
- PEM 文件可能是证书链，第一张根证书相同不能证明签名组合相同。应比较叶证书、公钥，并以 P12 私钥签名验证配套关系。
- 旧证书不匹配不等于没有可用材料。本次在用户明确授权检查 DevEco 现有材料后，找到较新配套 P12 与已有配置，无需生成证书、猜密码或删除记录；原 Profile 更新失败后只创建了一个替代 Profile。
- 签名配置、备份及 `material/` 均需单独检查 Git 忽略覆盖，不能因为 `.p12` 被忽略就假设其他敏感材料也被忽略。此处仅记录教训，不修改 Skill 文件。

## Archive / 回滚

- 旧 `.certs/debug-map-2026-11/skyinstrument-debug-map-2026-11.p7b`、原 DevEco `default_PcShowcase_*` 证书与 P12 原地保留，标记为 archived/inactive，仅用于回滚。
- 切换前完整配置快照：`.certs/archive/debug-before-2026-11-11/build-profile.json5`。快照含加密的签名配置，属于本地私有材料，不入库、不输出。
- 回滚时仅将该快照中的 `default.material` 恢复到当前工程配置；如期间父任务修改了其他配置，不要直接覆盖整个文件。新材料与旧材料均保留，不需要删除任何记录。

## 构建、设备验证与验收边界

最终修复包已覆盖安装；calendar ID13 已通过发布、指纹核验、重启去重和单项清理，精确事件时间保留。旧 ID2–7 保留且来源未核验，分类补排明确报未完成，不冒充整体通过。最新记录见 [Pad 验收](../testing/NOTIFICATION-CALENDAR-PAD-2026-11-11.md)，以下保留各阶段 Profile 验证经过。

父任务报告 `assembleHap` 成功，新 Profile 签名包已在 MatePadMini（`192.168.31.234:42713`）覆盖安装成功。已核对 `/tmp/stellarium-new-profile-install.log` 中的 `install bundle successfully`。父任务确认未卸载应用、用户数据保留；本次覆盖安装已验证可接受新的 Debug 签名组合。

父任务报告 `scheduleAstronomyReminder` 发布成功，返回 `reminderId: 1`，本次单条发布的 `1700002` 权益阻塞已解除。这是在 Profile 字段校验之外获得的设备端发布证据。

后续实测 timer ID9 已通过跨重启元数据恢复、重复请求去重、force-stop 后到点显示及点击进入满月详情；测试项已清理。系统勿扰未关闭，不宣称声音/振动通过。日历类另发现秒字段由系统回读为零（37 → 0），整分钟对照发布成功；诊断测试 ID10/11 已清理，原 ID2–7 保留。calendar 分类订阅仍须修复和独立验证，不能混同于已解除的 Profile 权益阻塞。完整证据与边界见 [代理提醒核查](AGC-REMINDER-PROFILE-CHECK-2026-11-11.md)。

本 Profile 子任务未执行构建、签名 HAP、安装或卸载；上述构建与运行结果由父任务提供，安装成功另有日志核对。本轮仅更新两份 Profile 文档，未修改签名配置或材料。

依据：[华为代理提醒指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/agent-powered-reminder)、[1700002 官方解释](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/errorcode-reminderagentmanager)。所有本地签名材料位于忽略目录；本清单不包含口令、私钥、UDID、访问令牌或签名下载 URL。
