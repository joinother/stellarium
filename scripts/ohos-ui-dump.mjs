#!/usr/bin/env node
// HarmonyOS 真机 UI 控件树读取与断言封装。
//
// 底层使用 `uitest dumpLayout` 的富属性树，而不是 `devecocli ui layout`
// （后者只投影 id/type/text/bounds/clickable，缺少 enabled/opacity/
// backgroundColor/blur 等）。适用于 ArkUI 节点的存在性、可见性、位置、
// 启用状态、透明度与背景色断言；字体大小/字重/字体颜色、backdropBlur、
// XComponent/GL 渲染内容仍然只能靠截图或录屏确认。
//
// 用法示例：
//   node scripts/ohos-ui-dump.mjs --device 192.168.3.95:36717 \
//     --id loc-open-map-current
//   node scripts/ohos-ui-dump.mjs --device 192.168.3.95:36717 \
//     --id map-app-mode-route --expect-visible --expect-enabled
//   node scripts/ohos-ui-dump.mjs --device 192.168.3.95:36717 \
//     --text-contains 星点亮度 --expect-present
//
// 退出码：0 通过；1 断言失败/查询无匹配；2 设备、解析或参数错误。

import { existsSync, mkdirSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { spawnSync } from 'node:child_process'

export const DEFAULT_BUNDLE = process.env.STELLARIUM_BUNDLE || 'com.joinother.skyinstrument'

const DEFAULT_FIELDS = [
  'type', 'id', 'text', 'bounds', 'visible', 'enabled', 'opacity', 'backgroundColor', 'blur'
]

export function parseBounds(value) {
  const match = /^\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]$/.exec(String(value ?? '').trim())
  if (!match) return null
  return [Number(match[1]), Number(match[2]), Number(match[3]), Number(match[4])]
}

export function boolAttr(value) {
  return String(value ?? '').trim().toLowerCase() === 'true'
}

export function parseOpacity(value) {
  const parsed = Number.parseFloat(String(value ?? '').trim())
  return Number.isFinite(parsed) ? parsed : NaN
}

// #AARRGGBB -> alpha (0..1)
export function backgroundAlpha(value) {
  const match = /^#([0-9a-fA-F]{8})$/.exec(String(value ?? '').trim())
  if (!match) return NaN
  return Number.parseInt(match[1].slice(0, 2), 16) / 255
}

function effectiveText(attrs) {
  return String(attrs.originalText || attrs.text || '')
}

// 把 uitest 的嵌套树展开为数组；每个条目保留 depth 与祖先链，便于输出定位路径。
export function flattenLayout(layout) {
  const nodes = []
  const roots = Array.isArray(layout) ? layout : [layout]
  const walk = (node, depth, parents) => {
    if (!node || typeof node !== 'object') return
    const attributes = node.attributes && typeof node.attributes === 'object' ? node.attributes : {}
    nodes.push({ attributes, depth, parents })
    const children = Array.isArray(node.children) ? node.children : []
    for (const child of children) walk(child, depth + 1, parents.concat([attributes]))
  }
  for (const root of roots) walk(root, 0, [])
  return nodes
}

export function nodeMatches(attrs, query) {
  if (query.id !== undefined && String(attrs.id || '') !== query.id) return false
  if (query.type !== undefined && String(attrs.type || '') !== query.type) return false
  if (query.text !== undefined && effectiveText(attrs) !== query.text) return false
  if (query.textContains !== undefined && !effectiveText(attrs).includes(query.textContains)) return false
  return true
}

export function selectNodes(nodes, query) {
  return nodes.filter((node) => nodeMatches(node.attributes, query))
}

export function hasExpectation(options) {
  return options.expectPresent === true || options.expectAbsent === true ||
    options.expectVisible !== undefined || options.expectEnabled !== undefined ||
    options.expectOpacity !== undefined || options.expectBackground !== undefined ||
    options.expectBgAlpha !== undefined || options.expectBounds !== undefined
}

