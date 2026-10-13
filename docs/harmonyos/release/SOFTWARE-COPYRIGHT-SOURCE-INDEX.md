# 软著源程序候选索引

核对日期：2026-09-08。用于准备和追溯，不是正式交存清单或原创代码认定。

## 已检查的候选文件

以下行数按本地工作树 `wc -l` 统计，包含空行和注释；不是申报源程序量。文件有无版权头不决定其是否原创，均须继续核对来源。

| 文件（仓库相对路径） | 物理行数 | 用途 |
| --- | ---: | --- |
| harmonyos/ets-source/pages/MainWindowNativeNode.ets | 32707 | 统一面板、目标详情、输入与命令交互；混合大文件，不能整文件直接认定原创 |
| harmonyos/ets-source/pages/AstronomyGuide.ts | 197 | 声明式导览及播放器 |
| harmonyos/ets-source/pages/DetailModelGeometry.ets | 28 | 独立模型旋转 |
| harmonyos/ets-source/pages/DetailModelRasterizer.ets | 177 | 详情图像栅格化 |
| harmonyos/ets-source/pages/DetailModelRenderClient.ets | 106 | 后台任务协调 |
| harmonyos/ets-source/pages/StartupStarGeometry.ts | 91 | 启动粒子几何与过渡 |
| harmonyos/ets-source/common/PrivacyStartup.ets | 18 | 初始化条件 |
| harmonyos/ets-source/qability/PrivacyConsent.ets | 81 | 隐私同意读取与状态 |
| harmonyos/cpp-source/PresentationGeometry.h | 36 | 呈现几何辅助 |

候选文件物理行数合计 33441。这个合计既不代表完整软件规模，也不代表申请人原创量；不能直接抄进申请表。

## 内容指纹

```text
94e25d2ec56519830737f342d92e7a451ae4103b14725b34b344dbd10d3e1b48  harmonyos/ets-source/pages/MainWindowNativeNode.ets
8401c425422bae30214307eee8f62d18cca7595946ae97e8ed4ad9c5b0f387a3  harmonyos/ets-source/pages/AstronomyGuide.ts
409fa6e6d49ce3255f341ed617563c474adc2a65ef75f49f53153742363313d7  harmonyos/ets-source/pages/DetailModelGeometry.ets
b3e10da0db5eb70bb0bda3142cf525e2e292b733d804d139b95df7b2a642ec7d  harmonyos/ets-source/pages/DetailModelRasterizer.ets
a8a236bcd46bab35bc2a8c86069772ec03687659f6b59cc6fb844bc1168798ca  harmonyos/ets-source/pages/DetailModelRenderClient.ets
9e968f6a8fea7e7912ab43943cc5c75fd8dfbb34dba7838608e79c9e938c2da9  harmonyos/ets-source/pages/StartupStarGeometry.ts
128aa1f2a70073b530d52f46755be1734b0d6a266054f6bc1b81ddb9ce0cc800  harmonyos/ets-source/common/PrivacyStartup.ets
7622ec5bbbf6ed4cd38ce981825484222e2cc428083a04c31de106d19a88f0e4  harmonyos/ets-source/qability/PrivacyConsent.ets
bedec884467f1cad784f705803399ae45d469062e19e87d13ebdf5ad029d34ed  harmonyos/cpp-source/PresentationGeometry.h
e11990f5ce1a593457f2e64580dc228ceb622b27ebe4a21ed72793f39f6b551d  harmonyos/AppScope/app.json5
```

## 来源审查与排除

- `src/StelMainView.cpp` 属于修改过的上游文件，保留 Fabien Chereau 等原版权和 GPL 声明；其新增部分需要差异与贡献证据。
- `src/scripting/StelScriptMgr.cpp` 的导览快照属于对上游脚本管理模块的扩展，不将整个执行器申报成新写。
- `harmonyos/cpp-source/hello.cpp` 有 Qt Company 版权和许可头；不能删除头部后作为纯原创交存。
- Qt 模板、第三方依赖、打包生成目录、签名文件、资源图像、PO/QM 译文、星表、地景和文化资料不能用来凑新增源程序页数。
- 开源许可及原作者信息保留；不把证书密码、AccessKey、Profile、真实用户身份信息或调试隐私日志装入提交材料。
- 当前仓库为浅克隆，未得到可信完整上游共同祖先；本轮没有计算“新增代码百分比”，也没有以新增文件名断言权利归属。

## 最终交存前

确定登记对象和版本 → 审核来源及许可 → 固定真实文件顺序 → 记录每页与原文件行的对应 → 按连续页要求排版 → 检查敏感内容 → 渲染核对 → 申请人审阅。

不得任意拼接各文件中间片段伪装成整个软件前后连续页；如需例外交存，按官方允许方式明确选择。后续代码变化应重新生成清单与材料，不能沿用旧摘要冒充同一版本。
