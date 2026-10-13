# CompileArkTS 独立构建诊断

验证时间：2026-09-08 07:57（Asia/Shanghai）。

## 结论

- 已找到并实际执行可靠的 ArkTS 编译入口：`--mode module -p module=entry@default default@CompileArkTS`。
- 返回码 `0`，`BUILD SUCCESSFUL in 7 s 892 ms`；包含启动开销的实测耗时约 8.45 秒，`CompileArkTS` 本身耗时 4.464 秒，并非仅命中缓存。
- 本次在源码同步完成后执行；生成工程中的 `StellariumResourceBootstrap.ets` 与 `harmonyos/ets-source/qability/StellariumResourceBootstrap.ets` 内容一致，包含父代理同步的 bootstrap 改动。
- 没有执行 assembleHap、安装、签名、原生构建或任何停止进程操作。

## 已验证的安全命令

在生成的 HarmonyOS 工程根目录执行，而不是仓库根目录或 `harmonyos` 模板目录：

```sh
cd /Users/jiexuanyang/stellarium-src/build/libstellarium-harmonyos
env \
  NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
  JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
  DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  PATH="/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:$PATH" \
  /Applications/DevEco-Studio.app/Contents/tools/node/bin/node \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js \
  --mode module \
  -p product=default \
  -p module=entry@default \
  -p buildMode=debug \
  default@CompileArkTS \
  --no-daemon
```

这里“仅 ArkTS 编译”指选取 CompileArkTS 及其必需前置任务，不是跳过资源和元数据准备。无需删除或改动签名配置，也无需添加任何关闭签名的工程配置。

## 失败原因与排除项

1. **任务名缺少 target 前缀。** `CompileArkTS` 并非本工程注册的完整任务名；实际名称是 `default@CompileArkTS`。`-p product=default` 或 `-p module=entry@default` 不会把裸任务名自动补成该名称。
2. **不要直接复制日志中的前导冒号。** `:entry:default@CompileArkTS` 是日志显示形态。本机 `task-path-util.js` 按冒号拆分后取前两个字段作为模块和任务，前导冒号会造成错位。推荐使用上面已实际通过的模块模式命令，不依赖带冒号的路径写法。
3. **`tasks` 列表不完整，不代表插件未加载。** 本机 Hvigor 与 OHOS 插件均为 6.24.4。插件使用惰性任务容器，编译任务保存在 `_lazyTasks`，而 `getAllTasks()` 只返回已实例化的 `_tasks`。本次显式指定 module、target、product、debug 后，`tasks` 仍仅列出 entry 的基础帮助和 init 任务，但正确名称可以直接编译成功。
4. **product/target 映射正常。** 模板与生成工程的相关映射一致，不需要改 profile 来生成任务。安全子集如下：

   | 层级 | 非敏感 name / product / target 信息 |
   | --- | --- |
   | 工程 product | `default` |
   | 工程 buildMode name | `debug`、`release` |
   | module name | `entry` |
   | module target → product | `default` → `default` |
   | entry target name | `default`、`ohosTest` |

5. **本次无需切换 SDK 或构建模式。** Node 为 DevEco 自带 18.20.1，SDK 使用 DevEco 的 `Contents/sdk`，`buildMode=debug` 已通过。本次没有验证 release 或 ohosTest 编译，也不建议为解决任务查找而切换它们。

## 实际任务与警告

- 已执行：PreBuild、CreateModuleInfo、MergeProfile、CreateBuildProfile、GeneratePkgContextInfo、ProcessProfile、ProcessRouterMap、ProcessShareConfig、ProcessStartupConfig、GenerateLoaderJson、CompileResource、CompileArkTS；ProcessResource 为 UP-TO-DATE。
- 未出现 BuildNativeWithCmake、CompileNative、PackageHap、SignHap 或 assembleHap 执行记录。检查本机插件的 ArkTS 前置依赖及当前配置后再启动验证，没有重复父代理的 CMake 构建。
- 编译通过，有 17 条 ArkTS 警告。Bootstrap 的四处警告为：106:19 的 `getSystemLocale` 弃用，以及 285:20、290:19、295:20 的潜在异常处理提示；其余位于 I18n、MainWindowNativeNode、FloatWindowNativeNode、SubWindowNativeNode、UiExtensionNativeNode。本次仅诊断，不修改这些代码。
- 上述无原生/无签名结论针对本次配置和依赖关系；若未来工程改变 ArkTS 前置依赖，需重新检查，不能将此命令视为任意工程都无原生依赖的通用保证。

## 配置完整性与范围

编译前后对生成工程的工程级/entry 级 build-profile、工程级/entry 级 hvigorfile、hvigor-config 共五个文件做内存内 SHA-256 对比，全部一致。没有改动签名、工程配置、JSON 或 CHANGELOG；人工写入仅限本文档。Hvigor 自身更新了正常的编译中间产物、缓存和日志。

## 依据

- 华为开发者知识 MCP 检索并读取的[命令行构建工具（hvigorw）官方说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-commandline)：module/target 选择需配合 `--mode module`，以及 product、buildMode、no-daemon 参数语义。
- 本机 Hvigor 6.24.4 实现：`src/base/internal/task/core/lazy-task-container.js`、`src/base/internal/task/util/task-path-util.js`；OHOS 插件实现：`src/tasks/manager/arkts-task-initializer.js`、`src/tasks/manager/task-creation-manager.js`。
- 本文命令在当前工程上的实际成功执行与前后配置完整性校验。官方参数说明不等同于对本机任务枚举行为的保证；任务名、惰性列表和路径结论来自本机实现及实测。
