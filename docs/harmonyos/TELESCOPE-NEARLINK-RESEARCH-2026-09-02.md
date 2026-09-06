# 星闪望远镜控制预研

更新时间：2026-09-02

## 结论

星闪可以作为平板与望远镜设备之间的本地无线传输层，但它本身不是 GoTo 控制协议。GoTo 表示望远镜赤道仪或经纬仪具备自动转向能力；真正的控制仍需要设备厂商提供的命令协议、服务 UUID、属性 UUID、坐标格式、确认帧和错误码。

因此本项目可以按下面的目标推进：

- 平板通过星闪发现、配对和连接支持星闪的望远镜终端。
- 通过协议适配器发送 GoTo、Sync、Abort Slew、位置读取和状态查询。
- ArkUI、统一 CLI 和星图标记共用同一套望远镜领域状态，不把星闪 API 直接写进星图业务。
- 未取得真实设备协议和硬件验证前，只提供“规划中/设备能力待确认”，不把已配对设备伪装成可控制望远镜。

当前仓库还没有接入星闪生产代码，也没有真实星闪望远镜作为测试设备。本报告是接口、数据边界和落地路线，不代表已经支持星闪硬件。

## 当前基线

### 鸿蒙端现状

鸿蒙端在 `src/StelMainView.cpp` 中使用轻量望远镜桥，支持 1–9 个设备槽、离线模拟器、LX200 TCP、J2000/JNow、转向、同步、中止、位置回读、平滑标记和视场圈。ArkUI 与 CLI 共用持久化配置。完整桌面 `TelescopeControl` 插件尚未作为鸿蒙插件加载。

当前真实设备路径只支持用户主动指定的本机/局域网 LX200 TCP 端点；不自动发现、不扫描、不后台连接，公网地址和主机名在创建 socket 前拒绝。现有 CLI 仍是后续星闪接入的唯一控制面之一，不能另起一套仅供 UI 使用的命令。

### 工程版本约束

当前两个 HarmonyOS 工程的 `compileSdkVersion` 和 `targetSdkVersion` 均为 `6.1.1(24)`。本轮不修改 `build-profile.json5`，不修改签名、证书、Profile、权限或联网封口。

星闪官方文档存在两套模块名称：

| 文档模块 | 当前文档标注 | 本项目处理原则 |
|---|---|---|
| `@kit.NearLinkKit` | `manager`、`remoteDevice`、`ssap`、CDSM 文档覆盖 API 13/18/23/24 | 作为当前 API 24 预研基线，接入前仍要用本机 SDK 编译探测 |
| `@kit.ConnectivityKit` | 部分新版 `js-apis-nearlink-*` 文档标注 API 26 | 不在当前 API 24 工程中直接引用，升级 SDK 后单独评估迁移 |

## MCP 核对的官方能力

以下结论来自华为开发者知识 MCP 在 2026-09-02 的查询，正式接入前仍需在 DevEco 和目标 Pad 真机上复核 API 签名及设备能力。

### 基础开关和远端设备

官方 `@kit.NearLinkKit` 文档提供：

- `manager.getState()`：读取星闪开关状态。
- `manager.isNearLinkSupported()`：查询本端是否支持星闪，官方文档标注起始版本为 API 6.1.0(23)。
- `remoteDevice.createRemoteDevice(address)`：按星闪地址创建远端设备实例；官方要求使用形如 `11:22:33:AA:BB:FF` 的地址。
- `RemoteDevice.startPairing()`：发起配对并由系统弹窗要求用户确认。
- `getPairingState()`、`getConnectionState()`、`getAcbState()`：分别读取配对、连接和逻辑链路状态。
- `getDeviceName()`、`getDeviceClass()`、`getDeviceInformation()`：读取名称、设备类别和厂商/型号数据。
- `manager` 和 `remoteDevice` 支持连接、配对状态事件；所有事件都要在页面销毁或断开时取消订阅。

需要 `ohos.permission.ACCESS_NEARLINK` 的接口在未授权、设备关闭或设备不支持时可能返回权限、能力不支持或星闪关闭错误。错误码 801 不能当成设备离线重试成功。

### SSAP 数据承载

官方 `ssap` 文档提供星闪服务交互协议能力：

- 创建客户端并连接远端设备。
- 获取服务和属性，按 `serviceUuid`、`propertyUuid` 读写属性。
- 支持有响应写、无响应写和通知订阅。
- 支持连接状态事件和 MTU 变化。
- 文档示例使用 `ArrayBuffer` 承载二进制数据，服务 UUID 和属性 UUID 由设备服务定义。

官方 FAQ 提醒，连续调用 `writeData`/写入接口可能造成发送队列拥塞，建议控制发送间隔，示例建议约 10 ms。望远镜的高频位置回报、转向指令和停止指令必须放进一个有序命令队列，不能由多个 UI 回调并发写入。

