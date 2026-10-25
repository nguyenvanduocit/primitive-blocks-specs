// Kit manifest: parse the README frontmatter of a kit and validate it
// against the repo (blocks/<category>/<slug>/, kits/<id>/).
import fs from 'node:fs';
import path from 'node:path';

const KEY_LINE = /^([A-Za-z_][\w-]*):(?:\s+(.*))?$/;
const BLOCK_ID = /^[a-z0-9-]+\.[a-z0-9-]+$/;
const BLOCK_REFERENCE = /`([a-z]+\.[a-z][a-z-]*)`/g;

// ---------- frontmatter parser (subset of YAML) ----------

// Removes a trailing `# comment` that sits outside quotes.
function stripComment(text) {
  let quote = null;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quote) {
      if (ch === '\\' && quote === '"') i++;
      else if (ch === quote) quote = null;
    } else if (ch === '"' || ch === "'") {
      quote = ch;
    } else if (ch === '#' && (i === 0 || /\s/.test(text[i - 1]))) {
      return text.slice(0, i).trimEnd();
    }
  }
  return text.trimEnd();
}

function parseScalar(raw) {
  const text = raw.trim();
  if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
    return text.slice(1, -1).replace(/\\(["\\])/g, '$1');
  }
  if (text.length >= 2 && text.startsWith("'") && text.endsWith("'")) {
    return text.slice(1, -1).replace(/''/g, "'");
  }
  if (text === 'true') return true;
  if (text === 'false') return false;
  return text;
}

// Splits on commas that sit outside quotes.
function splitList(inner) {
  const parts = [];
  let quote = null;
  let start = 0;
  for (let i = 0; i < inner.length; i++) {
    const ch = inner[i];
    if (quote) {
      if (ch === '\\' && quote === '"') i++;
      else if (ch === quote) quote = null;
    } else if (ch === '"' || ch === "'") {
      quote = ch;
    } else if (ch === ',') {
      parts.push(inner.slice(start, i));
      start = i + 1;
    }
  }
  parts.push(inner.slice(start));
  return parts.map((p) => p.trim()).filter((p) => p !== '');
}

// A value after `key:` or `- `: a scalar or an inline list.
function parseValue(raw) {
  const text = raw.trim();
  if (text.startsWith('[') && text.endsWith(']')) {
    return splitList(text.slice(1, -1)).map(parseScalar);
  }
  return parseScalar(text);
}

// Reads one `- ` list item that starts on lines[i]. Returns [item, nextIndex].
// A map item is `- key: v` followed by more indented `key: v` lines.
function parseListItem(lines, i, fail) {
  const text = lines[i].replace(/^\s*-\s*/, '');
  if (text.startsWith('"') || text.startsWith("'") || !KEY_LINE.test(text)) {
    return [parseValue(text), i + 1];
  }
  const item = {};
  const indent = lines[i].match(/^\s*/)[0].length;
  let current = text;
  let next = i + 1;
  for (;;) {
    const m = current.match(KEY_LINE);
    if (!m) fail(next, 'expected "key: value"');
    item[m[1]] = m[2] === undefined ? '' : parseValue(m[2]);
    if (next >= lines.length) break;
    const line = lines[next];
    const lineIndent = line.match(/^\s*/)[0].length;
    if (lineIndent <= indent || /^\s*-\s/.test(line)) break;
    current = line.trim();
    next++;
  }
  return [item, next];
}

// Splits a markdown file into its frontmatter lines and its body text.
function splitFrontmatter(md) {
  const all = md.replace(/^\uFEFF/, '').split(/\r?\n/);
  if (all[0]?.trim() !== '---') throw new Error('no frontmatter');
  const end = all.findIndex((line, idx) => idx > 0 && line.trim() === '---');
  if (end === -1) throw new Error('no frontmatter');
  return { all, end, body: all.slice(end + 1).join('\n').replace(/^\n+/, '') };
}

export function parseFrontmatter(md) {
  const { all, end } = splitFrontmatter(md);

  // Drop blanks and comments; keep what is left with its 1-based file line.
  const rows = [];
  for (let n = 1; n < end; n++) {
    const text = stripComment(all[n]);
    if (text.trim() !== '') rows.push({ text, n: n + 1 });
  }
  const lines = rows.map((r) => r.text);
  const fail = (idx, why) => {
    throw new Error(`frontmatter line ${rows[Math.min(idx, rows.length - 1)].n}: ${why}`);
  };

  const meta = {};
  let i = 0;
  while (i < lines.length) {
    const m = lines[i].match(KEY_LINE);
    if (!m) fail(i, 'expected "key: value"');
    const [, key, value] = m;
    i++;
    if (value !== undefined) {
      meta[key] = parseValue(value);
      continue;
    }
    if (i < lines.length && /^\s*-(\s|$)/.test(lines[i])) {
      const list = [];
      while (i < lines.length && /^\s*-(\s|$)/.test(lines[i])) {
        const [item, next] = parseListItem(lines, i, fail);
        list.push(item);
        i = next;
      }
      meta[key] = list;
    } else {
      meta[key] = '';
    }
  }
  return meta;
}

// ---------- kit loading and validation ----------

export function loadKit(repoRoot, id) {
  const dir = path.join(repoRoot, 'kits', id);
  const md = fs.readFileSync(path.join(dir, 'README.md'), 'utf8');
  return { id, dir, meta: parseFrontmatter(md), body: splitFrontmatter(md).body };
}

const asList = (value) => (Array.isArray(value) ? value : []);
const entryId = (entry) => (entry && typeof entry === 'object' ? entry.id : entry);

function blockReadme(repoRoot, blockId) {
  const [category, slug] = blockId.split('.');
  return path.join(repoRoot, 'blocks', category, slug, 'README.md');
}

function blockCategories(repoRoot) {
  const dir = path.join(repoRoot, 'blocks');
  if (!fs.existsSync(dir)) return new Set();
  return new Set(fs.readdirSync(dir, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name));
}

export function validateKit(repoRoot, id) {
  const kit = loadKit(repoRoot, id);
  const errors = [];

  if (kit.meta.id !== id) errors.push(`kit id mismatch: ${kit.meta.id}`);

  const existingGuides = [];
  for (const name of asList(kit.meta.guides)) {
    const rel = path.join('guides', String(name));
    if (fs.existsSync(path.join(kit.dir, rel))) existingGuides.push(rel);
    else errors.push(`guide missing: ${rel}`);
  }

  for (const tool of asList(kit.meta.tools)) {
    const file = String(tool && typeof tool === 'object' ? tool.file : tool);
    if (!fs.existsSync(path.join(kit.dir, file))) errors.push(`tool missing: ${file}`);
  }

  for (const entry of asList(kit.meta.blocks)) {
    const blockId = String(entryId(entry));
    if (fs.existsSync(path.join(repoRoot, 'kits', blockId, 'README.md'))) {
      errors.push(`kit lists a kit: ${blockId}`);
      continue;
    }
    const readme = BLOCK_ID.test(blockId) ? blockReadme(repoRoot, blockId) : null;
    if (!readme || !fs.existsSync(readme)) {
      errors.push(`block missing: ${blockId}`);
      continue;
    }
    let actual;
    try {
      actual = parseFrontmatter(fs.readFileSync(readme, 'utf8')).id;
    } catch {
      actual = undefined;
    }
    if (actual !== blockId) errors.push(`block id mismatch: ${blockId}`);
  }

  for (const entry of asList(kit.meta.kits)) {
    errors.push(`kit lists a kit: ${entryId(entry)}`);
  }

  const categories = blockCategories(repoRoot);
  const texts = [kit.body, ...existingGuides.map((rel) => fs.readFileSync(path.join(kit.dir, rel), 'utf8'))];
  const unknown = new Set();
  for (const text of texts) {
    for (const [, ref] of text.matchAll(BLOCK_REFERENCE)) {
      if (categories.has(ref.split('.')[0]) && !fs.existsSync(blockReadme(repoRoot, ref))) unknown.add(ref);
    }
  }
  for (const ref of unknown) errors.push(`unknown block reference: ${ref}`);

  return errors;
}
