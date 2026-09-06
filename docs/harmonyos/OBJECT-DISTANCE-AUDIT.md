# 天体距离与缺失资料审计（2026-09-06）

## 实际发现

距离不是所有类共用同一个单位的 `distance` 字段。旧摘要只读该字段并按 AU 转换，恒星 `distance-ly` 被漏用，深空目录没有把已有距离导出到 getInfoMap。旧版 Pad 实测 SN 1987A 显示 `160.0000 AU`，脉冲星 PSR J0437-4715 显示 `0.1390 AU`，系外行星系统 Helvetios 显示 `15.4614 AU`；这三项分别应解释为千光年、千秒差距、秒差距，不能沿用 AU。

## 统一读取规则

| 对象 | 现有源字段/单位 | 处理 |
| --- | --- | --- |
| 行星、天然卫星、太阳系小天体 | Planet distance / AU | 观测者距离，保留星历计算 |
| 人造卫星 | range / km，orbit-valid | 保留观测斜距，不拿轨道高度代替 |
| 恒星、变星、双星 | distance-ly / ly，parallax / arcsec | 摘要接入光年；保留误差、估算来源 |
| 星系、星团、星云等 Nebula | oDistance / kpc、oDistanceErr | 通过 getInfoMap 导出单位和误差；大距离用 M ly/G ly |
| 系外行星系统 | distance / pc | 展示宿主系统的目录距离，不混同系内轨道半长轴 |
| 脉冲星 | distance / kpc，adistance / kpc | 优先原有电子密度模型结果，缺失时采用目录另一估计，明确 estimated |
| 新星、超新星 | distance / 千光年 | 转换为光年 |
| 类星体 | 通常只有 redshift | 保留红移资料；无直接距离时显示 redshift_only，不擅自指定宇宙学模型 |
| 未来插件 | distance + distance-unit，或 distance-ly | 有明确单位才换算；无单位返回 unsupported_unit |
| 星座、辐射点等无单一天体距离对象 | 无可靠距离字段 | 不根据投影向量长度伪造距离；当前通用提示为目录无可靠数据 |

共同实现 `src/OhosObjectDistance.hpp`。摘要、`getDistanceInfo`、`getObjectInfo` 和中文朗读命令复用同一套读取逻辑，不再把所有对象强制转成 Planet；不会出现屏幕距离已修正而朗读仍说成 AU 的情况。

## 误差和其他资料

- 部分脉冲星只有目录编号，原生专名和译名都为空，ArkUI 因空名称隐藏整张卡片。选中对象响应现在仅在名称缺失时回退原始 getID 编号，不擅自编造或翻译名字；已有专名保留。
- 恒星视差逆算遵循现有桌面文字的阈值：视差、误差均为正，信噪比大于 5；无误差、负视差、低信噪比不输出貌似准确的距离。
- 原恒星 getInfoMap 的绝对星等比桌面公式少了常数 5，已与 `m + 5(1 + log10(parallax_arcsec))` 对齐。
- 旧 `getObjectInfo` CLI 直接将笛卡尔方向向量分量当角度，已使用原生 getInfoMap 的赤经、赤纬、高度、方位角，与主详情统一。
- 恒星结构化视差值实际是角秒，却标成 mas，已乘 1000。原脉冲星视差是 mas，不重复转换。
- 深空对象有可靠目录距离时优先采用目录；仅有视差时使用同样的可信度限制，不取负视差的绝对值反算。
- 类星体 getInfoMap 默认 redshift=0 代表目录缺失，结构化资料不再将这个缺省值显示成测量结果。
- 摘要用简短的值和单位，误差仍保留在完整资料距离与机器字段中，避免将 `±` 塞进窄摘要格造成截断。

## CLI、状态与兼容

选中对象响应保持 `distance` 为展示字符串，另有 `distanceCompact`、`distanceValue`、`distanceUnit`、`distanceLightYears`、可选 `distanceErrorLightYears`、`distanceStatus`、`distanceMethod`。

`getDistanceInfo` 保留 distance 的数值形式，但必须同时读取 distanceUnit；格式化字符串为 distanceText。无可靠距离不返回伪造的 0。status 有 computed、catalog、estimated、unavailable、low_confidence、redshift_only、invalid_orbit、unsupported_unit。

`setObjectDetailTab 0/1/2/3` 对应观测、坐标、资料、操作；只操作现有详情状态机，不改变星图视角。响应 accepted 是入队确认，实际展示用详情值/布局检查。

插件关闭显示时，部分上游 searchByName 会拒绝命中；审计使用已有 `searchObject 'catalog|Quasars|MS 23574-3520|selectOnly'` 等精确目录路径，不为查资料而强制打开图层。不把搜索未命中后仍保留的旧选择当作该目标。

信息级别与自定义距离开关继续生效。坐标/资料页区分缺失原因；当前新增说明有英语、简体和繁体中文，其他 UI 语言依现有 I18n 规则回退英语，不宣称已完成所有语言的人工校对。

## 验证范围

适配器通过主机 QtCore C++ 断言测试，43 项 UI/既有回归通过。最终 Native、CompileArkTS、assembleHap 和资源审计通过（保留既有 4 项警告），已安装到 MatePad Mini；15 个代表目标的 148 项 CLI/实际布局检查通过，见 `object-distance-pad-test-2026-09-06.json`。天狼星、M31、类星体截图已人工检查。真机测试按星表类型抽样，不声称逐一测量了几百万颗恒星。离线包没有距离的对象不会凭空增加数据，也不发起网络查询。

后续宇宙学距离功能必须明确参数和定义（光度距离、共动距离、回望时间不能混用），记录算法版本与来源；不将红移简单乘常数称作真实距离。
