import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const runner = fileURLToPath(new URL('foundry.mjs', import.meta.url));
test('the audit runner propagates native tool failures', () => {
  const result = spawnSync(process.execPath, [runner, 'forge', '--invalid-audit-regression-option'], { encoding: 'utf8' });
  assert.equal(result.status, 2);
  assert.match(result.stderr, /unexpected argument/);
});
test('the audit runner propagates success', () => {
  const result = spawnSync(process.execPath, [runner, 'forge', '--version'], { encoding: 'utf8' });
  assert.equal(result.status, 0);
  assert.match(result.stdout, /1\.7\.1/);
});
