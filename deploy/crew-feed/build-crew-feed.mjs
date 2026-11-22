#!/usr/bin/env node
// 构建星象仪空间站在轨航天员中文化静态源（/v1/spaceflight/crew.json + manifest.json）。
// 数据来源：本地镜像 /srv/tle-mirror/v1/catalogs/spaceflight/people-in-space.json（零重复抓上游）；
// 中文名优先取维基百科权威中文词条，未命中词条时调用服务器 DeepSeek AI 一次性翻译并永久缓存到
// /var/lib/skyinstrument/crew-zh-cache.json，后续刷新零额外 Token 消耗。

import { createHash, randomUUID } from 'node:crypto'
import { mkdir, open, readFile, rename, rm } from 'node:fs/promises'
import { basename, dirname, join } from 'node:path'

const COUNTRY_ZH = {
  cn: '中国', china: '中国',
  us: '美国', 'united states': '美国', usa: '美国',
  ru: '俄罗斯', russia: '俄罗斯', 'russian federation': '俄罗斯',
  ca: '加拿大', canada: '加拿大',
  jp: '日本', japan: '日本',
  de: '德国', germany: '德国',
  fr: '法国', france: '法国',
  it: '意大利', italy: '意大利',
  gb: '英国', 'united kingdom': '英国', uk: '英国',
  in: '印度', india: '印度',
  ae: '阿联酋', 'united arab emirates': '阿联酋', uae: '阿联酋',
  sa: '沙特阿拉伯', 'saudi arabia': '沙特阿拉伯',
  se: '瑞典', sweden: '瑞典',
  dk: '丹麦', denmark: '丹麦',
  by: '白俄罗斯', belarus: '白俄罗斯',
  pl: '波兰', poland: '波兰',
  hu: '匈牙利', hungary: '匈牙利',
  pk: '巴基斯坦', pakistan: '巴基斯坦',
  kz: '哈萨克斯坦', kazakhstan: '哈萨克斯坦',
  tr: '土耳其', turkey: '土耳其', 'türkiye': '土耳其',
  es: '西班牙', spain: '西班牙',
  nl: '荷兰', netherlands: '荷兰',
  be: '比利时', belgium: '比利时',
}

const AGENCY_ZH = {
  cmsa: '中国载人航天',
  cnsa: '中国国家航天局',
  nasa: '美国航天局',
  roscosmos: '俄罗斯航天局',
  csa: '加拿大航天局',
  esa: '欧洲航天局',
  jaxa: '日本宇宙航空研究开发机构',
  isro: '印度空间研究组织',
  mbrsc: '阿联酋航天中心',
  ssa: '沙特航天局',
  axiom: '公理航天',
  spacex: '太空探索技术公司',
}

const POSITION_ZH = {
  commander: '指令长',
  'flight engineer': '飞行工程师',
  pilot: '驾驶员',
  'payload specialist': '载荷专家',
  'mission specialist': '任务专家',
  'spaceflight participant': '太空飞行参与者',
}

function hasCjk(text) {
  return typeof text === 'string' && /[\u4e00-\u9fff]/.test(text)
}

function cleanZhName(raw) {
  if (typeof raw !== 'string') return ''
  const cleaned = raw
    .replace(/\s*[（(][^）)]*[）)]\s*$/g, '')
    .replace(/[·•・\.\s]+/g, (m) => (m.includes('·') || m.includes('•') || m.includes('・') ? '·' : ''))
    .trim()
  if (!hasCjk(cleaned) || cleaned.length > 24 || /https?:\/\/|[<>{}[\]]/.test(cleaned)) {
    return ''
  }
  return cleaned
}

function translateCountryZh(country, flagCode) {
  const code = String(flagCode || '').trim().toLowerCase()
  const key = String(country || '').trim().toLowerCase()
  return COUNTRY_ZH[code] || COUNTRY_ZH[key] || String(country || '').trim()
}

function translateAgencyZh(agency) {
  const raw = String(agency || '').trim()
  if (!raw) return ''
  return AGENCY_ZH[raw.toLowerCase()] || raw
}

