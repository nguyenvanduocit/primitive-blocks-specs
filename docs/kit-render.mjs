// Pure renderers for the kit pages. Both functions return inner HTML only;
// docs/build.mjs adds the head, header and footer.

const escapeHtml = (s) =>
  String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// Same light inline markdown as build.mjs: `code` and **bold**.
const renderInline = (s) =>
  escapeHtml(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');

const asList = (value) => (Array.isArray(value) ? value : []);
const text = (value) => (typeof value === 'string' || typeof value === 'number' ? String(value) : '');
const asEntry = (value, key) => (value && typeof value === 'object' ? value : { [key]: value });

const COMPLEXITIES = new Set(['low', 'medium', 'high']);
const NONE = '<p class="empty-state">None</p>';

function kitFacts(kit) {
  const meta = kit.meta ?? {};
  const complexity = text(meta.complexity);
  return {
    id: kit.id,
    name: text(meta.name) || kit.id,
    tags: asList(meta.tags).map(text).filter(Boolean),
    complexity,
    complexityClass: COMPLEXITIES.has(complexity) ? ` ${complexity}` : '',
    effort: text(meta.estimated_effort),
    version: text(meta.version),
    guides: asList(meta.guides).map(text).filter(Boolean),
    blocks: asList(meta.blocks).map((b) => asEntry(b, 'id')).map((b) => ({
      id: text(b.id),
      phase: text(b.phase),
      when: text(b.when),
    })).filter((b) => b.id),
    tools: asList(meta.tools).map((t) => asEntry(t, 'file')).map((t) => ({
      file: text(t.file),
      purpose: text(t.purpose),
      env: asList(t.requires_env).map(text).filter(Boolean),
      external: t.external_service === true,
    })).filter((t) => t.file),
  };
}

const tagsHtml = (tags) =>
  tags.length ? `<div class="block-tags">${tags.map((t) => `<span class="tag">${escapeHtml(t)}</span>`).join('')}</div>` : '';

const metaItem = (label, valueHtml) =>
  `<div class="meta-item"><span class="label">${label}</span><span>${valueHtml}</span></div>`;

const complexityBadge = (f) =>
  f.complexity ? `<span class="complexity${f.complexityClass}">${escapeHtml(f.complexity)}</span>` : '';

export function renderKitsIndexBody(kits) {
  const list = asList(kits);
  if (!list.length) return NONE;
  const cards = list.map((kit) => {
    const f = kitFacts(kit);
    return `
        <a class="block-card kit-card" href="kits/${escapeHtml(f.id)}.html">
          <span class="arrow" aria-hidden="true">→</span>
          <div class="card-body">
            <div class="row-1"><span class="block-id">${escapeHtml(f.id)}</span></div>
            <div class="block-name">${escapeHtml(f.name)}</div>
            ${tagsHtml(f.tags)}
            <div class="block-meta">
              ${f.complexity ? metaItem('Complexity', complexityBadge(f)) : ''}
              ${f.effort ? metaItem('Effort', escapeHtml(f.effort)) : ''}
              ${metaItem('Guides', String(f.guides.length))}
              ${metaItem('Blocks', String(f.blocks.length))}
              ${metaItem('Tools', String(f.tools.length))}
            </div>
          </div>
        </a>`;
  }).join('');
  return `<div class="block-grid">${cards}
    </div>`;
}

// First paragraph after the README's H1, used as the page lead.
function leadParagraph(body) {
  const lines = text(body).split('\n');
  let i = lines.findIndex((l) => /^#\s/.test(l));
  i = i === -1 ? 0 : i + 1;
  while (i < lines.length && (lines[i].trim() === '' || /^#+\s/.test(lines[i]))) i++;
  const para = [];
  for (; i < lines.length && lines[i].trim() !== ''; i++) {
    if (/^(#+|-|\*|\d+\.)\s/.test(lines[i])) break;
    para.push(lines[i].trim());
  }
  return para.join(' ');
}

// Items of the "## Day-0 interview" section: a numbered question plus its detail lines.
function parseInterview(body) {
  const lines = text(body).split('\n');
  const start = lines.findIndex((l) => /^##\s+Day-0 interview\s*$/i.test(l));
  if (start === -1) return [];
  const items = [];
  for (let i = start + 1; i < lines.length && !/^##\s/.test(lines[i]); i++) {
    const item = lines[i].match(/^\s*\d+\.\s+(.*\S)\s*$/);
    if (item) {
      items.push({ question: item[1], details: [] });
    } else if (items.length && lines[i].trim() !== '') {
      items[items.length - 1].details.push(lines[i].trim().replace(/^[-*]\s+/, ''));
    }
  }
  return items;
}

const detailHtml = (line) => {
  const m = line.match(/^([A-Za-z][^:]{0,60}):\s*(.*)$/);
  return m ? `<p><strong>${escapeHtml(m[1])}:</strong> ${renderInline(m[2])}</p>` : `<p>${renderInline(line)}</p>`;
};

const section = (id, label, inner) => `
      <section id="${id}">
        <div class="section-rule">
          <span class="section-label">${label}</span>
          <span class="section-line"></span>
        </div>
        ${inner}
      </section>`;

const fileLink = (href, label, type) =>
  `<a class="file-link" href="${escapeHtml(href)}" target="_blank" rel="noopener">${escapeHtml(label)}<span class="ftype">${type}</span></a>`;

export function renderKitBody(kit, opts) {
  const f = kitFacts(kit);
  const repoBlob = text(opts?.repoBlob);
  const known = new Set(asList(opts?.blockIds));
  const kitBlob = `${repoBlob}/kits/${f.id}`;
  const lead = leadParagraph(kit.body);
  const interview = parseInterview(kit.body);

  const summary = `
      <div class="block-meta">
        ${f.complexity ? metaItem('Complexity', complexityBadge(f)) : ''}
        ${f.effort ? metaItem('Effort', escapeHtml(f.effort)) : ''}
        ${f.version ? metaItem('Version', `<code>v${escapeHtml(f.version)}</code>`) : ''}
        ${metaItem('Guides', String(f.guides.length))}
        ${metaItem('Blocks', String(f.blocks.length))}
        ${metaItem('Tools', String(f.tools.length))}
      </div>`;

  const interviewHtml = interview.length
    ? section('interview', 'Day-0 interview', `<ol>${interview.map((q) =>
        `<li>${renderInline(q.question)}${q.details.map(detailHtml).join('')}</li>`).join('')}</ol>`)
    : '';

  const blockRows = f.blocks.map((b) => {
    const ref = known.has(b.id)
      ? `<span class="prereq-list"><a class="prereq" href="../blocks/${escapeHtml(b.id)}.html">${escapeHtml(b.id)}</a></span>`
      : `<code>${escapeHtml(b.id)}</code>`;
    return `<div class="related-row">
            <span class="related-label">${escapeHtml(b.phase)}</span>
            <div class="related-chips">${ref}${b.when ? `<span>${escapeHtml(b.when)}</span>` : ''}</div>
          </div>`;
  }).join('');
  const blocksHtml = section('blocks', 'Blocks', f.blocks.length ? `<div class="related-blocks">${blockRows}</div>` : NONE);

  const guidesHtml = section('guides', 'Guides', f.guides.length
    ? `<div class="files-grid">${f.guides.map((g) => fileLink(`${kitBlob}/guides/${g}`, g, 'MD')).join('')}</div>`
    : NONE);

  const toolBlocks = f.tools.map((t) => `<div class="files-section">
          <div class="files-grid">${fileLink(`${kitBlob}/${t.file}`, t.file, 'TOOL')}</div>
          ${t.purpose ? `<p>${escapeHtml(t.purpose)}</p>` : ''}
          <p><strong>Environment variables:</strong> ${t.env.length ? t.env.map((e) => `<code>${escapeHtml(e)}</code>`).join(' ') : 'None'}</p>
          <p><strong>Calls an external service:</strong> ${t.external ? 'Yes' : 'No'}</p>
        </div>`).join('');
  const toolsHtml = section('tools', 'Tools', f.tools.length ? toolBlocks : NONE);

  return `<article class="page-content">
      <div class="breadcrumb">
        <a href="../kits.html">Kits</a>
      </div>
      <span class="block-id-large">${escapeHtml(f.id)}</span>
      <h1>${escapeHtml(f.name)}</h1>
      ${lead ? `<p class="lead">${renderInline(lead)}</p>` : ''}
      ${tagsHtml(f.tags)}
${summary}
${interviewHtml}${blocksHtml}${guidesHtml}${toolsHtml}
    </article>`;
}