### CDSM 与跨设备协同的边界

CDSM 用于星闪合作设备集合管理，不等于望远镜控制协议，也不保证某台设备暴露赤道仪控制服务。`abilityConnectionManager` 适合平板与另一台鸿蒙设备之间传输 UI 状态、时间、选中目标或视角；它不能代替星闪望远镜的 SSAP 服务，也不能把另一台设备自动变成 GoTo 设备。

## 术语和设备分层

| 名称 | 含义 | 项目中的处理 |
|---|---|---|
| 星闪终端 | 具备星闪无线能力的手机、平板、遥控器、成像设备、网络设备或厂商设备 | 只能说明传输能力，不能说明望远镜能力 |
| GoTo 设备 | 能按目标坐标自动驱动赤道仪/经纬仪转向的设备 | 通过协议能力表确认 `goto`，不能由设备类别猜测 |
| 望远镜本体 | 光学筒、相机或目视设备 | 通常由赤道仪或控制盒负责通信，不一定直接支持星闪 |
| 星闪控制盒/转接器 | 把星闪 SSAP 服务转换为厂商串口、LX200 或其他协议 | 需要厂商协议文档；可作为首个真实硬件验证对象 |
| LX200/NexStar/SynScan | 望远镜控制协议 | 位于传输层之上；同一协议可以跑在 TCP、串口或星闪适配器上 |
| INDI/ASCOM/Alpaca/RTS2 | 设备驱动或服务生态 | 更适合由本机/局域网桥接，不应假设能直接跑在星闪 SSAP 上 |

## 推荐架构

```text
ArkUI / 统一 CLI / 脚本
          |
TelescopeControlService
          |
TelescopeTransportManager
          |
TransportAdapter
  |-- NearLinkAdapter (SSAP)
  |-- TcpAdapter
  |-- SerialAdapter
  |-- DistributedAbilityAdapter
  |-- OfflineSimulatorAdapter
          |
TelescopeProtocol
  |-- LX200
  |-- NexStar
  |-- SynScan
  |-- INDI bridge
  |-- ASCOM/Alpaca bridge
  |-- RTS2 bridge
          |
TelescopeCapability + TelescopeState
```

### 传输适配器职责

`TransportAdapter` 只负责设备发现结果、配对、连接、断开、发送字节、接收字节、超时、取消和连接状态。它不负责目标选择、不计算赤经赤纬、不移动星图，也不决定“转向”按钮是否可用。

### 协议适配器职责

`TelescopeProtocol` 负责握手、目标坐标编码、命令顺序、ACK/错误码、位置解析和能力探测。它必须声明坐标历元、角度单位、南北符号、是否支持 Sync、是否支持 Abort Slew，以及是否支持连续位置回报。

### 领域服务职责

`TelescopeControlService` 负责：

- 把选中天体或屏幕中心转换为明确的 J2000/JNow 目标。
- 串行化 GoTo、Sync、Abort、读取位置和跟踪状态。
- 维护 `disconnected`、`pairing`、`connecting`、`ready`、`slewing`、`tracking`、`stopping`、`error` 状态。
- 把真实设备回传的位置送给星图覆盖层；不能用目标坐标伪造真实设备已经转到目标。
- 让脚本、CLI、ArkUI 和星图标记订阅同一份状态。

## 统一设备能力模型

后续设备配置应从现在的 LX200 配置扩展为传输与协议分离的结构，示意如下：

```json
{
  "slot": 1,
  "name": "NearLink GoTo Mount",
  "transport": "nearlink_ssap",
  "protocol": "vendor_lx200",
  "address": "11:22:33:AA:BB:FF",
  "serviceUuid": "vendor-defined",
  "commandPropertyUuid": "vendor-defined",
  "telemetryPropertyUuid": "vendor-defined",
  "equinox": "J2000",
  "capabilities": {
    "goto": false,
    "sync": false,
    "abortSlew": false,
    "positionRead": false,
    "tracking": false,
    "park": false,
    "home": false,
    "pulseGuide": false
  },
  "offline": true
}
```

`capabilities` 在真实设备握手或厂商配置导入后才能变为 `true`。服务 UUID、属性 UUID、配对要求和帧格式属于设备协议资料，不能使用示例值写入发布配置。

## CLI 预留契约

当前没有这些星闪命令的生产实现。P0 只应预留返回结构化 `planned`/`unsupported`，不得伪造发现或连接成功。建议命令如下：