function translatePositionZh(position) {
  const raw = String(position || '').trim()
  if (!raw) return ''
  return POSITION_ZH[raw.toLowerCase()] || raw
}

function translateSpacecraftZh(spacecraft) {
  const raw = String(spacecraft || '').trim()
  if (!raw) return ''
  const sz = /^Shenzhou\s+(\d+)$/i.exec(raw)
  if (sz) return `神舟${sz[1]}号`
  const soyuz = /^Soyuz\s+(.+)$/i.exec(raw)
  if (soyuz) return `联盟 ${soyuz[1]}`
  const crewDragon = /^(Crew-\d+)\s+Dragon$/i.exec(raw)
  if (crewDragon) return `龙飞船 ${crewDragon[1]}`
  if (/^Dragon\s+/i.test(raw)) return `龙飞船 ${raw.slice(7)}`
  if (/starliner/i.test(raw)) return `星际客机 ${raw.replace(/starliner/i, '').trim()}`.trim()
  return raw
}

async function parseKeyValueConf(filePath) {
  const conf = {}
  try {
    const raw = await readFile(filePath, 'utf8')
    for (const line of raw.split('\n')) {
      const trimmed = line.trim()
      if (!trimmed || trimmed.startsWith('#')) continue
      const idx = trimmed.indexOf('=')
      if (idx <= 0) continue
      const key = trimmed.slice(0, idx).trim()
      let val = trimmed.slice(idx + 1).trim()
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1)
      }
      conf[key] = val
    }
  } catch {}
  return conf
}

async function lookupZhWikiNames(people) {
  const titleToKey = new Map()
  for (const p of people) {
    const u = typeof p.url === 'string' ? p.url : ''
    const idx = u.indexOf('/wiki/')
    if (idx < 0) continue
    try {
      const title = decodeURIComponent(u.slice(idx + 6)).replaceAll('_', ' ')
      if (title) titleToKey.set(title, p)
    } catch {}
  }
  const result = new Map()
  if (titleToKey.size === 0) return result
  try {
    const titles = [...titleToKey.keys()].join('|')
    const url = `https://en.wikipedia.org/w/api.php?action=query&prop=langlinks&lllang=zh&lllimit=50&format=json&titles=${encodeURIComponent(titles)}`
    const resp = await fetch(url, {
      signal: AbortSignal.timeout(12000),
      headers: { 'user-agent': 'SkyInstrumentMirror/1.0 (+https://skyinstrument.cn)' },
    })
    if (!resp.ok) return result
    const data = await resp.json()
    const pages = data?.query?.pages || {}
    for (const page of Object.values(pages)) {
      const title = page?.title
      const zhRaw = page?.langlinks?.[0]?.['*']
      const zh = cleanZhName(zhRaw)
      if (title && zh && titleToKey.has(title)) {
        const person = titleToKey.get(title)
        result.set(`${person.name}|${person.country}`, zh)
      }
    }
  } catch (err) {
    console.warn(`[crew-feed] zh-wiki lookup skipped: ${err?.message || err}`)
  }
  return result
}

