import test from 'node:test'
import assert from 'node:assert/strict'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import path from 'node:path'

const ROOT = path.resolve(new URL('..', import.meta.url).pathname)

function read(rel) {
  return readFileSync(path.join(ROOT, rel), 'utf8')
}

function listSubdirs(rel) {
  const base = path.join(ROOT, rel)
  return readdirSync(base)
    .filter((name) => statSync(path.join(base, name)).isDirectory())
    .sort()
}

function walkEts(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const full = path.join(dir, name)
    if (statSync(full).isDirectory()) {
      walkEts(full, out)
    } else if (name.endsWith('.ets') || name.endsWith('.ts')) {
      out.push(full)
    }
  }
  return out
}

const skyCultureStoriesSrc = read('harmonyos/ets-source/common/derive/SkyCultureStoriesZh.ts')
const landscapeStoriesSrc = read('harmonyos/ets-source/common/derive/LandscapeStoriesZh.ts')
const skyCultureTabSrc = read('harmonyos/ets-source/panels/skyculture/SkyCultureViewTab.ets')
const layerTabsSrc = read('harmonyos/ets-source/panels/layers/LayerViewTabs.ets')
const mediaCtlSrc = read('harmonyos/ets-source/capability/ObjectInspectorMediaController.ets')
const mainViewCpp = read('src/StelMainView.cpp')

function extractKeys(tsSource, exportName) {
  const start = tsSource.indexOf(`export const ${exportName}`)
  assert.ok(start >= 0, `missing export ${exportName}`)
  const openBrace = tsSource.indexOf('{', tsSource.indexOf('=', start))
  const end = tsSource.indexOf('\n}\n', openBrace)
  assert.ok(end > openBrace, `could not locate end of ${exportName}`)
  const body = tsSource.slice(openBrace + 1, end)
  const keys = []
  const re = /^  (?:'([^']+)'|([a-zA-Z0-9_-]+)):\s*\{/gm
  let m
  while ((m = re.exec(body)) !== null) {
    keys.push(m[1] ?? m[2])
  }
  return keys.sort()
}

test('all 64 bundled sky cultures have curated Chinese stories', () => {
  const bundled = listSubdirs('skycultures')
  assert.equal(bundled.length, 64, `expected 64 skycultures, found ${bundled.length}`)
  const covered = extractKeys(skyCultureStoriesSrc, 'SKY_CULTURE_STORIES_ZH')
  assert.deepEqual(covered, bundled)
})

test('all 16 bundled landscapes have curated Chinese stories', () => {
  const bundled = listSubdirs('landscapes')
  assert.equal(bundled.length, 16, `expected 16 landscapes, found ${bundled.length}`)
  const covered = extractKeys(landscapeStoriesSrc, 'LANDSCAPE_STORIES_ZH')
  assert.deepEqual(covered, bundled)
})

test('Chinese narratives strictly follow decolonized, egalitarian, shared-future editorial rules', () => {
  const combined = skyCultureStoriesSrc + '\n' + landscapeStoriesSrc
  const bannedPatterns = [
    /发现了/,
    /被发现/,
    /发现新/,
    /欧洲人发现/,
    /西方发现/,
    /与我们不同/,
    /我们和他们/,
    /原始部落/,
    /未开化/,
    /野蛮/,
    /落后民族/,
    /土著奇观/,
    /异域风情/
  ]
  for (const pattern of bannedPatterns) {
    assert.doesNotMatch(combined, pattern, `found banned phrase matching ${pattern}`)
  }
  assert.match(skyCultureStoriesSrc, /人类命运共同体/)
  assert.match(landscapeStoriesSrc, /人类命运共同体/)
})

test('no uncertified worldmap.jpg raster or territory border polygon map exists anywhere in ets-source', () => {
  const files = walkEts(path.join(ROOT, 'harmonyos/ets-source'))
  for (const file of files) {
    const content = readFileSync(file, 'utf8')
    assert.doesNotMatch(content, /worldmap\.jpg/, `uncertified worldmap.jpg referenced in ${file}`)
  }
  assert.doesNotMatch(skyCultureTabSrc, /Canvas\(this\.mapContext\)/)
  assert.match(skyCultureTabSrc, /人类共同的星空 · 文化导览/)
  assert.match(skyCultureTabSrc, /SkyCulturePetalMapCard/)
  assert.match(skyCultureTabSrc, /探索文化/)
  assert.match(skyCultureTabSrc, /文化详情/)
  assert.match(skyCultureTabSrc, /显示与标注/)
  assert.match(skyCultureTabSrc, /getSkyCultureStoryZh/)

  const petalCard = read('harmonyos/ets-source/panels/skyculture/SkyCulturePetalMapCard.ets')
  assert.match(petalCard, /MapComponent/)
  assert.match(petalCard, /MapType\.TERRAIN/)
  assert.match(petalCard, /rectifyCoordinate/)
  assert.doesNotMatch(petalCard, /addPolygon/)
  assert.doesNotMatch(petalCard, /worldmap\.jpg/)
})