export function evaluateExpectations(matches, options) {
  const failures = []
  const wantPresent = options.expectPresent === true
  const wantAbsent = options.expectAbsent === true
  if (wantPresent && matches.length === 0) failures.push('expect-present: 没有匹配节点')
  if (wantAbsent && matches.length > 0) failures.push(`expect-absent: 仍有 ${matches.length} 个匹配节点`)

  const stateKeys = [
    'expectVisible', 'expectEnabled', 'expectOpacity', 'expectBackground',
    'expectBgAlpha', 'expectBounds'
  ]
  const needsSingle = stateKeys.some((key) => options[key] !== undefined)
  if (needsSingle) {
    if (matches.length === 0) {
      failures.push('状态断言: 没有匹配节点')
    } else if (matches.length > 1 && options.first !== true) {
      failures.push(`状态断言: 匹配到 ${matches.length} 个节点，请收窄选择器或加 --first`)
    }
  }

  if (matches.length >= 1 && (matches.length === 1 || options.first === true)) {
    const attrs = matches[0].attributes
    const tolerance = Number.isFinite(options.tolerance) ? options.tolerance : 0.01
    if (options.expectVisible !== undefined &&
        boolAttr(attrs.visible) !== options.expectVisible) {
      failures.push(`expect-visible: 期望 ${options.expectVisible}，实际 ${attrs.visible}`)
    }
    if (options.expectEnabled !== undefined &&
        boolAttr(attrs.enabled) !== options.expectEnabled) {
      failures.push(`expect-enabled: 期望 ${options.expectEnabled}，实际 ${attrs.enabled}`)
    }
    if (options.expectOpacity !== undefined) {
      const actual = parseOpacity(attrs.opacity)
      if (!Number.isFinite(actual) || Math.abs(actual - options.expectOpacity) > tolerance) {
        failures.push(`expect-opacity: 期望 ${options.expectOpacity} ±${tolerance}，实际 ${attrs.opacity}`)
      }
    }
    if (options.expectBackground !== undefined) {
      const actual = String(attrs.backgroundColor || '').toUpperCase()
      if (actual !== options.expectBackground.toUpperCase()) {
        failures.push(`expect-background: 期望 ${options.expectBackground}，实际 ${attrs.backgroundColor}`)
      }
    }
    if (options.expectBgAlpha !== undefined) {
      const actual = backgroundAlpha(attrs.backgroundColor)
      if (!Number.isFinite(actual) || Math.abs(actual - options.expectBgAlpha) > tolerance) {
        failures.push(`expect-bg-alpha: 期望 ${options.expectBgAlpha} ±${tolerance}，实际 ${attrs.backgroundColor}`)
      }
    }
    if (options.expectBounds !== undefined) {
      const actual = parseBounds(attrs.bounds)
      const expected = options.expectBounds
      if (!actual || actual.length !== 4 || actual.some((value, index) => value !== expected[index])) {
        failures.push(`expect-bounds: 期望 ${expected.join(',')}，实际 ${attrs.bounds}`)
      }
    }
  }

  return { ok: failures.length === 0, failures }
}

