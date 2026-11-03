#!/usr/bin/env node
/**
 * 构建期校验：上游 CMake 声明的顶层数据目录，是否都进了 HAP rawfile 白名单。
 *
 * 背景：26.3 新增 atmosphere/（物理大气散射模型，59 MB），但
 * scripts/sync-ohos-resources.sh 的 DIRS 白名单是人工维护的，没有跟上。
 * 结果是包内缺该目录 → 天空渲染全黑、夜间看不到星星，而且日志没有报错，
 * 只能靠用户反馈才发现。skycultures/potawatomi 的启动卡死是同一类问题。
 *
 * 判据：根 CMakeLists.txt 的 ADD_SUBDIRECTORY(...) 是“上游认为需要安装的目录”，
 * 其中属于运行期数据的部分必须出现在 DIRS 里。
 *
 * 用法：node scripts/check-ohos-resource-dirs.mjs
 * 退出码：0 = 一致；1 = 有缺失（打印缺失项与修复提示）
 */
import { readFileSync, existsSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = resolve(SCRIPT_DIR, '..')

// 这些顶层目录不进入 rawfile，且各自有明确理由。
// 新增排除项必须写理由，避免变成“报错了就加进白名单”的循环。
const NON_DATA_DIRS = new Map([
  ['src', 'C++ 源码，编译进 libstellarium.so'],
  ['plugins', '插件源码与资源，编译进库'],
  ['doc', '文档，不随包分发'],
  ['po', '翻译源文件，构建期由 build-ohos-official-translations.mjs 生成 .qm'],
  ['models', '3D 模型源文件，构建期处理后进入 textures/'],
  ['cmake', 'CMake 模块'],
])

function readText(relPath) {
  return readFileSync(join(REPO_ROOT, relPath), 'utf8')
}

// 1) 上游声明的顶层子目录
const cmake = readText('CMakeLists.txt')
const declared = [...cmake.matchAll(/^\s*ADD_SUBDIRECTORY\(\s*([A-Za-z0-9_.-]+)\s*\)/gim)]
  .map((m) => m[1].toLowerCase())
const declaredSet = new Set(declared)

// 2) 同步脚本里的 DIRS 白名单
const syncSh = readText('scripts/sync-ohos-resources.sh')
const dirsMatch = syncSh.match(/^DIRS=\(([^)]*)\)/m)
if (!dirsMatch) {
  console.error('FAIL: 无法从 scripts/sync-ohos-resources.sh 解析 DIRS 白名单')
  process.exit(1)
}
const whitelist = new Set(
  dirsMatch[1]
    .split(/\s+/)
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean)
)

// 3) 需要进 rawfile 的候选目录 = 上游声明 - 已备案的非数据目录
const candidates = [...declaredSet].filter((name) => !NON_DATA_DIRS.has(name) && existsSync(join(REPO_ROOT, name)))
const missing = candidates.filter((name) => !whitelist.has(name))
const stale = [...whitelist].filter((name) => !existsSync(join(REPO_ROOT, name)))

if (stale.length > 0) {
  console.warn(`WARN: DIRS 里存在仓库中不存在的目录：${stale.join(', ')}`)
}

if (missing.length > 0) {
  console.error('')
  console.error('FAIL: 上游新增了运行期数据目录，但没有加入 HAP rawfile 白名单')
  console.error(`  缺失：${missing.join(', ')}`)
  console.error('')
  console.error('  这些目录不会被打进 HAP。用户升级后可能出现：')
  console.error('   · 启动卡死（GetRawFileList 失败，如 skycultures/potawatomi）')
  console.error('   · 天空全黑、夜间无星（如 atmosphere/）')
  console.error('')
  console.error('  修复：把缺失目录加入 scripts/sync-ohos-resources.sh 的 DIRS，')
  console.error('        并在该文件的注释里说明用途；纯非数据目录请加入本脚本 NON_DATA_DIRS。')
  process.exit(1)
}

console.log(`OK: 上游 ${candidates.length} 个数据目录均已进 rawfile 白名单（${candidates.join(', ')}）`)
