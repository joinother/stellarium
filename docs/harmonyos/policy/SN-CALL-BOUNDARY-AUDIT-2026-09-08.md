# SN 调用边界与最终包核验

## 结论与证据等级

不能把“普通 HiLog 没有 SN”当作无调用证明；也不能因为系统拒绝返回 SN 就认为没有尝试访问。此次保留用户要求的同意后 SDK 能力，整改目标是有效同意前不进入该初始化链，而不是让静态扫描找不到 SN 字符串。

已有证据是源码调用链、执行分支回归、最终 Release 字节码及原生运行段一致性、真机同意时序。尚无新 Release 包的华为隐私专项复测结果，不保证审核通过或声称所有潜在反射调用已形式化证明。

`Cannot get SourceMap info, dump raw stack` 表示源码映射不可用。华为 JS Crash 文档明确列出 Release 安装包不含 SourceMap 时的同类提示；这一行本身无法证明检测人员采用了哪一种检测技术。静态反汇编辅助确定可达路径，运行时栈、调用时间与同意状态用于判断实际发生的行为。旧1000049栈不能直接用1000050的当前行号或映射文件解释。

## 全局检查范围及发现

检查应用 `harmonyos/ets-source`、`harmonyos/cpp-source`、`src`、`plugins` 中设备标识接口、deviceInfo 属性、初始化入口及唯一标识调用；检查生成工程原生库的设备信息接口字符串；再检查与 SDK SBOM 一致的 qtbase 97575d35 源码。

| 位置 | 核验结果 | 处理 |
| --- | --- | --- |
| 应用主入口 `QAbilityStage.initQtAppContextImpl` | 应用源码唯一 `qpa.setupQtApplication` 调用处 | 放行标记和当前政策校验；两次异步资源准备后分别再校验 |
| `QAbility.initializeQtAbilityIfNeeded` | 转入 Stage 前检查当前同意，启动单请求串行化 | 保留，回归覆盖 |
| `process/QChildProcess.ets` | 备用 `runQtChildProcess` 入口原先缺同样门禁 | 本轮补 `hasCurrentPrivacyConsent`，失败直接返回，不创建工厂、不进入 Qt |
| Qt `qohosjsmain.cpp` | `initDeviceInfo` 批量表包含 `serial`、`udid`，通过 `@ohos.deviceInfo` 读取并缓存 | 同意后能力保留，不输出标识值 |
| Qt `qoperatingsystemversion.cpp` | 另一处 deviceInfo 访问只读取 majorVersion/seniorVersion/featureVersion | 与 SN 区分，不误报成序列号读取 |
| 生成库 | 相关接口字符串命中 libqohos 和 libQt6Core，与上述两条源码路径对应 | 字符串检索是线索，不是所有执行路径覆盖证明 |
| 应用 `useDeviceLocation` / `startGyroscope` | 定位和姿态属于独立数据入口，不是它们为了计算而读取 SN | 继续维持当前同意、主动触发、权限、前后台和停止条件 |

确认的两条初始化链：

```text
当前隐私同意 → QAbility → QAbilityStage.initQtAppContextImpl
  → qpa.setupQtApplication → setupQtApplicationImpl → initAppData
  → initDeviceInfo → @ohos.deviceInfo.serial / udid

当前隐私同意 → QChildProcess.onStart → qpa.runQtChildProcess
  → setupQtApplicationImpl → initAppData → initDeviceInfo
```

备用子进程路径静态存在，不代表其曾在用户审核场景实际运行。没有删除字段、扩大受限标识权限、按检测环境隐藏调用或改写系统返回值。

## 最终包核验与防回退

执行 `node scripts/check-ohos-privacy-artifact.mjs`。脚本从实际签名 HAP 提取 `ets/modules.abc`，使用 SDK `ark_disasm` 检查主入口三处校验及子进程门禁确实进入最终字节码；同时核对包内 libqohos 与匹配 SDK 补丁库的28个可加载文件内容节。

Hvigor 会去除调试符号，因此整个 .so 文件 SHA256 与构建目录不同是预期现象，不能直接当成旧库；本轮28个运行内容节逐一一致。此一致性检查不替代对其他 SDK/新增库的审计。

新检查真实挡住了一次漏同步：原同步脚本白名单没有 QChildProcess，导致主 Release 仍打入旧入口。已补同步条目及回归；重新打包后检查通过。旧 Debug 包作为负例也被正确拒绝。不能把之前一次构建成功视作修复已进包。

当前 Release 核验快照（仅对应本轮产物，重新构建后须重新生成）：

- 1.0.9 /1000050；HAP SHA256 `5f0fec6ec9a9888241680d1f48cc6714e6151f75b9107b2407151b046e7ab686`。
- ArkTS 字节码 SHA256 `d1f519d11f411f5aed1298c55e781fd1b43c595c8a5c1ff304d84cbc3b46d0be`。
- 包内 libqohos SHA256 `59e5c567a6fcaf140fc9f1cd8dcef9fe0644932b3f899c49c57ec0eca614bdc8`。
- SourceMap 位于同次构建的 `outputs/default/symbol/release/entry-sourceMaps.map`；同目录保留 nameCache。不要将新映射文件套用于旧包，也不将映射、反汇编全文或原始设备日志提交 Git。
- 包内权限仍仅模糊定位、精确定位、加速度计、陀螺仪；无 INTERNET、ACCESS_UDID。

## 动态验证与剩余验收

- 47项隐私/启动/剪贴板/审核回归通过，包括未同意、旧政策、拒绝、隐私接口异常时备用子进程零 Qt 调用。
- 主工程 Release、独立 Debug assembleHap 均通过，签名配置摘要保持不变；Debug 已安装 Pad，主 Release 未改为 Debug。
- Pad 主进程48255同意校验后进入一次设备信息初始化；SN/UDID返回系统错误 -14700103，未取得标识的成功证据。20次复制及面板查询83响应、最高697ms，进程未更换。
- 最终子进程门禁包 Pad 进程53981正常进入2560×1600星图，同意后时序检查通过；再跑20次复制/面板查询共83响应，最高790ms，进程不变，采样日志没有本进程AppFreeze关键词。资源准备387ms，创建到首帧10.9秒、完整进入13.6秒，启动仍需优化。备用子进程的真实启动未单独强制触发，不能将主进程测试等同于其真机路径验证。
- 前轮撤回后一分钟等待已通过；本轮继续增加异步后的校验和字节码检查。还需以最终提交包复测：首次未同意、拒绝、撤回后重启、政策版本更新、正常同意、后台/恢复、定位和姿态开关。
- AppAnalyzer官方上架体检文档列出的隐私规则包含权限用途等项目，并不据此推断它覆盖华为审核全部 SN 运行时拦截能力。最终需取得相应隐私专项结果并核对软件包摘要/版本。

## 官方资料

- [JS Crash：日志与 SourceMap 提示](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/jscrash-guidelines)（华为 MCP 已查询）。
- [隐私管理服务](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/store-privacy)（MCP已读全文）：采用当前政策的系统签署结果；自定义链接元数据示例仅为未上架 Debug 模拟接入，不能当作 Release 绕过托管方案。
- [上架合规体检](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-app-analyzer-ag-policy)（MCP已读全文）：真机、签名、解锁亮屏及实际列出的规则范围。