function usage() {
  return `用法：
  node scripts/ohos-ui-dump.mjs [选项]

读取设备当前前台窗口的 uitest 控件树，并按 id/text/type 查询或断言。

设备与窗口：
  --device <id>            hdc 目标（IP:port 或序列号）；省略时使用唯一设备
  --hdc <path>             hdc 可执行文件；默认读 HDC/HDC_BIN/DEVECO_HOME
  --bundle <name>          目标包名；默认 ${DEFAULT_BUNDLE}
  --window <id>            指定窗口 id（uitest -w）
  --display <id>           指定显示 id（uitest -d）
  --no-merge               不合并窗口（uitest -m false）
  --allow-empty            允许空树（默认 bundle 模式视为前台不可读错误）

查询：
  --id <id>                按 id 精确匹配
  --text <text>            按可见文本精确匹配
  --text-contains <text>   按可见文本子串匹配
  --type <Type>            按控件类型精确匹配（如 Button/Slider/Text）
  --all                    输出全部节点（不能与选择器同用）
  --first                  状态断言/输出只取第一个匹配节点
  --json                   以 JSON 输出匹配节点的属性
  --dump-only              只导出并汇总，不做查询

断言（需配合选择器）：
  --expect-present         至少有一个匹配
  --expect-absent          没有匹配
  --expect-visible         匹配节点 visible=true
  --expect-hidden          匹配节点 visible=false
  --expect-enabled         匹配节点 enabled=true
  --expect-disabled        匹配节点 enabled=false
  --expect-opacity <0..1>  匹配节点 opacity（默认容差 0.01）
  --expect-background <#AARRGGBB>
  --expect-bg-alpha <0..1> 背景色 alpha 分量
  --expect-bounds <x1,y1,x2,y2>
  --tolerance <number>     opacity/alpha 容差，默认 0.01

输出：
  --out <path>             保存原始控件树，默认 build/ui-layout.json
  --no-save                不保存原始控件树（使用临时文件）

退出码：0 通过；1 断言失败或查询无匹配；2 参数/设备/解析错误。
注意：uitest 只读取前台可见窗口；字体字重、backdropBlur、GL/XComponent
内容和实际渲染像素不在控件树中，仍需截图或录屏验证。
`
}

function fail(message) {
  const error = new Error(message)
  error.exitCode = 2
  throw error
}

function parseNumber(value, name, min, max) {
  const parsed = Number(value)
  if (!Number.isFinite(parsed) || parsed < min || parsed > max) {
    fail(`${name} 需要 ${min}..${max} 的数字，收到 ${value}`)
  }
  return parsed
}

export function parseArgs(argv) {
  const options = {
    bundle: DEFAULT_BUNDLE,
    merge: true,
    save: true,
    out: 'build/ui-layout.json',
    tolerance: 0.01
  }
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index]
    const take = (name) => {
      if (index + 1 >= argv.length) fail(`${name} 缺少参数`)
      index += 1
      return argv[index]
    }
    switch (arg) {
      case '--help':
      case '-h':
        options.help = true
        break
      case '--device':
        options.device = take(arg)
        break
      case '--hdc':
        options.hdc = take(arg)
        break
      case '--bundle':
        options.bundle = take(arg)
        break
      case '--window':
        options.window = take(arg)
        break
      case '--display':
        options.display = take(arg)
        break
      case '--no-merge':
        options.merge = false
        break
      case '--allow-empty':
        options.allowEmpty = true
        break
      case '--id':
        options.id = take(arg)
        break
      case '--text':
        options.text = take(arg)
        break
      case '--text-contains':
        options.textContains = take(arg)
        break
      case '--type':
        options.type = take(arg)
        break
      case '--all':
        options.all = true
        break
      case '--first':
        options.first = true
        break
      case '--json':
        options.json = true
        break
      case '--dump-only':
        options.dumpOnly = true
        break
      case '--expect-present':
        options.expectPresent = true
        break
      case '--expect-absent':
        options.expectAbsent = true
        break
      case '--expect-visible':
        options.expectVisible = true
        break
      case '--expect-hidden':
        options.expectVisible = false
        break
      case '--expect-enabled':
        options.expectEnabled = true
        break
      case '--expect-disabled':
        options.expectEnabled = false
        break
      case '--expect-opacity':
        options.expectOpacity = parseNumber(take(arg), arg, 0, 1)
        break
      case '--expect-background':
        options.expectBackground = take(arg)
        break
      case '--expect-bg-alpha':
        options.expectBgAlpha = parseNumber(take(arg), arg, 0, 1)
        break
      case '--expect-bounds': {
        const raw = take(arg)
        const parts = String(raw).split(',').map((part) => Number.parseInt(part.trim(), 10))
        if (parts.length !== 4 || parts.some((part) => !Number.isFinite(part))) {
          fail(`${arg} 需要 x1,y1,x2,y2，收到 ${raw}`)
        }
        options.expectBounds = parts
        break
      }
      case '--tolerance':
        options.tolerance = parseNumber(take(arg), arg, 0, 1)
        break
      case '--out':
        options.out = take(arg)
        break
      case '--no-save':
        options.save = false
        break
      default:
        fail(`未知参数 ${arg}`)
    }
  }

  if (options.help) return options
  if (options.expectPresent && options.expectAbsent) fail('--expect-present 与 --expect-absent 不能同时使用')
  if (argv.includes('--expect-visible') && argv.includes('--expect-hidden')) {
    fail('--expect-visible 与 --expect-hidden 不能同时使用')
  }
  if (argv.includes('--expect-enabled') && argv.includes('--expect-disabled')) {
    fail('--expect-enabled 与 --expect-disabled 不能同时使用')
  }
  if (options.all && (options.id !== undefined || options.text !== undefined ||
      options.textContains !== undefined || options.type !== undefined)) {
    fail('--all 不能与 --id/--text/--text-contains/--type 同时使用')
  }
  const hasSelector = options.id !== undefined || options.text !== undefined ||
    options.textContains !== undefined || options.type !== undefined
  if (hasExpectation(options) && !hasSelector) {
    fail('断言需要至少一个选择器（--id/--text/--text-contains/--type）')
  }
  if (options.dumpOnly && (hasSelector || options.all || hasExpectation(options))) {
    fail('--dump-only 不能与查询、--all 或断言同时使用')
  }
  if (!options.dumpOnly && !options.all && !hasSelector) {
    fail('请提供选择器（--id/--text/--text-contains/--type），或使用 --all/--dump-only')
  }
  return options
}

