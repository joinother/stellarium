# 审核冻屏：Qt 剪贴板通知修复

## 证据与范围

2026-09-07 的 1000049 审核故障主线程阻塞于 libqohos → OH_Pasteboard_GetData → Binder 等待。Qt 剪贴板变化通知读取完整内容来区分写入来源；该回调不要求用户点击粘贴，跨设备剪贴板变化也可能触发。Qt 渲染线程同时存在驱动等待，单个堆栈不能解释所有卡顿。

本次删除通知回调中的内容读取，直接使 Qt 剪贴板缓存失效并发送原有变更通知。显式复制、粘贴接口保留。未来新增原生 Qt 粘贴功能，仍须审计显式读操作的线程、权限和耗时；本补丁不将其伪装成异步读取。

应用复制集中到 `ClipboardService.ets`：当前政策同意、应用前台、长度限制、单请求在途，使用系统异步 setData；结果只返回成功/失败及字符数，不返回正文、平台异常或设备标识。不新增读取剪贴板或设备标识权限。

## 精确 SDK 与构建

- Qt 6.12.0 HarmonyOS arm64，SDK SBOM 指定 [qtbase 修订 97575d35](https://github.com/qt/qtbase/tree/97575d35c0cecdc0fb4e12fc3575afaa9fd9d3f1)，不能换成最新 dev。原始 clipboard 源文件 SHA1 `2beca4b72fb6b0afbe0f34320e743165e3d26d53` 与 SDK 源码 SBOM 一致。
- `bash scripts/build-ohos-platform-patch.sh` 校验官方源码压缩包 SHA256、SDK 修订，应用 `harmonyos/qt-platform-patch/clipboard-notification.patch`，仅重建平台插件。`QTBASE_ARCHIVE` 可指定已经下载的相同压缩包。
- 库、源码及 manifest 位于忽略的 `build/qt-platform-patch/`，不覆盖全局 SDK，不读写签名材料。
- `node scripts/check-ohos-platform-patch.mjs --sync` 核对补丁、生成库及 SDK Core/Gui/OpenGL 三个依赖摘要后复制到生成工程。源码同步和提交前检查设门禁，防止部署工具把旧 libqohos 带回包内。
- 修改补丁前，先在此临时源码树反向应用旧补丁，再用新补丁构建；升级 Qt 必须重新核对源码、私有 API 和设备结果，不跳过摘要门禁。

## SN 验证

SDK 的 `initDeviceInfo` 字段仍含 serial/udid，按用户要求保留。调用位于 setupQtApplication 内；ArkTS 同意门禁和资源准备后的二次同意检查必须先完成。新增原生开始/结束探针，只记录阶段，不打印字段值。探针用于核对时序，不等同于系统级个人信息检测报告。

## 授权与发布

保留上游源文件 SPDX、版权和完整许可证，补丁依照对应 Qt 源文件许可证分发。仓库记录精确来源和补丁；发行时沿用项目 Qt 开源许可和对应源码提供流程，不只分发自改二进制而丢失来源。原始审核附件、设备指纹和原始诊断日志不上传 Git。

华为官方依据：AppFreeze 定位指南、剪贴板复制粘贴指南（本轮通过开发知识 MCP 读取）；界面线程避免同步耗时任务。实测结果及剩余限制见 `PRIVACY-REVIEW-2026-09-08.md` 和 `CHANGELOG.md`。
