// Content rules for everything under kits/ and skills/implement-kit.md.
// KIT_ROOT overrides the kits directory (default: <repo>/kits).
// KIT_SCRUB_TERMS is a comma-separated list of names that must not appear anywhere;
// the owner supplies it at run time and it is never stored in the repo.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseFrontmatter } from './kit-manifest.mjs';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const KIT_ROOT = process.env.KIT_ROOT || path.join(REPO_ROOT, 'kits');
const SCRUB_TERMS = (process.env.KIT_SCRUB_TERMS || '')
  .split(',').map((t) => t.trim()).filter(Boolean);

const DURATION = /\b\d+(\.\d+)?\s?(h|hours?|min|minutes?|days?)\b/i;

// ---------- pure checks (also tested against bad input below) ----------

export function leakProblems(text, terms = []) {
  const problems = [];
  if (text.includes('/Users/')) problems.push('absolute home path /Users/');
  if (text.includes('~/projects')) problems.push('local path ~/projects');
  const emails = text.match(/[\w.+-]+@[\w-]+\.[\w.-]+/g) || [];
  for (const e of emails) {
    if (!e.startsWith('noreply@')) problems.push(`email ${e}`);
  }
  if (/BEGIN [A-Z ]*PRIVATE KEY/.test(text)) problems.push('private key header');
  const lower = text.toLowerCase();
  for (const term of terms) {
    if (lower.includes(term.toLowerCase())) problems.push('scrub term from KIT_SCRUB_TERMS');
  }
  return problems;
}

export function guideProblems(text) {
  const problems = [];
  if (!/^# \S/m.test(text)) problems.push('missing "# " title');
  if (!/^## Decision rule$/m.test(text)) problems.push('missing "## Decision rule"');
  if (!/^## Checklist$/m.test(text)) problems.push('missing "## Checklist"');
  if (DURATION.test(text) && !/observed once/i.test(text)) {
    problems.push('durations or counts without "observed once"');
  }
  return problems;
}

// ---------- file discovery ----------

function walk(dir) {
  if (!fs.existsSync(dir)) return [];
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!entry.name.startsWith('.') && entry.name !== '__pycache__') out.push(...walk(full));
    }
    else out.push(full);
  }
  return out;
}

const kitFiles = walk(KIT_ROOT);
const entrySkill = path.join(REPO_ROOT, 'skills', 'implement-kit.md');
const scanned = process.env.KIT_ROOT || !fs.existsSync(entrySkill) ? kitFiles : [...kitFiles, entrySkill];
const guideFiles = kitFiles.filter((f) => /[\\/]guides[\\/][^\\/]+\.md$/.test(f));

// ---------- the checks bite (unit tests of the pure functions) ----------

test('leakProblems flags paths, emails, key headers and scrub terms', () => {
  assert.deepEqual(leakProblems('see /Users/x/y'), ['absolute home path /Users/']);
  assert.deepEqual(leakProblems('~/projects/foo'), ['local path ~/projects']);
  assert.deepEqual(leakProblems('mail me@example.com'), ['email me@example.com']);
  assert.deepEqual(leakProblems('from noreply@example.com'), []);
  assert.deepEqual(leakProblems('-----BEGIN RSA PRIVATE KEY-----'), ['private key header']);
  assert.deepEqual(leakProblems('The Secret Name', ['secret name']), ['scrub term from KIT_SCRUB_TERMS']);
  assert.deepEqual(leakProblems('clean text', ['other']), []);
});

test('guideProblems flags a missing title, rule, checklist and unmarked durations', () => {
  assert.deepEqual(guideProblems('# T\n\n## Decision rule\n\n## Checklist\n'), []);
  assert.equal(guideProblems('## Decision rule\n## Checklist\n').length, 1);
  assert.equal(guideProblems('# T\n## Checklist\n').length, 1);
  assert.equal(guideProblems('# T\n## Decision rule\n').length, 1);
  assert.equal(guideProblems('# T\n## Decision rule\n## Checklist\nTook 3 hours.\n').length, 1);
  assert.deepEqual(
    guideProblems('# T\n## Decision rule\n## Checklist\nTook 3 hours (observed once, on one project).\n'),
    [],
  );
});

// ---------- the real files ----------

test('no file under kits/ or skills/implement-kit.md leaks a path, email, key or scrub term', () => {
  const failures = [];
  for (const file of scanned) {
    for (const problem of leakProblems(fs.readFileSync(file, 'utf8'), SCRUB_TERMS)) {
      failures.push(`${path.relative(REPO_ROOT, file)}: ${problem}`);
    }
  }
  assert.deepEqual(failures, []);
});

test('every guide has a title, a Decision rule and a Checklist, and marks durations', () => {
  const failures = [];
  for (const file of guideFiles) {
    for (const problem of guideProblems(fs.readFileSync(file, 'utf8'))) {
      failures.push(`${path.relative(REPO_ROOT, file)}: ${problem}`);
    }
  }
  assert.deepEqual(failures, []);
});

test('every guide listed by a kit exists and every file in guides/ is listed', () => {
  const failures = [];
  if (!fs.existsSync(KIT_ROOT)) return;
  for (const entry of fs.readdirSync(KIT_ROOT, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const readme = path.join(KIT_ROOT, entry.name, 'README.md');
    if (!fs.existsSync(readme)) continue;
    const listed = parseFrontmatter(fs.readFileSync(readme, 'utf8')).guides || [];
    const guidesDir = path.join(KIT_ROOT, entry.name, 'guides');
    const onDisk = fs.existsSync(guidesDir)
      ? fs.readdirSync(guidesDir).filter((n) => n.endsWith('.md'))
      : [];
    for (const name of listed) if (!onDisk.includes(name)) failures.push(`${entry.name}: listed but missing ${name}`);
    for (const name of onDisk) if (!listed.includes(name)) failures.push(`${entry.name}: on disk but not listed ${name}`);
  }
  assert.deepEqual(failures, []);
});