function resolveHdc(explicit) {
  const executable = process.platform === 'win32' ? 'hdc.exe' : 'hdc'
  const candidates = []
  if (explicit) candidates.push(explicit)
  for (const name of ['HDC', 'HDC_BIN', 'DEVECO_HDC']) {
    if (process.env[name]) candidates.push(process.env[name])
  }
  if (process.env.DEVECO_HOME) {
    candidates.push(join(process.env.DEVECO_HOME, 'sdk/default/openharmony/toolchains', executable))
  }
  if (process.platform === 'darwin') {
    candidates.push('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc')
  }
  if (process.platform === 'win32') {
    candidates.push('E:/code/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe')
    candidates.push('C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe')
  }
  candidates.push(executable)
  for (const candidate of candidates) {
    if (candidate === executable || existsSync(candidate)) return candidate
  }
  return executable
}

function runHdc(hdc, device, args, timeout) {
  const fullArgs = device ? ['-t', device, ...args] : args
  const result = spawnSync(hdc, fullArgs, { encoding: 'utf8', timeout })
  if (result.error) {
    fail(`无法执行 hdc：${result.error.message}`)
  }
  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout || '').trim()
    fail(`hdc ${fullArgs.join(' ')} 失败（${result.status}）${detail ? '：' + detail : ''}`)
  }
  return result.stdout || ''
}

export function summarizeRoot(layout) {
  // Some API versions wrap the real window node in one extra root level; the
  // bundle/ability/page fields then live on the first child, not the root.
  const named = flattenLayout(layout).find((node) => node.attributes.bundleName)
  if (named) return named.attributes
  const roots = Array.isArray(layout) ? layout : [layout]
  for (const root of roots) {
    const attrs = root && root.attributes ? root.attributes : {}
    if (attrs.bounds && attrs.bounds !== '[0,0][0,0]') return attrs
  }
  return {}
}

