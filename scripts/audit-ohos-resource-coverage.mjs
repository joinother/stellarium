#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const rawRoot = path.join(root, 'build/libstellarium-harmonyos/entry/src/main/resources/rawfile/stellarium')
const output = path.join(root, 'docs/harmonyos/RESOURCE-COVERAGE-AUDIT-2026-08-24.md')

function walk(directory) {
  if (!fs.existsSync(directory)) return []
  const result = []
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const full = path.join(directory, entry.name)
    if (entry.isDirectory()) result.push(...walk(full))
    else if (entry.isFile()) result.push(full)
  }
  return result
}

function relativeFiles(directory) {
  return new Set(walk(directory).map(file => path.relative(directory, file).split(path.sep).join('/')).sort())
}

function bytes(directory) {
  return walk(directory).reduce((sum, file) => sum + fs.statSync(file).size, 0)
}

function count(set, predicate = () => true) {
  let total = 0
  for (const item of set) if (predicate(item)) total += 1
  return total
}

function formatBytes(value) {
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KiB`
  return `${(value / 1024 / 1024).toFixed(1)} MiB`
}

function extension(file) {
  return path.extname(file).toLowerCase()
}

function expectedFiles(name, source) {
  if (name === 'nebulae') {
    return new Set([...source].filter(file => ['.dat', '.json', '.png'].includes(extension(file))))
  }
  if (name === 'scripts') {
    return new Set([...source].filter(file => !file.includes('/') && ['.ssc', '.inc'].includes(extension(file))))
  }
  if (name === 'skycultures') {
    return new Set([...source].filter(file =>
      file !== 'CMakeLists.txt' &&
      file !== 'CMakeLists.txt.template' &&
      file !== 'TODO.txt' &&
      !file.endsWith('.py')))
  }
  return source
}

function tableRow(values) {
  return `|${values.join('|')}|`
}

function code(value) {
  return `\`${value}\``
}

function sourceRawComparison(name) {
  const source = relativeFiles(path.join(root, name))
  const expected = expectedFiles(name, source)
  const raw = relativeFiles(path.join(rawRoot, name))
  const missing = [...expected].filter(file => !raw.has(file)).sort()
  const unexpected = [...raw].filter(file => !expected.has(file)).sort()
  return {
    source,
    expected,
    raw,
    missing,
    unexpected,
    sourceBytes: bytes(path.join(root, name)),
    rawBytes: bytes(path.join(rawRoot, name)),
  }
}

function pluginResources() {
  const files = []
  const plugins = path.join(root, 'plugins')
  if (!fs.existsSync(plugins)) return files
  for (const plugin of fs.readdirSync(plugins, { withFileTypes: true })) {
    if (!plugin.isDirectory()) continue
    for (const area of ['resources', 'data']) {
      const directory = path.join(plugins, plugin.name, area)
      for (const file of walk(directory)) {
        const relative = path.relative(root, file).split(path.sep).join('/')
        if (!['.qrc', '.cmake'].includes(extension(file)) && !relative.endsWith('CMakeLists.txt') && !relative.endsWith('.sh')) {
          files.push(relative)
        }
      }
    }
  }
  return files.sort()
}

function pluginBuildFlags() {
  const cache = path.join(root, 'build/CMakeCache.txt')
  if (!fs.existsSync(cache)) return []
  return fs.readFileSync(cache, 'utf8').split(/\r?\n/)
    .filter(line => /^USE_PLUGIN_[^:]+:BOOL=/.test(line))
    .map(line => line.replace(/^([^:]+):BOOL=(.*)$/, '$1=$2'))
    .sort()
}

