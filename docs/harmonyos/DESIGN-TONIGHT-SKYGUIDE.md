# 设计文档：今夜星图（Tonight's Sky）与 Sky Guide 远景规划

> **参考范式**：Sky Guide（Fifth Star Labs）的 *Tonight / Calendar / Time Travel* 体验；TRAE 协助梳理的"远景规划"方向。
> **日期**：2026-07-24
> **基线**：已完成 14 个 ArkUI 面板 + 172+ C++ 桥接命令（含 `getRTS`、`getAlmanac`、`getSatellites`、流星雨、Bortle 光污染、夜间模式）。
> **结论先行**：你缺的"今夜升起的星体 / 今天的视图"，**底层数据 Stellarium 全都有**，目前只是没有把数据聚合成一个"今晚该看什么"的向导面板。

---

## 1. 北极星：Sky Guide 范式

Sky Guide 的核心体验不是"一个星图软件"，而是**"今晚该看什么"的向导**。其标志性能力：

- **Tonight（今夜）**：把"今天在你头顶可见的行星、最佳观测窗口、卫星过境、光污染/天气"汇总到一屏。
- **Calendar（日历）**：按地点过滤的天文事件（日月食、行星合、流星雨、卫星过境）。
- **Time Travel（时间旅行）**：跳到未来编排月相照片、回溯历史彗星。
- **Satellite / ISS passes**：精确时机的过境提醒。
- **Light pollution map + weather**：在家/观测点查条件。
- **Night Vision（红光夜视）**、**Featured 天文科普**、**Aurora 极光**、**AR 模式**、**Siri 捷径**。

我们移植的是 Stellarium——数据/计算引擎远比 Sky Guide 强。所以"今夜视图"几乎不需要新计算，**纯粹是 UI 聚合**。

---

## 2. 现状盘点：底层数据已齐，只缺"向导面板"

| 需要的数据 | 已有桥命令 | 现状 |
|---|---|---|
| 观测地 / 日期 | `getObserverInfo`、`getState` | ✅ |
| 升起 / 中天 / 落下 | `getRTS(objName)` → 本地时 | ✅ |
| 日月历（升落 / 暮光 / 月相） | `getAlmanac` | ✅ |
| 行星 / 天体位置 | `getObjectPositions`、`getObjectInfo` | ✅ |
| 卫星（含 ISS） | `getSatellites`（已有面板）+ TLE | ✅ |
| 流星雨 | 已有流星雨面板 | ✅ |
| 光污染 / 暗夜 | `setLightPollution` / `setBortleScale` | ✅ |
| 夜间模式 | `actionShow_Night_Mode` | ✅ |
| 时间跳变 | `setDate` / `setJD` / `advanceTime` / `setTimeRate` | ✅ |

→ **"今夜星图"不需要新 C++ 计算，几乎全靠现有命令聚合**。这是当前性价比最高的新功能（对应新 GAP 项 **#46**）。

---

## 3. 核心新增：「今夜星图」面板（#46, P0）

### 3.1 rail 入口
在 `actions` 数组**最顶端**新增：
```ts
{ label: '今夜', icon: 'tonight', panel: 'tonight' }
```
并在 `getIcon` map 增加 `'tonight': $r('app.media.ic_tonight')`。

### 3.2 分区布局（自上而下）
- **A. 概览条**：日期 + 观测地（"北京 · 周五 7/24"）+ 一句话结论（"🌖 月相 78% · 最佳窗口 21:10–23:40 · 今夜可见 4 颗行星"）。
- **B. 行星今夜**（横向卡片）：每颗显示图标、名称、升起 / 中天 / 落下、最大高度、是否整夜可见；点卡片 → `moveToSelected` + 指向。
- **C. 亮星与星座**（可折叠）：今夜上中天附近最亮恒星 Top5 + 当季推荐星座。
- **D. 深空精选**：月相暗、无月时推荐可观测 Messier（标注方位 / 大致高度）。
- **E. 卫星过境**：今夜 ISS / 明亮卫星 Top3（起止时间、最大亮度、方位变化），源自 `getSatellites`。
- **F. 观星窗口**：时间轴（暮光结束 → 月出 → 月落），绿色高亮"最佳观测段"；显示 Bortle 等级 + "天气"占位（后续接 API）。