| 命令 | 作用 | 默认行为 |
|---|---|---|
| `getNearLinkStatus` | 读取本机支持性、开关状态、API 能力和权限状态 | 只读，不扫描 |
| `listNearLinkDevices` | 列出用户已授权/已配对或本次主动发现的设备 | 不自动配对，不控制设备 |
| `pairNearLinkDevice` | 对指定地址发起配对 | 必须用户主动调用 |
| `connectNearLinkDevice` | 连接指定设备并读取服务摘要 | 必须用户主动调用，带超时 |
| `disconnectNearLinkDevice` | 断开指定设备 | 立即取消未完成命令 |
| `getNearLinkServices` | 返回服务 UUID、属性方向、MTU 和能力探测结果 | 不发送望远镜控制命令 |
| `saveNearLinkTelescopeProfile` | 保存设备地址、协议标识和用户确认的 UUID | 只写本地配置，不连接 |
| `telescopeGoto` | 使用统一望远镜服务转向选中天体或指定坐标 | 只有 `goto=true` 且连接状态为 `ready` 才执行 |

现有 `getTelescopeProfiles`、`testTelescopeConnection`、`getTelescopePosition`、`telescopeLx200GotoSelected` 等命令应继续兼容。星闪设备接入后，应增加 `transport`、`protocol`、`pairingState`、`connectionState`、`capabilities` 和 `lastError` 字段，而不是复制一套 NearLink 专用业务命令。

所有实际控制命令返回至少包含：

```json
{
  "ok": false,
  "status": "unsupported",
  "transport": "nearlink_ssap",
  "protocol": "unknown",
  "connectionAttempted": false,
  "errorCode": "missing_vendor_protocol",
  "message": "设备未提供已验证的望远镜服务协议"
}
```

## 分阶段实施

### P0：接口和测试桩

- 在 C++ 领域层定义传输、协议和能力模型，先接入离线模拟器，不引入 NearLinkKit 生产依赖。
- 为现有 LX200 TCP 桥补 `transport=tcp` 和能力字段，验证 UI/CLI 不依赖具体传输实现。
- 增加 NearLink 命令目录和 `planned` 状态，运行时不申请权限、不扫描、不发起配对。
- 建立协议适配器测试：分包、粘包、超时、取消、重复 ACK、错误帧、设备断开和命令队列拥塞。

### P1：设备发现、配对和服务读取

- 在独立 ArkTS `NearLinkDeviceManager` 中封装 `manager`、`remoteDevice` 和 SSAP 生命周期。
- 只显示设备名称、地址脱敏值、设备类别、配对状态、连接状态和能力摘要。
- 用户在望远镜页明确点击发现/配对/连接；页面关闭、退后台或断开时释放连接和事件订阅。
- 先做“服务读取和诊断”，不发送 GoTo，记录服务 UUID、属性读写方向、MTU 和错误码。

### P2：真实星闪望远镜协议

真实设备接入前必须从厂商取得并审计：

1. 星闪服务 UUID 和属性 UUID。
2. 设备角色、配对方式、加密要求和最大 MTU。
3. 命令帧、响应帧、ACK、错误码、心跳和断线重连规则。
4. RA/Dec 坐标格式、历元、角度精度、时间基准和南北符号。
5. GoTo、Sync、Abort、位置回读、跟踪、Park、Home 和脉冲导星的能力表。
6. 固件版本兼容范围、并发限制和数据发送间隔。

然后实现 `NearLinkVendorAdapter` 或 `NearLinkLx200Adapter`。只有协议确实是 LX200 的设备才使用后者，不能因为设备名称含有 GoTo 就套用 LX200。

### P3：协议覆盖和桥接

- 优先支持有真实样机和公开协议的 LX200 星闪适配器。
- NexStar、SynScan 单独实现帧编码和能力探测，不与 LX200 共享猜测逻辑。
- INDI、ASCOM/Alpaca、RTS2 先作为本机/局域网桥接目标评估；若由另一台鸿蒙设备提供桥接，再使用 `abilityConnectionManager` 同步控制会话，不把它们伪装成原生星闪协议。
- 串口路径单独评估 HarmonyOS 设备权限和 Qt SerialPort 可用性。

### P4：多设备和未来终端

- 平板作为主控制器，手机、电脑或另一台鸿蒙设备可作为只读星图或控制副屏。
- 共享时间、观测地点、选中天体、视角、望远镜位置和连接状态；控制权限采用单一主控租约，避免两个设备同时发 GoTo。
- 未来可扩展星闪成像设备、电子目镜、遥控器和环境传感器，但每种设备仍通过独立能力模型注册，不把插件开关和传输状态混在一起。

## 离线、隐私和权限边界

星闪是本地无线设备通信，不是公网天文数据请求，但它仍然是设备连接能力，必须在隐私说明和权限审计中单独列出。当前未备案版本继续保持应用不访问互联网：

