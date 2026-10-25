import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { parseFrontmatter, loadKit, validateKit } from './kit-manifest.mjs';

// Builds a temp repo: one block (blocks/auth/login, id auth.login) plus
// the extra files given as { 'relative/path': 'content' }.
function makeFixture(t, extra = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'kit-manifest-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const files = {
    'blocks/auth/login/README.md': '---\nid: "auth.login"\nname: "Login"\n---\n\n# Login\n',
    ...extra,
  };
  for (const [rel, content] of Object.entries(files)) {
    const abs = path.join(root, rel);
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, content);
  }
  return root;
}

const kitReadme = (frontmatterLines, body = '# Kit\n') =>
  `---\n${frontmatterLines.join('\n')}\n---\n\n${body}`;

test('parseFrontmatter parses scalars and inline lists', () => {
  const meta = parseFrontmatter('---\ntags: [a, b]\ncomplexity: high\nexternal: true\nquoted: "true"\n---\nbody');
  assert.deepEqual(meta.tags, ['a', 'b']);
  assert.equal(meta.complexity, 'high');
  assert.equal(meta.external, true);
  assert.equal(meta.quoted, 'true');
});

test('parseFrontmatter parses a list of maps', () => {
  const meta = parseFrontmatter([
    '---',
    'blocks:',
    '  - id: "billing.in-app-purchase"',
    '    phase: "payments"',
    '    when: "app charges for anything"',
    '  - id: "auth.google-login"',
    '    phase: identity',
    '    when: "app has no login yet"',
    '  - id: "data.progress-sync"',
    '    phase: data',
    '    when: "progress must follow the user"',
    'guides:',
    '  - 01-day-0-decisions.md',
    '  - 02-lead-times.md',
    'tools:',
    '  - file: tools/store-art-gen.py',
    '    requires_env: [OPENROUTER_API_KEY]',
    '    external_service: true',
    '---',
  ].join('\n'));
  assert.equal(meta.blocks.length, 3);
  assert.deepEqual(meta.blocks[0], {
    id: 'billing.in-app-purchase',
    phase: 'payments',
    when: 'app charges for anything',
  });
  assert.deepEqual(meta.blocks[1], { id: 'auth.google-login', phase: 'identity', when: 'app has no login yet' });
  assert.equal(meta.blocks[2].id, 'data.progress-sync');
  assert.deepEqual(meta.guides, ['01-day-0-decisions.md', '02-lead-times.md']);
  assert.deepEqual(meta.tools, [
    { file: 'tools/store-art-gen.py', requires_env: ['OPENROUTER_API_KEY'], external_service: true },
  ]);
});

test('parseFrontmatter keeps a colon inside a quoted string', () => {
  const meta = parseFrontmatter('---\nname: "App Factory: idea to paid app"\n---\n');
  assert.equal(meta.name, 'App Factory: idea to paid app');
});

test('parseFrontmatter strips trailing comments but not # inside quotes', () => {
  const meta = parseFrontmatter([
    '---',
    'a: value # comment',
    'b: "keep # this" # drop this',
    'c: \'single # kept\'',
    'd: [x, y] # list comment',
    'blocks: # block comment',
    '  - id: "auth.login" # item comment',
    '    phase: "p#1"',
    '# whole-line comment',
    '---',
  ].join('\n'));
  assert.equal(meta.a, 'value');
  assert.equal(meta.b, 'keep # this');
  assert.equal(meta.c, 'single # kept');
  assert.deepEqual(meta.d, ['x', 'y']);
  assert.deepEqual(meta.blocks, [{ id: 'auth.login', phase: 'p#1' }]);
});

test('parseFrontmatter throws without frontmatter', () => {
  assert.throws(() => parseFrontmatter('# Just a heading\n'), { message: 'no frontmatter' });
  assert.throws(() => parseFrontmatter('---\nid: x\nno closing fence\n'), { message: 'no frontmatter' });
});

test('loadKit returns id, dir, meta and body', (t) => {
  const root = makeFixture(t, {
    'kits/demo/README.md': kitReadme(['id: "demo"', 'name: "Demo: a kit"'], '# Demo\n\nHello.\n'),
  });
  const kit = loadKit(root, 'demo');
  assert.equal(kit.id, 'demo');
  assert.equal(kit.dir, path.join(root, 'kits', 'demo'));
  assert.equal(kit.meta.name, 'Demo: a kit');
  assert.equal(kit.body, '# Demo\n\nHello.\n');
});