test('all 674 nebula photos from nebulae/default/textures.json are indexed in C++ and wired to ObjectInspectorMediaController', () => {
  const raw = read('nebulae/default/textures.json').replace(/\t/g, ' ')
  const parsed = JSON.parse(raw)
  assert.ok(Array.isArray(parsed.subTiles) && parsed.subTiles.length >= 674)
  assert.match(mainViewCpp, /ohosNebulaTilesCache\(\)/)
  assert.match(mainViewCpp, /ohosNebulaDetailMediaJson\(/)
  assert.match(mainViewCpp, /raw\.replace\('\\t', ' '\)/)
  assert.match(mainViewCpp, /nebulae\/default\/textures\.json/)
  assert.match(mediaCtlSrc, /selectedDetailMediaKind === 'image' \? 'image' : 'constellation'/)
  assert.match(mediaCtlSrc, /selectedDetailMediaLabel\.length > 0/)
})

test('landscape bridge exposes previewPath and localizedDescription, and LayerLandscapeTab renders story cards', () => {
  assert.match(mainViewCpp, /item\["previewPath"\] = relPreview/)
  assert.match(mainViewCpp, /description\.zh_CN\.utf8/)
  assert.match(mainViewCpp, /item\["localizedDescription"\]/)
  assert.match(layerTabsSrc, /getLandscapeStoryZh/)
  assert.match(layerTabsSrc, /\$rawfile\('stellarium\/' \+ item\.previewPath\)/)
  assert.match(layerTabsSrc, /expandedLandscapeId/)
  assert.match(layerTabsSrc, /展开故事/)
})

test('spacetime sky-culture recommender and scannable typography helpers work accurately', async () => {
  const { stripTypeScriptTypes } = await import('node:module')
  const storiesMod = await import('../harmonyos/ets-source/common/derive/SkyCultureStoriesZh.ts')
  const recSrc = stripTypeScriptTypes(read('harmonyos/ets-source/common/derive/SkyCultureRecommender.ts'))
    .replace(/import\s*\{[^}]*\}\s*from\s*['"]\.\/SkyCultureStoriesZh['"];?/, '')
    .replace(/export\s+function\s+/g, 'function ')
  const mod = new Function('SKY_CULTURE_STORIES_ZH', recSrc + '\nreturn { recommendSkyCultures, splitHighlightTags, splitAiryParagraphs, yearToJulianDay, formatShortEraRange, recommendedYearForCulture };')(storiesMod.SKY_CULTURE_STORIES_ZH)
  const sampleItems = [
    { id: 'modern', name: 'Modern', beginTime: 1922, endTime: 0 },
    { id: 'modern_chinese', name: 'Modern (Chinese)', beginTime: 1922, endTime: 0 },
    { id: 'chinese', name: 'Chinese', beginTime: -200, endTime: 1911 },
    { id: 'chinese_song_dynasty', name: 'Chinese Song', beginTime: 960, endTime: 1279 },
    { id: 'chinese_yuan_dynasty', name: 'Chinese Yuan', beginTime: 1271, endTime: 1368 },
    { id: 'maori', name: 'Maori', beginTime: 1200, endTime: 0 },
    { id: 'egyptian_dendera', name: 'Dendera', beginTime: -100, endTime: 0 }
  ]

  // China + 1100 AD -> Song Dynasty ranks #1
  const songRecs = mod.recommendSkyCultures({
    latitude: 31.3, longitude: 120.6, simulationYear: 1100,
    earthObserver: true, currentCultureId: 'modern', items: sampleItems
  })
  assert.equal(songRecs[0].id, 'chinese_song_dynasty')
  assert.equal(songRecs[0].isEraMatch, true)

  // New Zealand + 2026 -> Maori ranks #1
  const nzRecs = mod.recommendSkyCultures({
    latitude: -41.3, longitude: 174.8, simulationYear: 2026,
    earthObserver: true, currentCultureId: 'modern', items: sampleItems
  })
  assert.equal(nzRecs[0].id, 'maori')
  assert.equal(nzRecs[0].isLocalMatch, true)

  // Off-Earth -> global modern standard
  const marsRecs = mod.recommendSkyCultures({
    latitude: 0, longitude: 0, simulationYear: 2026,
    earthObserver: false, currentCultureId: 'chinese', items: sampleItems
  })
  assert.equal(marsRecs[0].id, 'modern_chinese')

  // Highlight tag pills and airy paragraph splitter
  assert.deepEqual(mod.splitHighlightTags('三垣二十八宿 · 四象与北斗七星 · 观象授时历法传统'), [
    '三垣二十八宿', '四象与北斗七星', '观象授时历法传统'
  ])
  const paras = mod.splitAiryParagraphs('第一句内容介绍背景。第二句内容补充天文观测细节和历法价值，让读者清楚理解。第三句展望人类共同的星空文化遗产与交流互鉴。')
  assert.ok(paras.length >= 2, 'long story should split into airy short paragraphs')

  // Year to JD & era formatting
  assert.ok(mod.yearToJulianDay(2000) > 2451700 && mod.yearToJulianDay(2000) < 2451730)
  assert.ok(mod.yearToJulianDay(-50) < 1721425)
  assert.equal(mod.formatShortEraRange(960, 1279), '960~1279')

  // Non-intrusive toast & jump-to-era wired cleanly
  const hostSrc = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets')
  assert.match(hostSrc, /scheduleSpacetimeCultureSuggest/)
  assert.match(hostSrc, /jumpToSkyCultureYear/)
  assert.match(skyCultureTabSrc, /此时此地推荐/)
  assert.match(skyCultureTabSrc, /阅读文化故事/)
  assert.match(skyCultureTabSrc, /时空变更时推荐匹配文化/)
})
