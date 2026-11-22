import test from 'node:test'
import assert from 'node:assert/strict'
import {
  backgroundAlpha,
  boolAttr,
  evaluateExpectations,
  flattenLayout,
  hasExpectation,
  nodeMatches,
  parseArgs,
  parseBounds,
  parseOpacity,
  selectNodes,
  summarizeRoot
} from './ohos-ui-dump.mjs'

const layout = {
  attributes: {
    type: 'root',
    bundleName: 'com.joinother.skyinstrument',
    abilityName: 'QAbility',
    bounds: '[0,0][100,200]'
  },
  children: [
    {
      attributes: {
        type: 'Column', id: 'map-app-mode-route', bounds: '[0,0][50,40]',
        visible: 'true', enabled: 'true', opacity: '1.000000',
        backgroundColor: '#266BA3D6'
      },
      children: []
    },
    {
      attributes: {
        type: 'Slider', id: 'star-brightness', bounds: '[0,50][90,70]',
        visible: 'true', enabled: 'false', opacity: '0.450000',
        backgroundColor: '#00000000'
      },
      children: []
    },
    {
      attributes: {
        type: 'Text', text: '推荐「chinese」', originalText: '推荐「chinese」',
        bounds: '[10,80][90,100]', visible: 'true', enabled: 'true',
        opacity: '1.000000', backgroundColor: '#D10F141E'
      },
      children: []
    }
  ]
}

test('attribute parsers handle uitest string values', () => {
  assert.deepEqual(parseBounds('[59,1567][626,1798]'), [59, 1567, 626, 1798])
  assert.equal(parseBounds('[0,0][0,0]')[2], 0)
  assert.equal(parseBounds(''), null)
  assert.equal(boolAttr('true'), true)
  assert.equal(boolAttr('false'), false)
  assert.equal(boolAttr(''), false)
  assert.equal(parseOpacity('0.450000'), 0.45)
  assert.ok(Number.isNaN(parseOpacity('')))
  assert.ok(Math.abs(backgroundAlpha('#D10F141E') - 0.819607843) < 0.000001)
  assert.ok(Number.isNaN(backgroundAlpha('#000000')))
})

test('flattenLayout preserves order, depth and ancestor chain', () => {
  const nodes = flattenLayout(layout)
  assert.equal(nodes.length, 4)
  assert.equal(nodes[0].depth, 0)
  assert.equal(nodes[0].attributes.bundleName, 'com.joinother.skyinstrument')
  assert.equal(nodes[1].depth, 1)
  assert.equal(nodes[1].parents.length, 1)
  assert.equal(nodes[1].parents[0].type, 'root')
  assert.equal(nodes[3].attributes.text, '推荐「chinese」')
})

test('summarizeRoot finds bundle info on an extra wrapper level', () => {
  const nested = {
    attributes: { type: 'root', bounds: '[0,0][100,200]' },
    children: [{
      attributes: {
        type: 'root', bundleName: 'com.joinother.skyinstrument',
        abilityName: 'QAbility', pagePath: 'pages/ApplicationRoot'
      },
      children: []
    }]
  }
  const root = summarizeRoot(nested)
  assert.equal(root.bundleName, 'com.joinother.skyinstrument')
  assert.equal(root.abilityName, 'QAbility')
})

test('selectors match id, type, exact text and substring', () => {
  const nodes = flattenLayout(layout)
  assert.equal(selectNodes(nodes, { id: 'star-brightness' }).length, 1)
  assert.equal(selectNodes(nodes, { type: 'Text' }).length, 1)
  assert.equal(selectNodes(nodes, { text: '推荐「chinese」' }).length, 1)
  assert.equal(selectNodes(nodes, { textContains: 'chinese' }).length, 1)
  assert.equal(selectNodes(nodes, { textContains: '不存在' }).length, 0)
  assert.equal(nodeMatches({ id: 'a', text: 'x' }, { id: 'a', text: 'y' }), false)
})

test('expectations pass for present, enabled, opacity, background alpha and bounds', () => {
  const route = selectNodes(flattenLayout(layout), { id: 'map-app-mode-route' })
  assert.equal(hasExpectation({ expectEnabled: true }), true)
  assert.equal(evaluateExpectations(route, { expectPresent: true, first: true }).ok, true)
  assert.equal(evaluateExpectations(route, { expectVisible: true, expectEnabled: true }).ok, true)
  assert.equal(evaluateExpectations(route, { expectOpacity: 1, expectBounds: [0, 0, 50, 40] }).ok, true)
  assert.equal(evaluateExpectations(route, { expectBackground: '#266ba3d6' }).ok, true)

  const text = selectNodes(flattenLayout(layout), { type: 'Text' })
  assert.equal(evaluateExpectations(text, { expectBgAlpha: 0.82 }).ok, true)
  assert.equal(hasExpectation({ expectOpacity: 0.45 }), true)
})

test('expectations report disabled state and failures precisely', () => {
  const slider = selectNodes(flattenLayout(layout), { id: 'star-brightness' })
  assert.equal(evaluateExpectations(slider, { expectDisabled: true, first: true }).ok, true)
  const enabledFailure = evaluateExpectations(slider, { expectEnabled: true })
  assert.equal(enabledFailure.ok, false)
  assert.match(enabledFailure.failures.join('\n'), /expect-enabled/)

  const opacityFailure = evaluateExpectations(slider, { expectOpacity: 0.5 })
  assert.equal(opacityFailure.ok, false)
  assert.match(opacityFailure.failures.join('\n'), /expect-opacity/)

  const absentFailure = evaluateExpectations(slider, { expectAbsent: true })
  assert.equal(absentFailure.ok, false)
  assert.match(absentFailure.failures.join('\n'), /expect-absent/)

  const empty = evaluateExpectations([], { expectPresent: true })
  assert.equal(empty.ok, false)
  assert.match(empty.failures.join('\n'), /expect-present/)
})

test('ambiguous matches require --first for state assertions', () => {
  const nodes = flattenLayout(layout)
  const buttons = selectNodes(nodes, { type: 'Column' })
  const ambiguous = evaluateExpectations(buttons.concat(buttons), { expectEnabled: true })
  assert.equal(ambiguous.ok, false)
  assert.match(ambiguous.failures.join('\n'), /收窄选择器|--first/)
  const first = evaluateExpectations(buttons.concat(buttons), { expectEnabled: true, first: true })
  assert.equal(first.ok, true)
})

test('parseArgs validates selectors and expectation combinations', () => {
  const parsed = parseArgs(['--device', 'dev', '--id', 'share', '--expect-enabled', '--no-save'])
  assert.equal(parsed.device, 'dev')
  assert.equal(parsed.id, 'share')
  assert.equal(parsed.expectEnabled, true)
  assert.equal(parsed.save, false)

  assert.throws(() => parseArgs(['--all', '--id', 'share']), /--all/)
  assert.throws(() => parseArgs(['--expect-present']), /断言需要至少一个选择器/)
  assert.throws(() => parseArgs(['--expect-present', '--expect-absent', '--id', 'x']), /不能同时使用/)
  assert.throws(() => parseArgs(['--expect-visible', '--expect-hidden', '--id', 'x']), /不能同时使用/)
  assert.throws(() => parseArgs(['--expect-enabled', '--expect-disabled', '--id', 'x']), /不能同时使用/)
  assert.throws(() => parseArgs(['--expect-bounds', '1,2,3', '--id', 'x']), /x1,y1,x2,y2/)
  assert.throws(() => parseArgs(['--dump-only', '--id', 'x']), /--dump-only/)
})