test('validateKit reports a missing guide, tool and block', (t) => {
  const root = makeFixture(t, {
    'kits/demo/README.md': kitReadme([
      'id: "demo"',
      'guides:',
      '  - x.md',
      'tools:',
      '  - file: tools/t.py',
      'blocks:',
      '  - id: "auth.nope"',
      '    phase: "identity"',
      '    when: "always"',
    ]),
  });
  assert.deepEqual(validateKit(root, 'demo'), [
    'guide missing: guides/x.md',
    'tool missing: tools/t.py',
    'block missing: auth.nope',
  ]);
});

test('validateKit reports an id mismatch', (t) => {
  const root = makeFixture(t, {
    'blocks/auth/login/README.md': '---\nid: "auth.other"\n---\n',
    'kits/demo/README.md': kitReadme(['id: "demo"', 'blocks:', '  - id: "auth.login"']),
  });
  assert.deepEqual(validateKit(root, 'demo'), ['block id mismatch: auth.login']);
});

test('validateKit reports an unknown block reference', (t) => {
  const root = makeFixture(t, {
    'kits/demo/README.md': kitReadme(['id: "demo"', 'guides:', '  - g.md']),
    'kits/demo/guides/g.md': 'Run `auth.login` then `auth.ghost`. Not blocks: `package.json`, `foo.bar`.\n',
  });
  assert.deepEqual(validateKit(root, 'demo'), ['unknown block reference: auth.ghost']);
});

test('validateKit checks backticked references in the README body', (t) => {
  const root = makeFixture(t, {
    'kits/demo/README.md': kitReadme(['id: "demo"'], 'See `auth.ghost`.\n'),
  });
  assert.deepEqual(validateKit(root, 'demo'), ['unknown block reference: auth.ghost']);
});

test('validateKit reports a kit that lists a kit', (t) => {
  const root = makeFixture(t, {
    'kits/other/README.md': kitReadme(['id: "other"']),
    'kits/demo/README.md': kitReadme(['id: "demo"', 'kits:', '  - other']),
  });
  assert.deepEqual(validateKit(root, 'demo'), ['kit lists a kit: other']);
});

test('validateKit reports a kit id that differs from its folder', (t) => {
  const root = makeFixture(t, {
    'kits/demo/README.md': kitReadme(['id: "elsewhere"']),
  });
  assert.deepEqual(validateKit(root, 'demo'), ['kit id mismatch: elsewhere']);
});

test('validateKit returns [] for a consistent kit', (t) => {
  const root = makeFixture(t, {
    'kits/demo/README.md': kitReadme(
      [
        'id: "demo"',
        'name: "Demo: consistent kit"',
        'guides:',
        '  - 01-start.md',
        'tools:',
        '  - file: tools/t.py',
        '    requires_env: [SOME_KEY]',
        'blocks:',
        '  - id: "auth.login"',
        '    phase: "identity"',
        '    when: "app has no login yet"',
      ],
      'Use `auth.login` first.\n',
    ),
    'kits/demo/guides/01-start.md': 'Start with `auth.login`.\n',
    'kits/demo/tools/t.py': '# tool\n',
  });
  assert.deepEqual(validateKit(root, 'demo'), []);
});

// ---------- the shipped kit ----------

const REPO_ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');

test('app-factory validates with no errors', () => {
  assert.deepEqual(validateKit(REPO_ROOT, 'app-factory'), []);
});

test('app-factory interview has fourteen items with a default each', () => {
  const { body } = loadKit(REPO_ROOT, 'app-factory');
  const start = body.indexOf('## Day-0 interview');
  assert.notEqual(start, -1, 'README has no "## Day-0 interview" section');
  const rest = body.slice(start + '## Day-0 interview'.length);
  const next = rest.search(/^## /m);
  const section = next === -1 ? rest : rest.slice(0, next);
  assert.equal((section.match(/^\d+\. /gm) || []).length, 14);
  assert.equal((section.match(/^\s+Default:/gm) || []).length, 14);
});
