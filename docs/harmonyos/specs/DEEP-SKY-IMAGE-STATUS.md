# 深空图片诊断状态

`getDeepSkyImageStatus` 是只读诊断，不开启图片、不触发下载或纹理加载。空参数检查重点图片；`all|偏移|数量` 继续分页列出磁盘 PNG（单页 1–64 项）。响应仍为原有 JSON object，文件清单、分页及 targets 字段不变。

## 显示门禁

- `renderEnabled`：`StelSkyLayerMgr::getFlagShow()`，即 `actionShow_DSO_Textures` 总开关；管理器不存在时为 false。
- `layerVisible`：保留旧语义，至少一个图片图层自身的 show 标志开启；不包含总开关，不保证当前视野有图片。
- `effectiveLayerVisible`：`renderEnabled && layerVisible`。只表示显示开关允许绘制，不保证通过视野、分辨率、亮度或消光门限。
- `activeTexture*Count`：只统计总开关开启且自身 show 开启的图片图层，沿用最近绘制帧的 viewport candidate。关闭的图层不计入残留候选；该接口不会推进绘制帧。

## activeTextureStatus

按下列优先级返回：

| 状态 | 条件 |
| --- | --- |
| `disabled` | 总开关关闭，或没有自身 show 开启的图片图层；active 计数为零 |
| `error` / `partial-error` | 有活动错误纹理；同时有 ready 纹理时为 partial-error |
| `loading` | 有活动 loading 或 notStarted 纹理 |
| `idle` | 显示门禁开启，但最近一帧没有活动图片候选 |
| `ready` | 至少一张活动纹理 ready，且没有活动 pending/error |

旧状态名称保留，新增 `disabled` / `idle`，不能再以“零 pending/error”推断 ready。现有 SkyTextureStatusController 根据 pending/error 数量显示横幅；新状态的计数为零，因此隐藏横幅并停止轮询，无需变更 UI。

`targets[].state` 保留 `noMatch/decodeFailed/ready/loading/notStarted`，反映磁盘及活动纹理状态，不新增 per-target 枚举。关闭总开关时，磁盘存在的图片通常是 notStarted；不表示 GPU 缓存已被卸载。`all` 是磁盘分页，并非强制加载全部图片。ready 不保证最终可见，图片仍可能受大气、消光或地面遮挡。

## 回归与边界

运行 `node --test scripts/test-ohos-deep-sky-status.mjs scripts/test-texture-frame-budget.mjs`。诊断测试从实际 C++ handler 提取状态收集和输出表达式，转换容器语法后用模拟图层执行，覆盖总开关关闭/陈旧候选、隐藏图层、空候选、ready 去重、loading、error、缺失管理器及原 CLI 字段契约；不替代 native 编译或真机验收。

本次只修改 MainView 的诊断分支；渲染、资源加载、真实星等和总开关持久化行为不变。设备开启开关后的对照、native 构建由父任务执行。

2026-11-12 本地验证：上述命令 14/14 通过（诊断 10 项、纹理帧预算 4 项）。未构建、安装或操作设备。
