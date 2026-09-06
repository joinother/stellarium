import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { createHash } from 'node:crypto';

const directory = new URL('../harmonyos/ets-source/pages/', import.meta.url);
const source = name => readFileSync(new URL(name + '.ets', directory), 'utf8');
const plain = text => stripTypeScriptTypes(text.replace(/^import .*\n/gm, '').replace(/export /g, ''));
const procedural = new Function(plain(source('ProceduralDetailModel')) + ';return { renderProceduralModel, proceduralParticles };')();
const geometry = new Function(plain(source('DetailModelGeometry')) + ';return { modelIdentity, modelDrag };')();
const render = new Function('renderProceduralModel', plain(source('DetailModelRasterizer')) + ';return renderDetailModel;')(procedural.renderProceduralModel);

export function fixtures() {
  const texture = new Uint8Array(16 * 10 * 4);
  const ring = new Uint8Array(32 * 3 * 4);
  for (let index = 0; index < texture.length; index++) texture[index] = (index * 31 + 9) % 256;
  for (let index = 0; index < ring.length; index++) ring[index] = (index * 13 + 21) % 256;
  const resources = { texture: texture.buffer, textureWidth: 14, textureHeight: 10, textureStride: 64,
    ringTexture: ring.buffer, ringWidth: 32, ringHeight: 3,
    ringSpec: { innerRadius: 1.2, outerRadius: 2.3, opacity: 0.8 }, kind: '', temperature: 4300, particles: [] };
  const frame = { renderSize: 320, scale: 1, transform: geometry.modelDrag(geometry.modelIdentity(), 36, -64),
    lighting: { viewToBody: geometry.modelIdentity(), sunDirectionBody: [0.6, 0, 0.8], emissive: false } };
  const cases = [
    ['ring-320', resources, frame],
    ['sphere-640', { ...resources, ringSpec: undefined }, { ...frame, renderSize: 640 }],
    ['emissive-224', { ...resources, ringSpec: undefined }, { ...frame, renderSize: 224, lighting: { ...frame.lighting, emissive: true } }],
    ['unlit', { ...resources, ringSpec: undefined }, { ...frame, lighting: undefined }]
  ];
  for (const kind of ['star', 'quasar', 'pulsar', 'globular-cluster', 'open-cluster']) {
    cases.push([kind, { ...resources, kind, particles: procedural.proceduralParticles(kind, 'fixture') }, frame]);
  }
  return cases;
}

test('worker renderer matches original pixel fixtures without reducing resolution', () => {
  const expected = JSON.parse(readFileSync(new URL('./fixtures/detail-model-render-hashes.json', import.meta.url), 'utf8'));
  for (const [name, resources, frame] of fixtures()) {
    const pixels = render(resources, frame);
    assert.equal(pixels.byteLength, frame.renderSize ** 2 * 4);
    assert.equal(createHash('sha256').update(new Uint8Array(pixels)).digest('hex'), expected[name], name);
  }
});

function clientHarness() {
  const threads = [];
  class ThreadWorker {
    constructor(path) { this.path = path; this.messages = []; threads.push(this); }
    postMessage(message) { this.messages.push(message); }
    terminate() { this.terminated = true; }
    respond(data = { pixels: new ArrayBuffer(4), computeMs: 12 }) { this.onmessage({ data }); }
  }
  const Client = new Function('worker', plain(source('DetailModelRenderClient')) + ';return DetailModelRenderClient;')({ ThreadWorker });
  return { client: new Client(), threads };
}

test('only first frame copies textures, subsequent frames reuse one worker', async () => {
  const { client, threads } = clientHarness();
  const [, resources, frame] = fixtures()[0];
  const first = client.render(resources, frame);
  assert.equal(threads.length, 1);
  assert.equal(threads[0].messages[0].resources, resources);
  await assert.rejects(client.render(resources, frame), /already in flight/);
  threads[0].respond();
  assert.equal((await first).computeMs, 12);
  const second = client.render(resources, frame);
  assert.equal(threads.length, 1);
  assert.equal(threads[0].messages[1].resources, undefined);
  threads[0].respond();
  await second;
  client.dispose();
  assert.ok(threads[0].terminated);
});

test('disposal cancels pending work and stale worker cannot publish to a new frame', async () => {
  const { client, threads } = clientHarness();
  const [, resources, frame] = fixtures()[0];
  const first = client.render(resources, frame);
  client.dispose();
  await assert.rejects(first, /cancelled/);
  const next = client.render(resources, frame);
  threads[0].respond({ error: 'old target' });
  threads[1].respond();
  assert.equal((await next).computeMs, 12);
  client.dispose();
});

test('worker errors release pending state and allow an explicit retry', async () => {
  for (const failure of ['onerror', 'onmessageerror', 'onexit', 'response']) {
    const { client, threads } = clientHarness();
    const [, resources, frame] = fixtures()[0];
    const pending = client.render(resources, frame);
    if (failure === 'response') threads[0].respond({ error: 'decode failed' });
    else threads[0][failure]({ message: 'worker failed' });
    await assert.rejects(pending);
    assert.ok(threads[0].terminated);
    const retry = client.render(resources, frame);
    assert.equal(threads.length, 2);
    threads[1].respond();
    await retry;
    client.dispose();
  }
});

test('background suspends watchdog without losing the frame or creating another worker', async () => {
  const { client, threads } = clientHarness();
  const [, resources, frame] = fixtures()[0];
  const pending = client.render(resources, frame);
  client.setSuspended(true);
  assert.equal(client.timeout, 0);
  assert.equal(client.pulseTimer, 0);
  client.setSuspended(false);
  assert.notEqual(client.timeout, 0);
  assert.notEqual(client.pulseTimer, 0);
  assert.equal(threads.length, 1);
  threads[0].respond();
  await pending;
  assert.equal(client.timeout, 0);
  assert.equal(client.pulseTimer, 0);
  client.dispose();
});

test('UI submits snapshots, never executes pixel loops; selection generation guards completed frames', () => {
  const ui = source('MainWindowNativeNode');
  const renderMethod = ui.slice(ui.indexOf('  private renderObjectInspectorModel(highQuality:'), ui.indexOf('  private objectInspectorModelReady()'));
  assert.doesNotMatch(renderMethod, /for \(|renderProceduralModel\(|renderDetailModel\(/);
  assert.match(renderMethod, /render\(resources, frame\)/);
  assert.equal((renderMethod.match(/generation !== this.objectInspectorModelRenderGeneration/g) ?? []).length, 3);
  assert.match(ui, /objectInspectorModelRenderClient\?\.dispose\(\)/);
  assert.doesNotMatch(ui, /@State private objectInspectorModelRendering/);
});