function formatNode(node, index, prefix) {
  const attrs = node.attributes
  const parts = []
  for (const field of DEFAULT_FIELDS) {
    if (field === 'text') {
      const text = effectiveText(attrs)
      if (text) parts.push(`text="${text}"`)
    } else if (attrs[field] !== undefined && attrs[field] !== '') {
      parts.push(`${field}=${attrs[field]}`)
    }
  }
  const lines = [`${prefix}${index + 1}. ${attrs.type || '?'}${attrs.id ? '#' + attrs.id : ''} ${parts.join(' ')}`]
  const path = node.parents
    .filter((parent) => parent.type || parent.id)
    .map((parent) => `${parent.type || '?'}${parent.id ? '#' + parent.id : ''}`)
  if (path.length > 0) lines.push(`${prefix}   path: ${path.join(' > ')}`)
  return lines.join('\n')
}

function main() {
  const options = parseArgs(process.argv.slice(2))
  if (options.help) {
    process.stdout.write(usage())
    return 0
  }

  const hdc = resolveHdc(options.hdc)
  const remote = `/data/local/tmp/stellarium-ui-${process.pid}-${Date.now()}.json`
  const local = options.save ? resolve(options.out) : join(tmpdir(), `stellarium-ui-${process.pid}-${Date.now()}.json`)
  if (options.save) mkdirSync(dirname(local), { recursive: true })

  const flags = []
  if (options.bundle) flags.push('-b', options.bundle)
  if (options.window) flags.push('-w', options.window)
  if (options.display) flags.push('-d', options.display)
  if (!options.merge) flags.push('-m', 'false')
  const dumpCommand = `uitest dumpLayout -p ${remote} ${flags.join(' ')}`.trim()

  try {
    runHdc(hdc, options.device, ['shell', dumpCommand], 30000)
    runHdc(hdc, options.device, ['file', 'recv', remote, local], 30000)
    runHdc(hdc, options.device, ['shell', `rm -f ${remote}`], 10000)
  } catch (error) {
    if (!options.save) rmSync(local, { force: true })
    throw error
  }

  let layout
  try {
    layout = JSON.parse(readFileSync(local, 'utf8'))
  } catch (error) {
    if (!options.save) rmSync(local, { force: true })
    fail(`解析控件树失败：${error.message}`)
  }

  const nodes = flattenLayout(layout)
  const root = summarizeRoot(layout)
  if (!options.allowEmpty && options.bundle && !root.bundleName) {
    if (!options.save) rmSync(local, { force: true })
    fail(`uitest 返回空树：${options.bundle} 不在前台或窗口不可读。` +
      '请先 aa start 把应用切到前台，再用 devecocli ui window list 确认当前前台窗口。')
  }

  if (options.dumpOnly) {
    console.log(`layout: ${options.save ? local : '(临时文件已删除)'}`)
    console.log(`bundle: ${root.bundleName || '-'} ability: ${root.abilityName || '-'} page: ${root.pagePath || '-'}`)
    console.log(`nodes: ${nodes.length}`)
    if (!options.save) rmSync(local, { force: true })
    return 0
  }

  let matches
  if (options.all) {
    matches = nodes
  } else {
    matches = selectNodes(nodes, {
      id: options.id,
      text: options.text,
      textContains: options.textContains,
      type: options.type
    })
  }
  if (options.first) matches = matches.slice(0, 1)

  if (options.json) {
    console.log(JSON.stringify(matches.map((node) => node.attributes), null, 2))
  } else if (matches.length === 0) {
    console.error('没有匹配的节点。')
  } else {
    for (let index = 0; index < matches.length; index++) {
      console.log(formatNode(matches[index], index, ''))
    }
  }

  const evaluation = evaluateExpectations(matches, options)
  const expectationRequested = hasExpectation(options)
  if (expectationRequested) {
    if (!options.json) console.log(evaluation.ok ? 'PASS' : 'FAIL')
    for (const failure of evaluation.failures) console.error(`  ${failure}`)
  }

  if (!options.save) rmSync(local, { force: true })

  if (expectationRequested) return evaluation.ok ? 0 : 1
  return matches.length > 0 ? 0 : 1
}

const invokedDirectly = process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
if (invokedDirectly) {
  try {
    process.exitCode = main()
  } catch (error) {
    console.error(`ERROR: ${error.message}`)
    process.exitCode = error.exitCode || 2
  }
}
