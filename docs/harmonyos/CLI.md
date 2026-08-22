# Stellarium 鸿蒙 CLI

## 范围

CLI 通过 DevEco 自带的 `hdc` 和鸿蒙官方 `aa start --ps` 启动参数控制应用。它不启动 HTTP 服务、不访问公网、不上传观测位置或设备标识，适合未备案版本的本地调试和自动化测试。

应用收到命令后，会等待隐私同意、Qt 初始化和原生命令桥就绪，再执行命令；结果通过带请求 ID 的 `hilog` 记录返回给 CLI。首次启动若尚未同意隐私政策，CLI 会等待至超时，完成同意后重新执行即可。

## 使用

在仓库根目录执行：

```bash
node scripts/stellarium-cli.mjs --command getAppState
node scripts/stellarium-cli.mjs --command searchObject --payload M31
node scripts/stellarium-cli.mjs --command setFOV --payload 60 --json
```

多设备连接时必须指定设备：

```bash
node scripts/stellarium-cli.mjs --device 7LZBB26323200303 --command getTimeInfo --json
node scripts/stellarium-cli.mjs --device 7LZBB26323200303 --command getDeepSkyImageStatus --json
node scripts/stellarium-cli.mjs --device 7LZBB26323200303 --command getDeepSkyImageStatus --payload 'all|0|32' --json
```

`--payload` 沿用 `StellariumOhos_command` 的原有字符串格式。例如 `selectAt` 使用 `x|y|skyW|skyH`，`setActionChecked` 使用 `actionId|1`。CLI 会自动处理 `aa --ps` 对负号开头字符串的限制，并对 payload 做 shell 转义，保证竖线分隔参数不会被 `hdc` 远端 shell 当成管道。命令名不在 CLI 中硬编码，桥接层已支持的命令均可直接调用；可执行 `--help` 查看工具参数。

## 官方依据

鸿蒙官方 `aa` 工具支持显式启动 Ability 以及 `--ps <key> <value>` 字符串 Want 参数；官方 Want 文档将 `parameters` 定义为应用间传递自定义键值的载体。当前实现使用这些参数，不注册自定义 URI，不新增网络端口。

官方开发建议还包括：

- 使用 `aa start -W -b <包名> -a <Ability>` 测量 Ability 从启动请求到首帧或前台的耗时，适合定位“正在唤醒星空”或启动卡顿。
- 使用 `aa force-stop <包名>` 清理上一次进程状态，再执行冷启动测试；不要用强制停止代替正常生命周期测试。
- 使用 `hdc shell hilog` 查看系统日志，按请求 ID、包名和日志标签过滤，避免把完整日志流直接回传到主机造成丢行。
- 使用官方 `uitest` 命令进行界面级自动化：`screenCap` 截图、`dumpLayout` 获取控件树、`uiInput click/swipe/drag/keyEvent` 注入触摸和键鼠事件。

例如，启动耗时和界面检查可以这样执行：

```bash
hdc -t 7LZBB26323200303 shell aa start -W -b com.joinother.skyinstrument -a QAbility
hdc -t 7LZBB26323200303 shell uitest screenCap -p /data/local/tmp/skyinstrument.png
hdc -t 7LZBB26323200303 shell uitest dumpLayout -b com.joinother.skyinstrument -p /data/local/tmp/skyinstrument-layout.json
hdc -t 7LZBB26323200303 shell uitest uiInput keyEvent 2050
```

上述 `uitest` 命令属于设备端调试工具，不是应用运行时能力；正式包不会因此增加端口或网络权限。官方文档：[`aa工具`](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/aa-tool)、[`SDK命令行工具简介`](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/command-line-tools-overview)、[`UI测试`](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/uitest-guidelines)。

## 限制

- CLI 需要已连接、已授权的 `hdc` 设备和可调试安装包。
- 结果通过日志回传，超大结果可能受系统日志单行长度限制；查询类命令建议按范围或数量参数分批调用。
- `getDeepSkyImageStatus` 默认检查重点图片；传入 `--payload 'all|偏移|数量'` 分页列出已复制 PNG，单页数量最多 64。`onDisk` 只代表资源已复制，`textureReady` 才代表当前惰性纹理树已经取得可绑定纹理；`textureLoading` 表示正在后台读取，`textureNotStarted` 表示尚未开始绑定。没有进入当前视场的图片可能保持未实例化，不应据此判定资源缺失。
- 连续视图命令（如 `dragView`、`zoomBy`）返回“已入队”，不等待逐帧完成。
- 这是开发者控制通道，不是面向普通用户的应用内命令行界面；Release 包也不会因此监听网络端口。