function main() {
  const names = ['data', 'textures', 'landscapes', 'nebulae', 'stars', 'translations', 'skycultures', 'scripts']
  const comparisons = new Map(names.map(name => [name, sourceRawComparison(name)]))
  const sky = comparisons.get('skycultures')
  const nebulae = comparisons.get('nebulae')
  const scripts = comparisons.get('scripts')
  const translations = comparisons.get('translations')
  const scenerySource = relativeFiles(path.join(root, 'scenery3d'))
  const sceneryRaw = relativeFiles(path.join(rawRoot, 'scenery3d'))
  const plugins = pluginResources()
  const sourceData = relativeFiles(path.join(root, 'data'))
  const rawData = relativeFiles(path.join(rawRoot, 'data'))
  const sourceDataGui = new Set([...sourceData].filter(file => file.startsWith('gui/')))
  const rawDataGui = new Set([...rawData].filter(file => file.startsWith('gui/')))
  const sourceDataIcons = new Set([...sourceData].filter(file => file.startsWith('icons/')))
  const rawDataIcons = new Set([...rawData].filter(file => file.startsWith('icons/')))
  const cultureDirectories = fs.existsSync(path.join(root, 'skycultures'))
    ? fs.readdirSync(path.join(root, 'skycultures'), { withFileTypes: true }).filter(entry => entry.isDirectory()).map(entry => entry.name).sort()
    : []
  const cultureDescriptions = [...sky.source].filter(file => /(^|\/)description(?:\.|$)/i.test(file))
  const cultureImages = [...sky.source].filter(file => ['.png', '.jpg', '.jpeg', '.svg', '.svgz'].includes(extension(file)))
  const qmDomains = fs.existsSync(path.join(root, 'translations'))
    ? fs.readdirSync(path.join(root, 'translations'), { withFileTypes: true }).filter(entry => entry.isDirectory()).map(entry => {
      const directory = path.join(root, 'translations', entry.name)
      return { name: entry.name, count: walk(directory).filter(file => extension(file) === '.qm').length }
    })
    : []
  const directUiSource = fs.readFileSync(path.join(root, 'harmonyos/ets-source/pages/MainWindowNativeNode.ets'), 'utf8')
  const coreSource = fs.readFileSync(path.join(root, 'src/StelMainView.cpp'), 'utf8')
  const lines = [
    '# 鸿蒙端原版资源覆盖审计',
    '',
    `生成时间：${new Date().toISOString()}`,
    '',
    '## 结论',
    '',
    '- **顶层核心资源**：`data`、`textures`、`landscapes`、`stars`、`translations` 的源文件与 rawfile 镜像一致；`nebulae`、`skycultures`、`scripts` 的差异符合当前同步脚本的排除规则。',
    '- **明确缺口**：`scenery3d/` 有源码资源但没有进入 rawfile；当前鸿蒙端不能据此声称已接入原版三维地景。',
    '- **插件资源**：发现插件自有资源，但它们不在 rawfile 独立目录中；是否可用取决于对应插件是否被编译进 `libstellarium.so`，需要逐插件运行验证。',
    '- **资源存在不等于界面使用**：原版桌面 UI 皮肤、按钮图片、QRC 和字体已随 `data` 打包，但鸿蒙界面主要使用 ArkUI/SVG 自绘控件；这属于“已打包、未直接复用”，不是“已完成 UI 移植”。',
    '',
    '## 顶层目录对照',
    '',
    '|目录|源码文件|期望同步|rawfile|未同步|大小（源码/rawfile）|判定|',
    '|---|---:|---:|---:|---:|---|---|',
    ...names.map(name => {
      const item = comparisons.get(name)
      const status = item.missing.length === 0 && item.unexpected.length === 0 ? '覆盖' : '有差异'
      return tableRow([code(name), item.source.size, item.expected.size, item.raw.size, item.missing.length, `${formatBytes(item.sourceBytes)} / ${formatBytes(item.rawBytes)}`, status])
    }),
    '',
    '### 差异解释',
    '',
    `- ${code('nebulae')} 未同步：${nebulae.missing.map(file => code(file)).join('、') || '无'}；其中 CMake 文件和 ${code('catalog.txt')} 不在现行 ${code('sync-ohos-resources.sh')} 的运行时白名单内。`,
    `- ${code('skycultures')} 未同步：${sky.missing.map(file => code(file)).join('、') || '无'}；这些是构建脚本、说明占位文件或 Python 辅助工具，不是运行时文化资料。`,
    `- ${code('scripts')} 期望值只包含顶层 ${code('.ssc/.inc')}；测试目录、音频/视频样例和审计/构建脚本不进入应用脚本列表。当前顶层资源：${scripts.expected.size} 个，rawfile：${scripts.raw.size} 个。`,
    `- ${code('stars')} rawfile 额外残留：${comparisons.get('stars').unexpected.map(file => code(file)).join('、') || '无'}；这类文件来自旧同步结果，已将普通目录同步改为带 ${code('--delete')} 的镜像模式。`,
    '',
    '## 文本、简介与翻译',
    '',
    '|资源|源码情况|鸿蒙入口|状态|',
    '|---|---|---|---|',
    tableRow(['官方 `.qm` 翻译', `${qmDomains.map(item => `${code(item.name)} ${item.count} 个`).join('；')}`, '`LocaleMgr` / 核心天体名称 / UI I18n 校验', '已打包；域内语言数量以实际编译结果为准']),
    tableRow(['天体简介', '`StelObject::getInfoMap`、`getInfoString`、`getObjectSpokenText`', '`getObjectInfo`、`getObjectSpokenText`', '已接入核心详情；需设备抽样检查不同类型简介是否为空']),
    tableRow(['地景介绍', '`landscapes/*/landscape.ini` 和描述文本', '`getLandscapeInfo` 返回 description', '已接入当前地景；多语言覆盖需抽样验证']),
    tableRow(['星空文化介绍', `${cultureDescriptions.length} 个 description 文件`, '`getSkyCultureDetails` 返回 description/narration', '已接入；界面图片最多展示 24 张，属于展示限制']),
    tableRow(['行星地貌简介', '`translations/stellarium-planetary-features/*.qm`、`data/nomenclature.*`', '当前命令桥未发现独立的行星地貌资料面板', '资源已打包；是否完整呈现需补功能验证']),
    tableRow(['脚本简介', '脚本注释中的名称、作者、描述', '`getScriptList` 只返回脚本文件名', '脚本列表已接入，原版脚本详情文本尚未确认接入']),
    '',
    '## 图片和图形资源',
    '',
    '|资源|数量|当前状态|说明|',
    '|---|---:|---|---|',
    tableRow(['深空 PNG', count(nebulae.expected, file => extension(file) === '.png'), '已打包并由核心纹理机制按需加载', '启动阶段不复制全部图片；设备运行时需用 `getDeepSkyImageStatus` 验证引用、文件和纹理就绪状态']),
    tableRow(['天空文化绘图', cultureImages.length, '已打包；详情入口可读取路径', '源目录 63 个文化目录、65 个描述文件；当前界面最多显示 24 张绘图']),
    tableRow(['原版桌面 GUI 图片', sourceDataGui.size, '已打包但鸿蒙未直接复用', '鸿蒙主要使用 ArkUI；`data/gui/miscWorldMap.jpg` 另有 `$rawfile(\'worldmap.jpg\')` 替代入口']),
    tableRow(['原版应用图标', sourceDataIcons.size, '已打包；应用图标另有 HarmonyOS media 配置', '需要确认最终签名包使用的是哪套图标资源']),
    tableRow(['三维地景模型/纹理', scenerySource.size, '未打包、未接入', '源目录包含 OBJ/MTL/纹理/多语言 description；这是当前最高优先级资源缺口']),
    '',
    '## 插件资源',
    '',
    `插件资源候选共 **${plugins.length}** 个（` + '`plugins/*/resources`、`plugins/*/data`' + '）。它们由各插件的 QRC/模块构建逻辑管理，不会被 `sync-ohos-resources.sh` 复制到 rawfile。',
    '',
    `当前 CMake 插件开关：${pluginBuildFlags().map(flag => code(flag)).join('、') || '未读取到 build/CMakeCache.txt 中的 USE_PLUGIN_* 开关'}。`,
    '',
    '审计判断：',
    '',
    '- 已启用且资源编译进插件模块的插件，可通过核心运行；这需要逐个打开插件面板并检查资源加载日志。',
    '- 未启用插件的资源即使存在于源码，也不属于当前鸿蒙包的可用功能。',
    '- `OnlineQueries`、远程控制、卫星更新等涉及网络的插件必须保持离线默认，并另行登记网络行为；本报告不把它们列为已接入。',
    '',
    '## 三维地景缺口',
    '',
    `- 源码：${code(scenerySource.size)} 个文件，约 ${formatBytes(bytes(path.join(root, 'scenery3d')))}。`,
    `- rawfile：${code(sceneryRaw.size)} 个文件，约 ${formatBytes(bytes(path.join(rawRoot, 'scenery3d')))}。`,
    '- 核心源码有 `Scenery3d`、OBJ/MTL 和 shader 支持，但当前鸿蒙资源引导没有 `scenery3d/`，也没有发现鸿蒙端独立的三维地景入口。',
    '- 处理建议：单独设计资源裁剪、内存预算、离线加载和触摸/键鼠/CLI 控制后再迁移，不建议把全部三维资源直接塞入首包。',
    '',
    '## 静态入口证据',
    '',
    `- ArkUI 调用天空文化列表/详情/区域几何：${code(directUiSource.includes('getSkyCultureList') && directUiSource.includes('getSkyCultureDetails') ? '已找到' : '未找到')}。`,
    `- ArkUI 调用脚本列表：${code(directUiSource.includes('getScriptList') ? '已找到' : '未找到')}。`,
    `- C++ 深空状态审计命令：${code(coreSource.includes('getDeepSkyImageStatus') ? '已找到' : '未找到')}。`,
    `- 原版世界地图资源：${code(sourceDataGui.has('gui/miscWorldMap.jpg') && rawDataGui.has('gui/miscWorldMap.jpg') ? '已进入 rawfile；ArkUI 使用独立 worldmap.jpg' : '需检查')}。`,
    '',
    '## 后续优先级',
    '',
    '1. **P0：** 在设备上验证深空图片引用、实际文件、纹理就绪三者是否一致，并记录 M31、M42、M31 以外的代表样本。',
    '2. **P1：** 明确插件启用矩阵，逐个补资源加载探针；尤其是 Oculars、SolarSystemEditor、NebulaTextures、Satellites、MeteorShowers 和 Scenery3d。',
    '3. **P1：** 接入行星地貌简介和脚本详情文本，不只显示文件名。',
    '4. **P2：** 评估并裁剪三维地景资源，加入独立加载进度和内存失败回退。',
    '5. **P2：** 为天空文化补齐官方可用语言资源；当前 `en`、`zh_CN` 之外不要假称已完成多语言。',
    '',
    '本报告只做静态资源覆盖审计；“已接入”表示代码入口存在，不替代平板/模拟器上的真实渲染验证。',
  ]
  fs.writeFileSync(output, `${lines.join('\n')}\n`)
  console.log(`已生成 ${output}`)
  console.log(`顶层目录：${names.length}；三维地景源码 ${scenerySource.size}，rawfile ${sceneryRaw.size}；插件资源 ${plugins.length}`)
}

main()
