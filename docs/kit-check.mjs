// Usage: node docs/kit-check.mjs <kit-id>
// Prints each validation error on its own line and exits 1, or prints "ok: <id>" and exits 0.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateKit } from './kit-manifest.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const id = process.argv[2];

if (!id) {
  console.error('usage: node docs/kit-check.mjs <kit-id>');
  process.exit(1);
}

let errors;
try {
  errors = validateKit(repoRoot, id);
} catch (err) {
  errors = [err.code === 'ENOENT' ? `kit missing: ${id}` : `${id}: ${err.message}`];
}

if (errors.length > 0) {
  console.log(errors.join('\n'));
  process.exit(1);
}
console.log(`ok: ${id}`);
