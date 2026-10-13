# 华为地图接入边界与实施记录

## 结论

华为 Map Kit 适合“位置选择”这个当前地图场景：用户可以在底图上缩放、移动并点选一个观测地点，应用再把结果作为本地观测位置使用。它不应直接替换天空文化的研究地图。文化地图表达的是历史资料和文化分布叠加，仍使用本地 `worldmap.jpg` 与文化轮廓；现代地图底图只能作为将来明确标注的参考层，不能改变文化资料的范围、年代或语义。

## 当前实现

- 位置页默认显示随包离线地图；用户主动点击“华为地图”后才创建 `@kit.MapKit` `MapComponent`。
- 点击地图会通过 Map Kit 的坐标纠偏得到 WGS84，回写 Stellarium 的观测位置；不向应用服务器发送请求。
- 地图初始化、地图点击和坐标转换都有超时/失败状态；失败可以回到离线地图。
- 未使用逆地理编码、搜索建议、路径规划、用户位置持续跟踪或瓦片叠加；这些功能留到单独评审，避免扩大外发字段。
- Map Kit 开启前必须先获得当前隐私同意；撤回同意或应用进入后台时不创建在线地图组件。
- CLI 支持 `openUiPanel place`，并兼容 `openUiPanel location`；`getLocationMapState` 可查询当前在线地图的 `provider/phase/error`，用于自动化确认“准备中、可用、失败或已回退”，不把“已请求华为地图”误报为“地图已加载”。

## 接入前条件

1. 在 AGC 的“地图服务”中开通 Map Kit，并让 DevEco 重新生成包含地图能力的 Profile；不在源码中写入证书、API Key 或签名材料。
2. 发布前确认 `ohos.permission.INTERNET`、地图服务能力和隐私政策版本一致，并在真机上验证未同意、拒绝网络、断网、超时和回退路径。
3. 华为官方文档说明中国大陆地图使用 GCJ02、海外和中国台湾使用 WGS84；系统定位通常是 WGS84，因此不能把定位值不经纠偏直接画到大陆地图上。
4. 地图显示的现代地名和文化研究叠加分别维护，不能用在线地图的行政边界替换原始文化资料。

## 官方资料

- [Map Kit 配置地图服务](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/map-config-agc)
- [Map Kit 模块说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/map-module-desc)
- [坐标纠偏](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/map-convert-coordinate)
- [Map Kit 个人隐私](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/map-personal-privacy)

## 暂不接入

文化地图在线瓦片、逆地理编码、在线地点搜索、路线规划和持续定位均未接入。它们分别会扩大网络请求、位置/查询词外发和文化资料语义风险，需在新的数据来源、授权、隐私告知与本地回退方案确定后再做。

## 2026-09-30 真机检查

- 在 HUAWEI MateBook Pro（HAD-W32）联网构建上通过 CLI 打开位置页并请求华为地图；界面明确显示“华为地图暂不可用，请使用离线地图”，同时保留离线世界地图和回退按钮。
- 这次结果说明当前包的 Map Kit 服务/Profile 或设备侧地图能力尚未满足在线地图初始化条件，不能把联网构建等同于地图服务已开通。下一步应在 AGC 开通 Map Kit、重新生成匹配的 Profile 后再复测；不修改签名文件、不把文化地图替换成在线行政地图。
