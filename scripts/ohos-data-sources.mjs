import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname);
const registryPath = resolve(root, 'data/ohos/network-sources.json');

export async function loadOhosSourceRegistry() {
  return JSON.parse(await readFile(registryPath, 'utf8'));
}

export function getSource(registry, sourceId) {
  const source = registry.sources.find((candidate) => candidate.id === sourceId);
  if (!source) throw new Error(`未注册的数据源：${sourceId}`);
  return source;
}

export function resolveSource(source, mode, { mirrorBaseUrl = '', sourceRoot = root } = {}) {
  if (mode === 'local') return { ...source, resolvedMode: mode, localFile: resolve(sourceRoot, source.localPath) };
  if (mode === 'mirror') {
    if (!mirrorBaseUrl) throw new Error('镜像模式必须提供 --mirror-base-url 或 OHOS_MIRROR_BASE_URL');
    return { ...source, resolvedMode: mode, url: new URL(source.mirrorPath, `${mirrorBaseUrl.replace(/\/$/, '')}/`).toString() };
  }
  if (mode === 'upstream') return { ...source, resolvedMode: mode, url: source.upstreamUrl };
  throw new Error(`未知数据源模式：${mode}`);
}

export function sourceIdsForPrefix(registry, prefix) {
  return registry.sources.filter((source) => source.id.startsWith(prefix)).map((source) => source.id);
}
