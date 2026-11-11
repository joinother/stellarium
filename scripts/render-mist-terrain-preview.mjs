import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const prefix = resolve(process.argv[2] ?? '/tmp/stellar-mist-mesh');
const temporary = mkdtempSync(join(tmpdir(), 'mist-mesh-preview-'));
try {
  const executable = join(temporary, 'terrain-test');
  execFileSync(process.env.CXX ?? 'clang++', ['-std=c++17', '-O2', '-I', join(root, 'src/core/modules'),
    join(root, 'scripts/test-mist-terrain.cpp'), '-o', executable], { stdio: 'inherit' });
  execFileSync(executable, [prefix], { stdio: 'inherit' });
  for (const fov of [75, 30, 12, 'nadir210', 'zenith210', 'nadir210-night']) {
    const source = prefix + '-' + fov + '.ppm';
    if (process.platform === 'darwin') {
      const output = prefix + '-' + fov + '.png';
      execFileSync('sips', ['-s', 'format', 'png', source, '--out', output], { stdio: 'ignore' });
      console.log(output);
    } else console.log(source);
  }
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
