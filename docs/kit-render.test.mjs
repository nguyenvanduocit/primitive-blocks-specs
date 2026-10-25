import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderKitsIndexBody, renderKitBody } from './kit-render.mjs';

const REPO_BLOB = 'https://example.test/repo/blob/main';

const BODY = [
  '# Sample Kit',
  '',
  'Takes a project from idea to shipped.',
  '',
  '## Day-0 interview',
  '',
  '1. **Which stores?**',
  '   Default: both',
  '   Options: Play only, App Store only, both',
  '   Why it is expensive to reverse: review queues differ',
  '2. **Paid or free?**',
  '   Default: free',
  '',
  '## Other',
  '',
  'Not part of the interview.',
  '',
].join('\n');

const kit = (meta = {}, body = BODY) => ({
  id: 'sample',
  body,
  meta: {
    id: 'sample',
    name: 'Sample Kit',
    version: '1.0.0',
    tags: ['mobile', 'ios'],
    complexity: 'high',
    estimated_effort: 'days',
    blocks: [
      { id: 'billing.in-app-purchase', phase: 'payments', when: 'app charges' },
      { id: 'auth.not-here', phase: 'login', when: 'always' },
    ],
    guides: ['01-first.md', '02-second.md', '03-third.md'],
    tools: [
      { file: 'tools/art.py', purpose: 'Make art', requires_env: ['SOME_KEY'], external_service: true },
    ],
    ...meta,
  },
});

const opts = { repoBlob: REPO_BLOB, blockIds: ['billing.in-app-purchase'] };

test('index card shows counts and links to the kit page', () => {
  const html = renderKitsIndexBody([kit()]);
  assert.match(html, /href="kits\/sample\.html"/);
  assert.match(html, /Sample Kit/);
  assert.match(html, /mobile/);
  assert.match(html, /class="complexity high"/);
  assert.match(html, /days/);
  assert.match(html, /Guides<\/span><span>3<\/span>/);
  assert.match(html, /Blocks<\/span><span>2<\/span>/);
  assert.match(html, /Tools<\/span><span>1<\/span>/);
});

test('kit page links known blocks and leaves unknown ones plain', () => {
  const html = renderKitBody(kit(), opts);
  assert.match(html, /<a class="prereq" href="\.\.\/blocks\/billing\.in-app-purchase\.html">billing\.in-app-purchase<\/a>/);
  assert.doesNotMatch(html, /blocks\/auth\.not-here\.html/);
  assert.match(html, /auth\.not-here/);
  assert.match(html, /payments/);
  assert.match(html, /app charges/);
});

test('kit page links guides in manifest order', () => {
  const html = renderKitBody(kit(), opts);
  const hrefs = [...html.matchAll(/href="([^"]*\/kits\/sample\/guides\/[^"]+)"/g)].map((m) => m[1]);
  assert.deepEqual(hrefs, [
    `${REPO_BLOB}/kits/sample/guides/01-first.md`,
    `${REPO_BLOB}/kits/sample/guides/02-second.md`,
    `${REPO_BLOB}/kits/sample/guides/03-third.md`,
  ]);
  assert.match(html, new RegExp(`href="${REPO_BLOB}/kits/sample/tools/art\\.py"`));
  assert.match(html, /SOME_KEY/);
  assert.match(html, /Make art/);
  assert.match(html, /<ol[^>]*>[\s\S]*Which stores\?[\s\S]*Paid or free\?[\s\S]*<\/ol>/);
  assert.match(html, /Default:<\/strong> both/);
  assert.doesNotMatch(html, /Not part of the interview/);
});

test('kit page with no tools and no blocks has no "undefined" or "[object"', () => {
  const html = renderKitBody(kit({ blocks: [], tools: [], guides: [], tags: [] }, '# Bare\n'), opts);
  assert.doesNotMatch(html, /undefined|\[object/);
  assert.match(html, /None/);
  assert.doesNotMatch(html, /Day-0 interview/);

  const sparse = renderKitBody({ id: 'sparse', body: '', meta: { id: 'sparse' } }, opts);
  assert.doesNotMatch(sparse, /undefined|\[object/);
  assert.doesNotMatch(renderKitsIndexBody([{ id: 'sparse', body: '', meta: { id: 'sparse' } }]), /undefined|\[object/);
  assert.doesNotMatch(renderKitsIndexBody([]), /undefined|\[object/);
});

test('kit page escapes HTML in manifest strings', () => {
  const evil = '<script>alert(1)</script>';
  const html = renderKitBody(
    kit({
      name: evil,
      tags: [evil],
      estimated_effort: evil,
      blocks: [{ id: evil, phase: evil, when: evil }],
      guides: [evil],
      tools: [{ file: evil, purpose: evil, requires_env: [evil], external_service: false }],
    }, `# T\n\n${evil}\n\n## Day-0 interview\n\n1. **${evil}**\n   Default: ${evil}\n`),
    opts,
  );
  assert.doesNotMatch(html, /<script>/);
  assert.match(html, /&lt;script&gt;/);

  const index = renderKitsIndexBody([kit({ name: evil, tags: [evil], estimated_effort: evil })]);
  assert.doesNotMatch(index, /<script>/);
});
