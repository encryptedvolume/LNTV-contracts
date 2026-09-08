import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';
import { createRequire } from 'node:module';

const [tool, ...args] = process.argv.slice(2);
if (!['forge', 'cast', 'anvil'].includes(tool)) throw new Error('Expected forge, cast, or anvil');
const root = fileURLToPath(new URL('../', import.meta.url));
const require = createRequire(import.meta.url);
const architecture = process.arch === 'x64' ? 'amd64' : process.arch;
const name = process.platform === 'win32' ? `${tool}.exe` : tool;
let binary;
try {
  binary = require.resolve(`@foundry-rs/${tool}-${process.platform}-${architecture}/bin/${name}`);
} catch {
  binary = `${root}node_modules/@foundry-rs/dist/${name}`;
}
if (!existsSync(binary)) throw new Error('Missing Foundry binary; run npm ci with optional dependencies enabled');
if (args.length === 1 && args[0] === '--print-path') { console.log(binary); process.exit(0); }
// Invoke the native binary: the upstream 1.7.1 npm JS shim drops nonzero exit codes.
const result = spawnSync(binary, args, {
  cwd: root,
  stdio: 'inherit',
  env: process.env,
});
if (result.error) throw result.error;
process.exit(result.status ?? 1);