### 3.3 交互
- 打开即自动计算（`callNativeWhenReady` 聚合 `getAlmanac` + 多目标 `getRTS` + `getSatellites`）。
- 每个行星 / 目标可"一键指向"（`moveToSelected` + `setTracking`）。
- 面板内嵌"时间旅行"小 slider：预览"今夜 22:00 的天空"（`advanceTime` 临时步进），松手复位。
- 与夜间模式联动（红光）。

### 3.4 数据聚合伪代码（ArkTS）
```ts
loadTonight() {
  const obs  = callNative('getObserverInfo')        // 地点 / 日期
  const alm  = callNative('getAlmanac')             // 日月 / 暮光 / 月相
  const planets = ['Mercury','Venus','Mars','Jupiter','Saturn','Moon']
  const rts  = planets.map(p => callNative('getRTS', p))   // 升起/中天/落下
  const sats = callNative('getSatellites')          // 今夜过境
  // 过滤：transitAlt > 0 且落在 暮光结束 ~ 月出 窗口
  this.tonight = buildAgenda(alm, rts, sats)
}
```

### 3.5 为什么是 P0
纯 UI 聚合，无需新 C++ 计算；复用已验证的桥命令；模拟器可端到端验证。1–2 天可完成。

---

## 4. Sky Guide 远景功能 → 落地映射

| Sky Guide 功能 | 我们现状 | 落地方案 | 优先级 |
|---|---|---|---|
| **Tonight 今夜** | 无（缺面板） | 新增 tonight 面板（本章） | **P0（性价比最高）** |
| **Calendar 天象日历** | 无聚合 UI | 新增「天象日历」面板：日月食 / 行星合 / 流星雨（复用 meteors + almanac） | P1（#47） |
| **Satellite / ISS passes** | 有卫星面板 | 加"今夜过境"列表 + 可选通知 | P1 |
| **Time Travel** | 引擎有（`setJD`），无 UI | tonight / calendar 内嵌时间 slider | P2（#48） |
| **Light pollution map** | 有 Bortle 数值 | 加地图 / 站点选择 UI | P2 |
| **Weather 观星天气** | 无 | 接天气 API（需联网权限） | P3 |
| **Night Vision** | 已有 | 与 tonight 联动 | 已有 |
| **Featured 天文科普** | 无 | 新增「发现」内容面板（静态 + 可扩展） | P2（#49） |
| **Aurora 极光** | 无 | 接地磁 Kp API | P3 |
| **AR 模式** | 受限 | 鸿蒙暂无摄像头星空叠加，暂缓 | 受限 |
| **语音捷径（Siri→小艺）** | Speech 部分 | 把"今夜最佳""指向火星"做成语音意图 | P3 |

---

## 5. Phase 4 路线图（按性价比排序）

1. **今夜星图面板（#46）** — P0，纯 UI 聚合，1–2 天，模拟器可验。
2. **天象日历面板（#47）** — P1，复用 `almanac` + `meteors`。
3. **卫星今夜过境**（并入卫星面板） — P1。
4. **时间旅行 slider（#48）** — P2。
5. **发现 / 科普内容面板（#49）** — P2。
6. **轨迹回放（#42）** — P2 高工作量（星历步进）。
7. 天气 / 极光 / AR — P3（依赖外部 API / 硬件）。

---

## 6. 给 #42 轨迹回放的铺垫

轨迹回放需要：① 星历源（行星 / 卫星位置随时间变化）；② 时间步进驱动（已有 `advanceTime`）；③ "时间轴"录制（已有脚本录制框架可借鉴）。建议先做"行星轨迹预览"——按 `getObjectPositions` 在历史 / 未来区间采样多点连成线，比全功能回放简单得多，可作为 #42 的第一步。
