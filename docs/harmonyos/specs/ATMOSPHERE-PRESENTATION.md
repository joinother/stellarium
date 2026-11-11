# 大气表现与白天恒星

入口：图层 → 天空 → 大气层和地面。颜色模式不改变相机、投影、天体位置或观测地点。

## 用户控制

- **无**：关闭大气、照片地景、动态雾山、地景雾和活动三维场景。
- **仅地面**：保留当前地面类型，关闭大气。
- **大气层和地面**：保留当前地面类型，打开大气。由“无”返回时恢复照片地景/雾山偏好，不自动重启三维场景或地景雾。
- 单独关闭地面而保留大气时，下拉框显示“仅大气层 · 自定义”，不擅自重开地面。
- **绚丽模式**：默认关闭。依据太阳高度和方位，在现有大气渲染中增强蓝天、向日暖橙和背日紫色暮光。关闭返回原渲染；不叠加整屏滤镜，不改变物理亮度计算。地球的 Lightweight 和 Preetham 模型支持此效果，非地球、夜视沿用原效果；日食期间减弱增强。
- **现实星等**：默认开启，明亮天空抑制暗星。关闭时仅为恒星使用独立的视觉适应上限，同时同步星表 LOD 与拾取可见性；不改变行星和背景亮度，不取消用户星等限制或大气消光。

参考图中的圆形天空来自投影与视角；颜色开关不强制切换全穹顶视角。当前没有加入极光渲染或极光假开关。

## 雾山下方的天空

地球启用动态雾山、未启用照片地景或 Scenery3d 时，Lightweight/Preetham 的最终大气 RGB 在世界高度角 −3° 至 −15° 平滑减弱，−15° 以下不再镜像蓝天。淡出跟随雾山模式开关，不跟随镜头俯仰，也不依赖绚丽模式；抬头后的上半球保持原结果。近坡波纹的空隙可以露出背景，宽视场的实心地面仍由地形遮挡。

这是显示层调整，不改大气平均亮度、曝光适应、消光或天体计算。两个大气模型使用加法混合，所以衰减最终 RGB，而非仅修改 alpha。Preetham 每片元反投影取得带符号的世界高度，不能使用其亮度网格已镜像的方向。回归见 `scripts/test-ohos-mist-atmosphere.mjs`。

## CLI

沿用 `setSkyDisplaySetting`，payload：

| 参数 | 含义 |
| --- | --- |
| `environmentMode\|0` / `1` / `2` | 无 / 仅地面 / 大气层和地面 |
| `vividAtmosphere\|1` / `0` | 绚丽大气开关 |
| `realisticStarVisibility\|1` / `0` | 现实恒星可见性开关 |

`getState` 返回 `environmentMode`（0–3，3 为仅大气）、`vividAtmosphere`、`realisticStarVisibility` 及恒星专用 `starLimitingMagnitude`。布尔参数接受 `0`、`1`、`true`、`false`；非法模式不修改状态。

两个新开关分别持久化到 `landscape/flag_vivid_atmosphere` 与 `viewing/flag_realistic_star_visibility`。没有新增网络请求、权限或远程素材。

## 验证边界

`scripts/test-ohos-vivid-atmosphere.mjs` 执行实际 shader 的颜色函数，覆盖关闭等价、色域/亮度、太阳高度连续性和食相边界；`scripts/test-ohos-realistic-star-visibility.mjs` 验证星等与 LOD 行为。它们不替代 GPU 编译和真机截图检查。

关闭现实星等时，`StelObjectMgr` 的最终点击候选过滤仅对 `Star` 使用恒星专用门限，同时遵守用户的星等限制，避免“看得见却点不中”。其他类型和现实模式保留原门限。设备记录见 [大气与雾山验证](../testing/ATMOSPHERE-MIST-PAD-2026-11-12.md)。
