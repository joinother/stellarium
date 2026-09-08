# 多波段天空与圆形对照窗口预研

日期：2026-09-08。状态：录屏分析、源码审计及公开服务小样查询完成；尚未实现或打包多波段功能。没有修改应用网络权限、签名或 Pad 安装包。

## 1. 结论与录屏观察

推荐“真实巡天影像 + 原生 HiPS 多级瓦片 + 同一星图内圆形遮罩”，不是把普通 RGB 天空重新染色，也不必引入 Celestia 或第二套星图引擎。

用户录屏 `ScreenRecording_09-08-2026 14-36-42_1.MP4` 时长约 8.25 秒：可见 X 射线标签、紫蓝色弥散背景及亮点；与可见光天空共用目标标签、星座线和地平线；约第 4–6 秒出现可见光背景上的圆形 X 射线对照区，再切回全屏。只能确认可见交互，不能从录屏判断其数据来源或内部着色器。

[Sky Guide 官方滤镜说明](https://support.fifthstarlabs.com/article/18-creating-filters)确认支持伽马、X 射线、紫外、可见光、Hα、红外、微波、射电，以及移动、缩放、全屏和关闭。可借鉴交互，不提取竞品影像或私有资源。本方案修订早期“先做模拟染色”的顺序：优先交付少量真实离线波段；缺数据的波段显示未安装/未覆盖，不用模拟填满列表。

## 2. B−V 与 SIMBAD 的作用

- B−V 是 B、V 两个通带的星等差，不是完整光谱。[ESA Hipparcos 字段说明](https://hipparcos-tools.cosmos.esa.int/pstex/sect2_01.pdf)列有该字段及来源、误差信息。
- 当前 `src/core/modules/Star.hpp` 已有 `getBV()` 与颜色索引；`StarWrapper.cpp` 已输出 B−V，部分明亮恒星还有 `spectral-class`。先用本地资源，不逐星联网。
- 光谱型可辅助分类、温度及光球能量分布估算；模型需声明消光、金属丰度、表面重力和归一化假设。不能仅凭 B−V 唯一反演所有波段亮度，更不能还原星云空间结构。
- X 射线涉及日冕、高温等离子体、吸积等过程，不能由可见光温度直接推出真实 X 射线天空。参见 NASA [恒星高能辐射](https://heasarc.gsfc.nasa.gov/docs/heasarc/science/stars.html)与[光学/X 射线对比](https://heasarc.gsfc.nasa.gov/docs/objects/stars/starstext.html)。
- [SIMBAD](https://simbad.cds.unistra.fr/Pages/guide/ch15.htx)提供对象标识、文献光谱型、测光等；`sp_type` 是分类字符串，不是光谱曲线、巡天图或每颗星全部波段测量。
- 开发机实际通过 [SIMBAD TAP](https://simbad.cds.unistra.fr/simbad/sim-tap/) 查询 `HIP 91262`，返回 `* alf Lyr`、`A0V`、光谱型参考 `2024A&A...690A.176N`。这是织女星的小样，不代表全目录覆盖或生产服务保障。

本轮成功的小样 ADQL：

```sql
SELECT TOP 1 b.main_id, b.sp_type, b.sp_bibcode
FROM basic AS b JOIN ident AS i ON b.oid = i.oidref
WHERE i.id = 'HIP 91262'
```

后续采用 HIP/HD/Gaia 等稳定 ID 交叉匹配，不能拿翻译名称匹配。坐标匹配处理历元、自行、误差与歧义；保存质量、出处、检索日期，未知不填零。批量补齐用遵守服务限制的构建任务，不随视野拖动逐星请求。

## 3. 真实数据选择

[CDS HiPS 注册列表](https://aladin.cds.unistra.fr/hips/list)与 [NASA SkyView](https://skyview.gsfc.nasa.gov/current/cgi/titlepage.pl)用于发现数据，不代表它们授予所有上游产品的再分发权。

| 波段 | 候选 | 注意点 |
| --- | --- | --- |
| X 射线 | ROSAT/RASS；后续局部 Chandra、XMM 或 eROSITA 产品 | 先 RASS；不同产品能段、曝光和分辨率不同 |
| 紫外 | GALEX NUV、FUV | 非完整全天；两个通带分开，无覆盖不等于无辐射 |
| 近红外 | 2MASS J/H/K 或彩色合成 | 第一批候选，合成图注明通带与颜色映射 |
| 中红外 | WISE/AllWISE 指定通带 | 与 2MASS 分开；[IRSA 资料](https://irsa.ipac.caltech.edu/onlinehelp/catalogs/help.pdf)列有多种 HiPS 图层 |
| Hα | SHASSA 或审核后的多巡天合成 | 窄带谱线；SHASSA 非全天，保留覆盖信息 |
| 微波 | Planck 指定频率或单独的 CMB 产品 | CMB 分离产品不等于单频原始天空 |
| 射电 | Haslam 408 MHz、HI4PI 等指定产品 | 连续谱与氢谱线/速度积分图分开 |
| 伽马 | Fermi 指定能段 | 累计曝光图，不称实时天空 |

### 本轮实际读取的 properties

开发机读取 CDS hipslist，然后访问其中指向的三个 properties，均成功；没有下载整套瓦片。

| 产品 | 波段/覆盖 | 瓦片参数 | 来源 |
| --- | --- | --- | --- |
| RASS | X-ray，覆盖比例 1；波长约 0.517–12.398 nm | equatorial，order 0–4，512px，jpeg/fits | [properties](https://alasky.cds.unistra.fr/RASS/properties)，MPE/CDS |
| GALEXGR6_7 NUV | 177.1–283.1 nm，覆盖比例 0.788 | equatorial，order 0–9，512px，png/fits | [properties](https://alasky.cds.unistra.fr/GALEX/GALEXGR6_7_NUV/properties)，STScI/NASA |
| 2MASS Color | J/H/K 合成，覆盖比例 1 | equatorial，order 0–9，512px，jpeg | [properties](https://alasky.cds.unistra.fr/2MASS/Color/properties)，UMass/IPAC/Caltech |

比例来自 `moc_sky_fraction`，不表示所有像素同等曝光/质量。三个产品标有 `public master clonableOnce`，这是服务状态，不能单独作为商业再分发许可结论。发布前逐份核对署名、许可、引用与派生处理规则。网页读取工具未打开上述纯文本链接，但开发机 HTTP 请求取得了字段，需区分记录。

## 4. 现有源码与缺口

| 位置 | 已有能力 | 待补 |
| --- | --- | --- |
| `src/core/modules/HipsMgr.cpp` | 巡天列表、图层显示与偏好 | 离线包注册、禁用远程默认来源、波段目录 |
| `src/core/StelHips.cpp/.hpp` | 球面多级瓦片、坐标系、父瓦片回退、异步纹理、file URL、颜色/透明度设置 | 波段会话、覆盖/错误状态、圆形遮罩、共享缓存预算 |
| `Star.hpp`、`StarWrapper.cpp` | B−V、部分光谱型 | 补齐质量/出处及离线匹配，不代替巡天背景 |
| `StelMainView.cpp` | `actionShow_Hips_Surveys` 总开关 | 完整波段 CLI 尚不存在，需注册并回传实际显示状态 |

`getExt()` 当前选 jpeg/png/webp/tiff/bmp，不能据此宣称支持科学 FITS 强度图。首版用预处理展示瓦片；需要定量测光/任意拉伸时另建科学像素与单位管线，不能把压缩 JPEG 像素当原始通量。

风险：HipsSurvey 构造即请求 properties；HipsMgr 无配置时有外部默认列表地址。需要拦截所有派生请求，不只是改 UI 名字。现有每套巡天缓存按 `1000×512×512` 像素计，按 RGBA8 换算约 1000 MiB/套，不含其它副本；这是上限估算，不是实测占用，多波段必须改为共享预算。

[HiPS 标准](https://www.ivoa.net/documents/HiPS/)是渐进式球面瓦片，和 HIP 恒星目录不同。可参考 [Aladin Lite](https://github.com/cds-astro/aladin-lite) 的多巡天/覆盖/FITS 支持，其 README 标明 LGPL-3.0-or-later，具体引入仍须核对组件许可。当前优先复用 C++ 核心，Aladin 用作独立验图工具，不叠第二套 WebView 星图。[Hipsgen](https://aladin.cds.unistra.fr/hips/HipsgenReferenceManual.html)是开发机数据制作候选，先核验转换和许可再纳入流水线。

## 5. 渲染与交互（设计，未实现）

`SpectralDatasetRegistry → OfflineSurveyProvider → HipsSurvey → SpectralFilterSession → 原有星图渲染`

- 原生处理方向、瓦片、GPU 遮罩；ArkTS 处理按钮、来源说明、状态及手势意图。共用时间、位置、投影、选中对象与帧循环。
- 入口“图层 → 多波段”，离散波段按钮与全屏/圆窗切换。首版一个圆窗，拖主体移动、拖边缘缩放、窗外拖星图，提供明确关闭按钮，不强迫记忆旋转/甩出手势。
- 圆形按实际像素长宽比计算，换算 vp/px、安全区与旋转；遮罩和星图同帧更新，不能横屏变椭圆或跟随延迟。
- 相同相机矩阵下窗口内替换背景，或清楚标识混合模式；不默认把全部可见光恒星叠成 X 射线亮点。标签/选中圈独立显示并注明导航用途，避免双星点与虚假源。
- 低级底图就绪再过渡，180–240ms 可作待测起点；快速切换取消旧任务。不重建 XComponent、不刷新整个菜单。
- 科学波段不用可见光大气消光再次染色；地面遮挡可保留作方位参照，退出恢复偏好。说明是太空观测资料可视化，不是手机传感器探测或人眼看到的天空。
- 巡天有固定观测时期。改模拟时间只改变投影，不生成其它年代真实影像；行星/月球的多波段时序数据另做产品。

华为 MCP 查询 `XComponent OpenGL ES 纹理 渲染 性能 NativeWindow`，读取全文 `document/cn/harmonyos-guides/napi-xcomponent-guidelines`：[自定义渲染 XComponent](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/napi-xcomponent-guidelines)。官方确认 XComponent 承载自绘制 Surface，不内置天文滤镜。继续已有接入，不因新示例迁移窗口生命周期，本轮未引入版本专属 API。

## 6. 离线、性能与国内分发

- 第一批 RASS、GALEX NUV、一种红外产品；审核后内置低级底图，高清为独立扩展包。先固定天区验证坐标再定全包级别；保留 GALEX 观测空洞。
- 512px RGBA8 单瓦片约 1 MiB；全球某级瓦片数 `12×4^order`，升一级约增四倍。不能把全分辨率所有波段都塞 HAP；压缩包体积由实际清单统计，不虚报固定 MB。
- 全局 GPU/解码缓存预算，64–128 MiB 可作待测起点，不降低屏幕分辨率。仅加载可见天区及少量邻域，圆窗只取相交瓦片；父级回退、后台解码、分帧上传。启动不解码所有波段，下一波段最多预热底图。
- 明确 `ready/preparing/notInstalled/outsideCoverage/tileMissing/decodeFailed/unsupportedFormat/offlineBlocked`。反馈请求与实际显示级别、缺块数，不用永久转圈掩盖未覆盖。
- 离线包包含版本、SHA256、大小、坐标系、通带/单位、观测时期、色标映射、署名/许可与 MOC。防路径穿越、解压炸弹、超大图及 properties 外链；沙箱读取，校验后原子激活，失败保留旧包。
- 国内分发复用既有架构：境内服务管理清单、对象存储承载静态包/瓦片、CDN 按需加速。轻量服务器不逐次重投影 FITS、不随拖动代理 SIMBAD。
- CDS 注册列表已列 `hips.china-vo.org`，比旧报告仅历史论文的证据多一项注册记录；本轮未验本站瓦片、性能和许可，不能宣称完整国产替代。后续逐产品核验或合作做授权镜像。
- 备案、隐私、来源授权、联网开关分开验收。本轮仅开发机公开查询，应用不新增请求，也不发送用户位置、设备信息或文件。

## 7. CLI 契约草案与实施顺序

以下尚未注册到命令目录，不能当作已支持功能：

| 草案命令 | 作用 |
| --- | --- |
| `listSpectralDatasets` | 波段、覆盖、版本、来源及安装状态 |
| `setSpectralView` | datasetId、全屏/圆窗、透明度，幂等切换 |
| `setSpectralLens` | 归一化中心/半径与启用状态，GPU 校正实际像素 |
| `getSpectralState` | 请求与显示波段、错误、级别、缓存/覆盖统计 |
| `importSpectralPackage` | 本地导入、校验、原子激活 |
| `closeSpectralView` | 取消任务并恢复场景，支持脚本/导览快照 |

1. P0：产品许可、离线读取与覆盖验证；银心/M31/猎户座对照官方查看器，检查坐标方向及色标。
2. P1：真实离线全屏三波段、状态、缓存、CLI；测切换/拖动/缩放/重复进入/多插件下帧耗时与峰值内存。
3. P2：圆窗、渐变与手势；手机/Pad 横竖屏、挖孔、关闭按钮、窗内外手势与投影回归。
4. P3：其余波段、目录交叉匹配、用户离线包及镜像，新增产品复用同一清单、状态及 CLI。

验收包括飞行模式冷启动、缺块/损坏包、快速切换、UI/CLI 一致、跨波段坐标一致、空洞提示、退出恢复、GPU 内存回收和无意外网络请求。当前仅预研，不宣称这些验收已完成。
