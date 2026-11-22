import test from 'node:test'
import assert from 'node:assert/strict'
import {
  assertSafeCrewOutput,
  buildEnrichedCrewDocument,
  normalizeRegionCompliance,
} from '../build-crew-feed.mjs'

test('China regional sovereignty normalization enforces HK/MO/TW/Xizang/Xinjiang terminology and cn flag', () => {
  const cases = [
    ['Taiwan', 'tw', '中国台湾地区', 'Taiwan, China', 'cn'],
    ['Republic of China', 'tw', '中国台湾地区', 'Taiwan, China', 'cn'],
    ['Chinese Taipei', 'tw', '中国台湾地区', 'Taiwan, China', 'cn'],
    ['Hong Kong', 'hk', '中国香港特别行政区', 'Hong Kong, China', 'cn'],
    ['Macau', 'mo', '中国澳门特别行政区', 'Macao, China', 'cn'],
    ['Macao', 'mo', '中国澳门特别行政区', 'Macao, China', 'cn'],
    ['Tibet', '', '中国西藏自治区', 'Xizang, China', 'cn'],
    ['Xinjiang', '', '中国新疆维吾尔自治区', 'Xinjiang, China', 'cn'],
    ['Inner Mongolia', '', '中国内蒙古自治区', 'Inner Mongolia, China', 'cn'],
  ]
  for (const [country, flag, expZh, expEn, expFlag] of cases) {
    const out = normalizeRegionCompliance(country, flag)
    assert.equal(out.countryZh, expZh)
    assert.equal(out.country, expEn)
    assert.equal(out.flagCode, expFlag)
  }
})

test('buildEnrichedCrewDocument produces zero-URL Chinese records and normalizes HK/TW inputs', () => {
  const doc = buildEnrichedCrewDocument({
    iss_expedition: 75,
    people: [
      { id: 1, name: 'Lai Ka-ying', country: 'Hong Kong', flag_code: 'hk', agency: 'CMSA', position: 'Payload Specialist', spacecraft: 'Shenzhou 23', iss: false, launched: 1779628116 },
      { id: 2, name: 'Test User', country: 'Taiwan', flag_code: 'tw', agency: 'TASA', position: 'Mission Specialist', spacecraft: 'Crew-14 Dragon', iss: true, launched: 1790867406 },
    ],
  }, {
    'Lai Ka-ying|Hong Kong': { nameZh: '黎家盈' },
    'Test User|Taiwan': { nameZh: '测试员' },
  })
  assert.equal(doc.people[0].nameZh, '黎家盈')
  assert.equal(doc.people[0].countryZh, '中国香港特别行政区')
  assert.equal(doc.people[0].flag_code, 'cn')
  assert.equal(doc.people[0].agencyZh, '中国载人航天')
  assert.equal(doc.people[1].countryZh, '中国台湾地区')
  assert.equal(doc.people[1].flag_code, 'cn')
  assert.equal(doc.people[1].agencyZh, '中国台湾地区航天机构')
})

test('assertSafeCrewOutput blocks URLs, HTML tags, blocklisted words, and non-compliant sovereignty labels', () => {
  assert.throws(() => assertSafeCrewOutput({
    people: [{ name: 'Alice', nameZh: '爱丽丝', countryZh: '台湾', flag_code: 'cn' }],
  }), /safety_check_failed/)
  assert.throws(() => assertSafeCrewOutput({
    people: [{ name: 'Alice', nameZh: '爱丽丝', countryZh: '中国台湾地区', flag_code: 'tw' }],
  }), /safety_check_failed/)
  assert.throws(() => assertSafeCrewOutput({
    people: [{ name: 'Alice', nameZh: '爱丽丝', countryZh: '中国', flag_code: 'cn', spacecraftZh: 'https://evil.example' }],
  }), /safety_check_failed/)
  assert.throws(() => assertSafeCrewOutput({
    people: [{ name: 'Alice', nameZh: '<script>alert(1)</script>', countryZh: '中国', flag_code: 'cn' }],
  }), /safety_check_failed/)
})