async function translateBatchWithLlm(unresolved, conf) {
  const out = new Map()
  if (unresolved.length === 0 || !conf.LLM_KEY) return out
  const endpoint = conf.LLM_ENDPOINT || 'https://api.deepseek.com/chat/completions'
  const model = conf.LLM_MODEL || 'deepseek-chat'
  const items = unresolved.map((p) => ({
    name: p.name,
    country: p.country,
    agency: p.agency || '',
    spacecraft: p.spacecraft || '',
  }))
  const prompt =
    '请把以下在轨航天员信息翻译为简体中文标准译名（遵循中国载人航天官方及新华社规范译名；外国姓名用中间点“·”连接，不要保留英文）。\n' +
    '待翻译列表：\n' + JSON.stringify(items) + '\n\n' +
    '只返回一个 JSON 对象，格式为 {"translations":[{"name":"原英文名","nameZh":"标准中文姓名","agencyZh":"中文机构名","spacecraftZh":"中文飞船名"}]}，不要输出任何解释或代码块标记。'
  try {
    const resp = await fetch(endpoint, {
      method: 'POST',
      signal: AbortSignal.timeout(25000),
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${conf.LLM_KEY}`,
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: '你是专业的航天科技与新闻翻译专家，只输出严格 JSON。' },
          { role: 'user', content: prompt },
        ],
        temperature: 0.1,
        max_tokens: 800,
        stream: false,
      }),
    })
    if (!resp.ok) {
      console.warn(`[crew-feed] LLM HTTP ${resp.status}`)
      return out
    }
    const data = await resp.json()
    const content = String(data?.choices?.[0]?.message?.content || '').trim()
    const stripped = content.replace(/^```(?:json)?|```$/gm, '').trim()
    const match = stripped.match(/\{[\s\S]*\}/)
    if (!match) return out
    const parsed = JSON.parse(match[0])
    const list = Array.isArray(parsed?.translations) ? parsed.translations : []
    for (const row of list) {
      const name = typeof row?.name === 'string' ? row.name.trim() : ''
      const nameZh = cleanZhName(row?.nameZh)
      if (!name || !nameZh) continue
      const matchPerson = unresolved.find((p) => p.name === name)
      if (!matchPerson) continue
      out.set(`${matchPerson.name}|${matchPerson.country}`, {
        nameZh,
        agencyZh: hasCjk(row?.agencyZh) && row.agencyZh.length <= 24 ? row.agencyZh.trim() : '',
        spacecraftZh: hasCjk(row?.spacecraftZh) && row.spacecraftZh.length <= 24 ? row.spacecraftZh.trim() : '',
      })
    }
  } catch (err) {
    console.warn(`[crew-feed] LLM translation skipped: ${err?.message || err}`)
  }
  return out
}

async function atomicWrite(destination, text, mode = 0o644) {
  await mkdir(dirname(destination), { recursive: true })
  const tmp = join(dirname(destination), `.${basename(destination)}.${randomUUID()}.tmp`)
  try {
    const handle = await open(tmp, 'wx', mode)
    try {
      await handle.writeFile(text, 'utf8')
      await handle.sync()
    } finally {
      await handle.close()
    }
    await rename(tmp, destination)
  } finally {
    await rm(tmp, { force: true })
  }
}

function sha256Hex(bufferOrText) {
  return createHash('sha256').update(bufferOrText).digest('hex')
}

function parseArgs(argv) {
  const args = {
    input: '/srv/tle-mirror/v1/catalogs/spaceflight/people-in-space.json',
    out: '/srv/tle-mirror/v1/spaceflight',
    cache: '/var/lib/skyinstrument/crew-zh-cache.json',
    auditConf: '/etc/skyinstrument/audit.conf',
    dryRun: false,
  }
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i]
    if (k === '--input') args.input = argv[++i]
    else if (k === '--out') args.out = argv[++i]
    else if (k === '--cache') args.cache = argv[++i]
    else if (k === '--audit-conf') args.auditConf = argv[++i]
    else if (k === '--dry-run') args.dryRun = true
  }
  return args
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  const rawDoc = JSON.parse(await readFile(args.input, 'utf8'))
  if (!rawDoc || typeof rawDoc !== 'object' || !Array.isArray(rawDoc.people)) {
    throw new Error('invalid input people-in-space.json')
  }

  let cache = {}
  try {
    const loaded = JSON.parse(await readFile(args.cache, 'utf8'))
    if (loaded && typeof loaded === 'object' && !Array.isArray(loaded)) cache = loaded
  } catch {}

  const needLookup = []
  for (const p of rawDoc.people) {
    if (!p || typeof p.name !== 'string' || !p.name.trim()) continue
    const key = `${p.name.trim()}|${String(p.country || '').trim()}`
    if (!cleanZhName(cache[key]?.nameZh)) {
      needLookup.push(p)
    }
  }

  let cacheDirty = false
  if (needLookup.length > 0) {
    const wikiMap = await lookupZhWikiNames(needLookup)
    const stillUnresolved = []
    for (const p of needLookup) {
      const key = `${p.name.trim()}|${String(p.country || '').trim()}`
      if (wikiMap.has(key)) {
        cache[key] = {
          nameZh: wikiMap.get(key),
          source: 'zh-wikipedia',
          updatedAt: new Date().toISOString(),
        }
        cacheDirty = true
      } else {
        stillUnresolved.push(p)
      }
    }
    if (stillUnresolved.length > 0) {
      const conf = await parseKeyValueConf(args.auditConf)
      const aiMap = await translateBatchWithLlm(stillUnresolved, conf)
      for (const p of stillUnresolved) {
        const key = `${p.name.trim()}|${String(p.country || '').trim()}`
        const aiEntry = aiMap.get(key)
        if (aiEntry && cleanZhName(aiEntry.nameZh)) {
          cache[key] = {
            nameZh: cleanZhName(aiEntry.nameZh),
            agencyZh: aiEntry.agencyZh || '',
            spacecraftZh: aiEntry.spacecraftZh || '',
            source: 'deepseek-ai',
            updatedAt: new Date().toISOString(),
          }
          cacheDirty = true
        }
      }
    }
  }

  const enrichedPeople = rawDoc.people.map((p, index) => {
    const name = String(p.name || '').trim()
    const country = String(p.country || '').trim()
    const flagCode = String(p.flag_code || '').trim().toLowerCase()
    const agency = String(p.agency || '').trim()
    const position = String(p.position || '').trim()
    const spacecraft = String(p.spacecraft || '').trim()
    const key = `${name}|${country}`
    const cached = cache[key] || {}
    const nameZh = cleanZhName(cached.nameZh) || name
    const agencyZh = translateAgencyZh(agency) || cached.agencyZh || agency
    const spacecraftZh = translateSpacecraftZh(spacecraft) || cached.spacecraftZh || spacecraft
    return {
      id: typeof p.id === 'number' && Number.isFinite(p.id) ? p.id : index + 1,
      name,
      nameZh,
      country,
      countryZh: translateCountryZh(country, flagCode),
      flag_code: flagCode,
      agency,
      agencyZh,
      position,
      positionZh: translatePositionZh(position),
      spacecraft,
      spacecraftZh,
      iss: p.iss === true,
      launched: typeof p.launched === 'number' && Number.isFinite(p.launched) ? p.launched : 0,
    }
  })

  const outputDoc = {
    schemaVersion: 1,
    number: enrichedPeople.length,
    iss_expedition: typeof rawDoc.iss_expedition === 'number' ? rawDoc.iss_expedition : 0,
    people: enrichedPeople,
  }
  const payloadText = `${JSON.stringify(outputDoc, null, 2)}\n`
  const payloadBuf = Buffer.from(payloadText, 'utf8')
  const payloadSha = sha256Hex(payloadBuf)

  if (args.dryRun) {
    console.log(payloadText)
    return
  }

  if (cacheDirty) {
    await atomicWrite(args.cache, `${JSON.stringify(cache, null, 2)}\n`, 0o600)
  }

  const crewPath = join(args.out, 'crew.json')
  const manifestPath = join(args.out, 'manifest.json')
  let previousManifest = null
  try {
    previousManifest = JSON.parse(await readFile(manifestPath, 'utf8'))
  } catch {}

  if (previousManifest?.sha256 === payloadSha && previousManifest?.bytes === payloadBuf.length) {
    console.log(`crew-feed unchanged (${enrichedPeople.length} astronauts, sha256=${payloadSha.slice(0, 12)})`)
    return
  }

  await atomicWrite(crewPath, payloadText, 0o644)
  const manifest = {
    schemaVersion: 1,
    updatedAt: new Date().toISOString(),
    feedPath: '/v1/spaceflight/crew.json',
    bytes: payloadBuf.length,
    sha256: payloadSha,
    count: enrichedPeople.length,
  }
  await atomicWrite(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, 0o644)
  console.log(`crew-feed published (${enrichedPeople.length} astronauts, sha256=${payloadSha.slice(0, 12)})`)
}

main().catch((err) => {
  console.error(`[crew-feed] fatal: ${err?.message || err}`)
  process.exit(1)
})
