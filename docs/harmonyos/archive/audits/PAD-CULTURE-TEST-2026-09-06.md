# MatePad Mini 文化资料与星座译名回归

日期：2026-09-06。设备：MLR-AL00，HarmonyOS 无线调试。

## 已执行

- 最低亮度 1、关闭自动亮度，调试息屏超时 24 小时。不是永久关闭息屏。
- 使用已有签名配置构建并覆盖安装，没有清除用户数据或修改签名配置。
- 全量文化修订回归：43 个打包语言 × 日本、藏族、满族文化 = 129 组通过。
- 最终 UI 修订包复测：简体中文、英语、波斯语、马拉雅拉姆语、僧伽罗语、泰卢固语 × 3 文化 = 18 组通过。
- 7 项主机回归通过；C++、CompileArkTS、assembleHap、差异检查通过。

## 真机发现并修复

1. CLI 立即退出造成长 JSON 的管道输出截断；日志分块解析遗漏 Unicode 行分隔符、删除边界空格。改为完整输出、原生日志过滤、保留分隔符与空格、跨轮累计分块。
2. 旧“乱码清理”误删语言的合法连接符，首次 129 组中有 10 组失败。核心及 ArkTS 现在保留 U+200B/U+200C/U+200D/U+2060，第二轮全部通过。
3. 星座全名虽然已从核心返回，但概要指标使用初始参数快照，截图仍为旧英语。指标直接读取响应式状态，并让 CLI 语言切换与 UI 使用同一流程。截图核验同一 M31 从 Andromeda 更新为“仙女座”。

## 可复现检查

```sh
scripts/prepare-ohos-device.sh <设备> prepare
python3 scripts/test-ohos-skyculture-editorial.py --device <设备> --output /tmp/culture-report.json
node --test scripts/test-ohos-cli-response.mjs scripts/test-ohos-skyculture-text.mjs
```

测试会切换语言和文化；不要与手动操作同时运行。结束后自动恢复这两项设置。可用 `--languages zh_CN en fa ml si te` 执行重点回归。

## 证据与边界

- 机器报告：`skyculture-pad-regression-2026-09-06.json`、`skyculture-pad-ui-regression-2026-09-06.json`。
- 本机截图：`/tmp/pad-ui-m31-en.jpeg`、`/tmp/pad-ui-m31-zh.jpeg`；临时目录图片不是永久档案。
- 最终已安装 HAP SHA-256：`c332f873c0956dea195530368167939538d47c976c3f052588ad0a0134fd3232`。
- 回归范围是六处修订与统一编辑说明，不是所有文化正文的逐段语义审定。缺译内容明确记录为修订源文回退。
- 英语截图仍有硬编码中文的固定说明与分栏，已登记为后续国际化问题，不包含在本轮修复完成范围内。
