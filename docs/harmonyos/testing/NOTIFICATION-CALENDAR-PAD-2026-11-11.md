# MatePad Mini 日历与代理提醒验收

日期：2026-11-11；设备 MatePad Mini；包名 `com.joinother.skyinstrument`，版本 1.0.10 / 1000054。覆盖安装保留数据，使用新 Debug Profile；未改变 Release 签名。

## 已完成

| 项目 | 观察与证据 |
| --- | --- |
| 代理提醒权益 | 新 Profile 覆盖安装成功，真实发布不再出现 `1700002`；签名核验另见 release 中的 Debug 清单 |
| 月历只读查询 | 固定时间速率后查询其他月份，模拟时间、选择和观测者状态不随查询改变；`/tmp/stellar-readonly-calendar-*` |
| 月历详情 | 满月详情图片无圆形裁切，月份数据包含四组事件；`/tmp/stellar-final-detail.jpeg`、`/tmp/stellar-final-calendar-detail.json` |
| 查看星空 | 显式查看满月后选中 Moon 并到对应 JD；`/tmp/stellar-final-view-time-complete.json`、`/tmp/stellar-final-view-selected.json`。随后恢复真实时间与实时速率 |
| timer 重启恢复 | ID9 发布后 force-stop 再查询，事件路由与精确事件时间保持；`/tmp/stellar-final-timer-restart-list.json` |
| timer 去重 | 同一请求返回同 ID9、`unchanged:true`；`/tmp/stellar-final-timer-dedup.json` |
| timer 进程退出后触发 | 再次 force-stop 后，系统在到点时显示测试通知；`/tmp/stellar-final-delivery.jpeg`。截图含其他私人通知，不入库、不对外展示 |
| timer 点击 | 点击系统通知后启动应用，`selectedEventId=moon-phase-1795532081-2` 且 loaded 为 true，截图为满月详情；`/tmp/stellar-final-click-calendar.json`、`/tmp/stellar-final-click.jpeg` |
| calendar 问题复现 | ID10 请求 2026-11-12 12:34:37，系统回读 12:34:00，其余指纹完全一致；`/tmp/stellar-calendar-seconds-diagnostics.json` |
| calendar 对照 | ID11 显式整分钟请求成功；`/tmp/stellar-calendar-minute-schedule.json` |

timer 到点后原 `expiredContent` 会立刻把正文替换成“提醒已结束”，容易被误解为天象结束；现已保持原事件正文。系统勿扰一直开启，未验收声音和振动。

## calendar 修复依据

官方 `reminderAgentManager.LocalDateTime.second` 文档与当前 SDK 允许 0–59 的可选秒值，没有承诺回读截秒。因此不把本设备现象描述成所有系统版本的保证。

本应用将 calendar 发布精度明确为整分钟：触发时刻向下取整至分钟，之后检查未来 30 秒门槛及静默时段。事件原始 `eventAt/JD` 保持精度，通知点击仍使用事件时刻。归属指纹继续严格比较秒字段，不通过忽略字段、认领旧记录或取消旧记录掩盖差异。

最终补丁 80/80 通知服务/控制器/feed/integration 行为测试通过；reminder 契约和 UI 契约通过；最终 `assembleHap` 成功。日志 `/tmp/stellar-reminder-final-tests.log`、`/tmp/stellar-reminder-final-build.log`。

## 最终包回归与恢复

- `/tmp/stellar-reminder-final-install.log` 确认最终修复包覆盖安装成功。
- ID13 以 `12:34:37` 原事件时间发布成功，系统定时为 `12:34:00`，expected/actual 指纹完全一致、owned 为 true；事件 `eventAt` 仍保留 37 秒，JD 对应原时刻。证据 `/tmp/stellar-minute-final-publish.json`、`/tmp/stellar-minute-final-readback.json`。
- force-stop 后重新发同请求，返回 ID13、`unchanged:true`；证据 `/tmp/stellar-minute-final-restart-dedup.json`。随后单独取消13成功，未等待次日该条 calendar 到点，因此不宣称它的真实到点精度已验收。
- 切换构建期间另出现 ID12（与旧 ID2 相同事件，journal 仍为修复前 6 秒指纹）；已保留诊断并仅取消本轮产生的重复12。精确触发来源未确认，不归因于 Profile；最终版对同事件旧提醒返回 `legacy-reminder-unverified`，不再新增或取消。证据 `/tmp/stellar-minute-final-readback.json`、`/tmp/stellar-minute-final-clean12.json`。
- 天象订阅偏好恢复 true，卫星/专题 false，静默开启 22:30–06:35，提前量5分钟；列表最终只有旧 ID2–7。第一次恢复 CLI 返回 UI timeout，随后状态回读及再次操作确认上述偏好和真实 `subscription-update-failed`，不将 timeout 当保存成功。证据 `/tmp/stellar-minute-final-state.json`、`/tmp/stellar-minute-final-restore-confirmed.json`。
- 旧 ID2–7 缺少可验证的归属元数据：保留其系统排程，但不自动认领、取消或把分类订阅报成功。**因此旧提醒迁移尚未完成，分类自动补排不是全流程验收通过。** 后续需提供明确的旧提醒整理/逐项重建流程；不得通过清空提醒绕过。

## 数据保护与剩余边界

- 旧提醒 ID2–7 始终保留；只清理本轮创建的 ID1、8、9、10、11、12、13。未使用 cancelAll。
- 诊断期间临时改动已按上述恢复；应用静默时段与系统勿扰均保留，卫星、专题订阅未开启。
- 卫星显式日期预测仍返回 `explicit_epoch_prediction_unsupported`；不回退到修改共享模拟时间的旧预测器，卫星自动订阅未验收。
- 日月食、流星观测率双曲线与食象地图尚未接入月历；研究材料中的功能不算本次实现。
- v2 内容服务、Push 发送和客户端签名清单激活尚未接通/部署；桌面 forms 保持关闭。
- 本文只保存证据路径和非敏感结论，不复制私人通知截图、精确位置或签名材料。