- 不新增 Internet 权限，不访问公网，不通过星闪转发公网请求。
- 不自动扫描、自动配对、自动连接或后台保持望远镜连接。
- 不上传星闪地址、设备名、厂商数据、序列号、观测地点、选中目标或望远镜坐标。
- 日志默认脱敏星闪地址、服务 UUID 和厂商数据；诊断模式也不记录完整设备序列号。
- 目标 RA/Dec 和控制帧只发送到用户明确选择的本地设备，并在 CLI 结果中显示 `connectionAttempted`、目标设备和状态。
- 应用退后台、关闭面板、脚本结束或用户断开时，停止位置订阅和控制队列；长时间后台协同另按鸿蒙长时任务规则评估，不能默认常驻。

后续若备案后开放远程镜像或云端设备服务，必须另行登记 `docs/harmonyos/NETWORK-INVENTORY.md`，不能把星闪本地链路当作联网功能的替代隐瞒数据流向。

## 与现有方案的差异

| 方案 | 连接范围 | 控制协议 | 适合当前版本 |
|---|---|---|---|
| 离线模拟器 | 无设备连接 | 模拟 LX200 能力 | 立即用于 UI、CLI、脚本回归 |
| LX200 TCP | 本机/局域网 | LX200 | 当前鸿蒙真实设备路径 |
| 串口 LX200 | 本机物理端口 | LX200 | 桌面原版已有，鸿蒙待评估权限和依赖 |
| 星闪 SSAP | 本地无线 | 厂商定义或协议适配器 | 需要目标设备协议和真机验证 |
| INDI | 本机/局域网服务 | INDI 属性协议 | 适合桥接，不等于星闪原生控制 |
| ASCOM/Alpaca | Windows 本机或局域网 HTTP | ASCOM/Alpaca | 不作为鸿蒙直接依赖，未来评估桥接 |
| RTS2 | 本机/局域网服务 | RTS2 JSON | 未来单独评估，不与轻量桥混接 |

## 硬件验证清单

拿到真实星闪望远镜或控制盒后，按以下顺序验证：

1. Pad 的星闪支持性、开关状态和 `ACCESS_NEARLINK` 权限。
2. 用户主动发现、配对、断开和再次连接；记录错误码和超时。
3. 设备名称、类别、厂商数据和地址脱敏显示。
4. 服务发现、属性读写方向、通知、MTU 和 10 ms 以上发送节流。
5. 仅发送只读设备信息/位置探针，确认响应帧和断线行为。
6. 离线模拟器与真实设备在 `GoTo`、`Sync`、`Abort`、位置回读和状态机上的一致性。
7. 星图标记只跟随设备回传位置；设备未回传时显示未知，不把目标位置当成望远镜位置。
8. 脚本取消、应用退后台、关闭面板和设备断开时均能停止命令队列。
9. CLI 与 ArkUI 交替调用时不发生重复连接、重复发送或状态闪烁。
10. 用抓包或厂商诊断工具确认没有任何公网请求、用户位置外发或未授权数据上报。

当前 Pad 测试地址 `192.168.1.30:33805` 是无线调试端点，不是星闪设备，也不能证明星闪发现或望远镜协议可用。

## 风险与决策门

- 没有真实厂商协议时，最大风险不是 UI，而是把错误的帧格式发送给设备。没有协议资料就停在 P1 服务诊断。
- `@kit.NearLinkKit` 与 `@kit.ConnectivityKit` 的 API 版本存在差异；必须以项目实际 SDK 的 ArkTS 编译结果为准，不通过字符串或动态导入绕过版本检查。
- 设备类别、设备名称和 CDSM 集合都不能证明支持 GoTo；能力必须来自握手或经过审核的设备配置。
- 星闪连接状态、SSAP 服务状态和望远镜转向状态是三个不同状态，UI 不应共用一个“已连接”开关。
- NearLink 与局域网桥接都属于本地设备通信，但数据最小化、权限、日志脱敏和用户主动授权要求仍然适用。

### 本轮决策

1. 暂不将 `@kit.NearLinkKit` 加入生产代码和构建依赖。
2. 不修改签名、证书、Profile、联网权限、离线封口和现有望远镜 TCP 行为。
3. 下一次实现从 P0 领域接口和离线测试桩开始；拿到真实星闪设备协议后再做 P1/P2。
4. `PLUGIN-GAP-AUDIT-2026-08-31.md`、`NETWORK-INVENTORY.md` 和统一 CLI 文档必须与本报告保持链接和状态一致。

## 官方资料

- [manager（星闪开关能力）](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/nearlink-manager)
- [remoteDevice（对端设备的连接能力）](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/nearlink-remote-device)
- [SSAP（星闪服务交互协议）](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/nearlink-ssap)
- [CDSM（星闪合作设备集合）](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/nearlink-cdsm)
- [星闪常见问题与数据发送节流](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/nearlink-faq)
