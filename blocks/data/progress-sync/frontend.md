# Frontend Patterns - Progress Sync

The client carries almost all of this block's logic: validation, recovery, import, merge, serialization, sync scheduling. It is split on the **pure vs I/O boundary**:

| Part | Responsibility | I/O? |
|------|---------------|------|
| `progressCore` | `validate`, `recover`, `normalize`, `merge`, `serialize`, `parseSnapshot`, `markX` helpers | None. No clock, no storage, no network. Runs in tests with no mocks. |
| `store` | Holds `data`, reads and writes device storage, adopts other tabs' writes, import/export/reset | Device key-value storage, window events |
| `cloudSync` | Decides when to sync, runs read-merge-write against the Snapshot API, owns the sync state | Snapshot API, timers |
| UI | Sync card, import/erase controls, sign-in invitation | DOM |

Framework choice (Vue, React, Svelte) is the adopter's; nothing here depends on one. Keep `progressCore` free of framework imports.

## Store contract (L1)

| Member | Behavior |
|--------|----------|
| `data` | The current Local Store Record (always valid: it has been through `recover`). |
| `persistent` | `false` after storage was unusable at start or a write failed. |
| `load()` | Reads storage; any failure yields defaults; stored data goes through `recover`. Never throws. |
| `refresh()` | Re-reads storage; if its text differs from the last text this tab wrote or read, adopts it (when valid). Returns `null` (nothing adopted) or `{ reset }`. Never throws. |
| `update(fn)` | `refresh()`, then `data = fn(data)`, then `save()`. The only way features write. |
| `save()` | Writes; returns `false` on failure and then sets `persistent = false`, keeps memory data, leaves `seen` unchanged. |
| `subscribe(fn)` | `fn({ reset })` on every **external** adoption (not on this tab's own writes). |
| `exportJSON()` | Pretty-printed full record, including unknown keys and the owner marker. |
| `importJSON(text)` | `{ ok: true }` or `{ ok: false, error }`; see INV-3. |
| `reset()` | `data = defaults`, removes the storage key. |

`refresh()` also runs on: the storage event for `STORE_KEY` (or for a cleared storage, key `null`), page show (back/forward cache restore), and visibility change to visible. Hidden does not refresh.

## UI/UX Patterns

### Sync card (account section)

| State | What the user sees | Action offered |
|-------|-------------------|----------------|
| `off` | Sign-in button; text that study works without an account | Sign in |
| `syncing` | "Saving" with a spinner | none |
| `synced` | "Saved" and the last synced time | "Save now" |
| `error` | "Could not save; will retry" - local data is fine | "Retry now" |
| `blocked` | "Your cloud copy cannot be used or is too large; nothing was changed" | Explanation; no automatic action |

State is never conveyed by colour alone: every state has a text label or icon with an accessible name.

### Import

- Show the result as one message. On failure show the **reason mapped from the error path** (below) and, for list items, the 1-based position of the first bad item ("entry 12 of the history"). The existing data is unchanged and the message says so.
- Reason mapping: `not valid JSON`, `not an object`, `too large`, `quota` have their own wording; `history.entries[i].<field>` maps to one wording per field (`ref`, `value`, `ok`, `seq`, `ms`, `at`); `history.seq mismatch`, `marks duplicate`, `collection[i] duplicate`, `collection[i].<field>`, `notes.<ref>`, `prefs.<field>`, `milestones`. An unknown path gets a generic wording, never an empty message.
- After a **successful** import while signed in, clear the owner marker (INV-12) so the imported data joins the account.

### Erase

1. Signed out: erase the local record.
2. Signed in: delete the cloud snapshot first (and reset any derived leaderboard numbers); only on success erase locally. On failure erase nothing and say so. Otherwise the next sync restores the data.

### Shared device

When sign-in finds an owner marker for a different account, no dialog is shown: the account's copy replaces the data after the old data is saved aside, and the sync card says where the previous copy is (the previous-data slot). Preferences stay with the device.

### Toasts

Toast only an outcome the user cannot see on screen (export finished, import result, erase failed). Never for ordinary saves or sync ticks.

## Code Patterns

### Pattern 1: merge-before-write

<!-- PATTERN: store-merge-before-write -->
<!-- PURPOSE: Never overwrite another tab's newer data with this tab's stale memory -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: replace `KV` with the platform storage (localStorage, a native preferences plugin, IndexedDB wrapper); `defaults`, `validate`, `recover` come from progressCore; call `refresh` from the storage/pageshow/visibility listeners your platform provides -->
```typescript
export function createStore(kv: KV, key: string) {
  let seen: string | null = null; // text of `key` the last time this tab wrote or read it
  const s = { data: defaults(), persistent: true };
  const read = () => { try { return kv.getItem(key); } catch { return seen; } };
  const refresh = () => {
    const text = read();
    if (text === seen) return null;
    let next;
    if (text === null) next = defaults(); // another tab reset: do not bring old data back
    else {
      try { const p = JSON.parse(text); if (validate(p) !== null) return null; next = recover(p); }
      catch { return null; }
    }
    seen = text;
    const change = { reset: next.history.seq < s.data.history.seq };
    s.data = next;
    return change;
  };
  const save = () => {
    try { const t = JSON.stringify(s.data); kv.setItem(key, t); seen = t; return true; }
    catch { s.persistent = false; return false; } // memory copy stays; `seen` stays
  };
  const update = (fn: (d: Data) => Data) => { refresh(); s.data = fn(s.data); save(); return s.data; };
  return { s, refresh, save, update };
}
```

### Pattern 2: repair on load, section by section

<!-- PATTERN: store-recover-per-section -->
<!-- PURPOSE: Keep every valid part of damaged stored data; replace only what cannot be repaired -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: one `checkX` (returns an error path or null) and one `recoverX` per section of your schema; `fitHistory` is pattern 3; sections that fail repair fall back to the default of that section only -->
```typescript
export function recover(parsed: unknown): Data {
  if (!isObject(parsed)) return defaults();
  const d = defaults();
  const fitted = fitHistory(parsed.history);
  return normalize({
    ...parsed, // unknown top-level keys survive
    history: checkHistory(fitted) === null ? fitted : d.history,
    prefs: checkPrefs(parsed.prefs) === null ? parsed.prefs : undefined,
    collection: recoverCollection(parsed.collection), // drop bad entries, truncate long text, merge duplicate keys
    notes: recoverTextMap(parsed.notes), // drop values over MAX_TEXT
    milestones: checkMilestones(parsed.milestones) === null ? parsed.milestones : undefined,
  });
}
// `validate` (import) reports the FIRST error path of the same checks and never repairs:
export const validate = (data: unknown) =>
  !isObject(data) ? "not an object"
  : checkHistory(data.history) ?? checkMarks(data.marks) ?? checkPrefs(data.prefs) ??
    checkCollection(data.collection) ?? checkNotes(data.notes) ?? checkMilestones(data.milestones);
```

### Pattern 3: fit the history instead of discarding it

<!-- PATTERN: history-fit -->
<!-- PURPOSE: Repair stored history entry by entry; cap by dropping the oldest, never everything -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `isUsable` and `regrade` are domain rules (is `ref` still known, is `value` an allowed choice, recompute `ok` from the current answer key); drop `regrade` if `ok` is not derived data in your domain -->
```typescript
export function fitHistory(h: unknown) {
  if (!isObject(h) || !Array.isArray(h.entries)) return h;
  let latestAt = -Infinity;
  const entries = h.entries.filter(isUsable).map((e, i) => {
    const fit = { ...regrade(e), seq: i + 1, ms: Math.min(e.ms, MAX_ELAPSED_MS) };
    if (fit.at === undefined) return fit;
    if (!isAt(fit.at) || fit.at < latestAt - AT_SKEW_MS) { const { at, ...undated } = fit; return undated; }
    latestAt = Math.max(latestAt, fit.at);
    return fit;
  });
  const kept = entries.length > MAX_HISTORY ? entries.slice(-MAX_HISTORY).map((e, i) => ({ ...e, seq: i + 1 })) : entries;
  return { ...h, seq: kept.length, entries: kept };
}
```

### Pattern 4: strict import with rollback

<!-- PATTERN: import-strict-with-rollback -->
<!-- PURPOSE: Refuse a bad file whole and leave existing data untouched, including when storage is full -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `store` is the object from pattern 1; `normalize` fills missing optional sections and drops retired fields; error strings are the stable paths from validate(), mapped to wording by the UI -->
```typescript
export function importText(store: Store, text: string): { ok: true } | { ok: false; error: string } {
  if (text.length > MAX_IMPORT_CHARS) return { ok: false, error: "too large" }; // before parsing
  let parsed: unknown;
  try { parsed = JSON.parse(text); } catch { return { ok: false, error: "not valid JSON" }; }
  const error = validate(parsed);
  if (error) return { ok: false, error };
  const previous = store.s.data;
  const wasPersistent = store.s.persistent;
  store.s.data = normalize(parsed as Data);
  if (!store.save()) { // storage could not hold it: restore memory, report quota
    store.s.data = previous;
    store.s.persistent = wasPersistent;
    return { ok: false, error: "quota" };
  }
  return { ok: true };
}
```

### Pattern 5: defensive snapshot parse and serialize

<!-- PATTERN: snapshot-parse-serialize -->
<!-- PURPOSE: Treat cloud text as untrusted; produce deterministic text so equality means "nothing changed" -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: SYNCED lists the sections that travel, in the fixed order they serialize; validate is the same function import uses; keep `edits` map keys sorted inside merge so the text is stable -->
```typescript
const SYNCED = ["history", "marks", "collection", "settings", "prefs", "notes", "milestones", "edits"] as const;

export function pickSynced(data: Data): Partial<Data> {
  const out: Record<string, unknown> = {};
  for (const k of SYNCED) if (data[k] !== undefined) out[k] = data[k];
  return out as Partial<Data>;
}
export const serialize = (data: Data) => JSON.stringify(pickSynced(data));

/** The snapshot, or null when the text is not a usable copy (the caller then leaves the cloud copy alone). */
export function parseSnapshot(text: string | null): Data | null {
  if (text === null) return null;
  try {
    const v = JSON.parse(text);
    return v && typeof v === "object" && validate(v) === null ? (v as Data) : null;
  } catch {
    return null;
  }
}
```

### Pattern 6: append-log merge

<!-- PATTERN: merge-append-log -->
<!-- PURPOSE: Join two history lists without losing entries or double-counting the same one -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: the identity fields in `keyOf` (ref, value, ms, at) are the reference schema's; choose fields that are stable across devices and distinguish two real events; keep the occurrence counter so identical entries inside ONE copy stay distinct -->
```typescript
const keyOf = (e: Entry) => `${e.ref}|${e.value}|${e.ms}|${e.at ?? ""}`;
function keyed(list: Entry[]): [string, Entry][] {
  const count = new Map<string, number>();
  return list.map((e) => { const k = keyOf(e), n = count.get(k) ?? 0; count.set(k, n + 1); return [`${k}#${n}`, e]; });
}
export function mergeHistory(local: Entry[], remote: Entry[], max: number): Entry[] {
  const seen = new Set<string>(), all: Entry[] = [];
  for (const [k, e] of [...keyed(local), ...keyed(remote)]) if (!seen.has(k)) { seen.add(k); all.push(e); }
  const undated = all.filter((e) => e.at === undefined);
  const dated = all.filter((e) => e.at !== undefined).sort((a, b) => a.at! - b.at!); // stable sort required
  return [...undated, ...dated].slice(-max).map((e, i) => ({ ...e, seq: i + 1 }));
}
```

### Pattern 7: marks with tombstones, collection with removal times

<!-- PATTERN: merge-marks-and-collection -->
<!-- PURPOSE: Make deletions survive a merge with an older copy, and let a later re-add stand -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `normalizeKey` must be byte-identical on every client; `sortKeys` makes the serialized `edits` stable; add one `markX(edits, ..., at)` writer per user action that removes something and call it in the same `update` as the removal -->
```typescript
type Mark = { at: number; on: boolean };
export function joinMarks(a: Record<string, Mark>, b: Record<string, Mark>) {
  const out = { ...a };
  for (const [ref, m] of Object.entries(b)) {
    const have = out[ref];
    if (!have || m.at > have.at || (m.at === have.at && m.on)) out[ref] = m; // tie: stays flagged
  }
  return sortKeys(out);
}
export const mergeMarkList = (l: string[], r: string[], marks: Record<string, Mark>) =>
  [...new Set([...l, ...r])].filter((ref) => marks[ref]?.on !== false);

export function mergeCollection(l: Item[], r: Item[], removed: Record<string, number>): Item[] {
  const byKey = new Map<string, Item>();
  for (const e of [...l, ...r]) {
    const k = normalizeKey(e.key);
    if ((e.savedAt ?? 0) <= (removed[k] ?? -1)) continue; // deleted after it was saved
    const have = byKey.get(k);
    const newer = have && (e.savedAt ?? 0) <= (have.savedAt ?? 0) ? have : e;
    byKey.set(k, have ? { ...newer, sources: [...new Set([...(have.sources ?? []), ...(e.sources ?? [])])] } : e);
  }
  return [...byKey.values()];
}
```

### Pattern 8: debounce with snapshot equality

<!-- PATTERN: sync-scheduler-equality -->
<!-- PURPOSE: One write per burst of changes, none when nothing differs from the cloud, one follow-up if a change lands mid-sync -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `onDataChange` is the framework's watcher on store.data (Vue watch, React effect, store subscription); `runSync` is pattern 9; `signedIn` comes from the auth block; timers may be replaced by the platform scheduler -->
```typescript
let known = ""; // snapshot text the cloud is known to hold
let timer: ReturnType<typeof setTimeout> | null = null;
let running = false, again = false;

const schedule = (ms: number) => { if (timer) clearTimeout(timer); timer = setTimeout(() => void sync(), ms); };

onDataChange(() => {
  if (!signedIn() || state === "blocked") return;
  if (serialize(store.s.data) !== known) schedule(SAVE_DELAY_MS);
});

async function sync() {
  if (!signedIn()) return;
  if (running) { again = true; return; }
  running = true;
  if (timer) clearTimeout(timer);
  try { await runSync(); /* sets known = serialize(store.s.data) after folding the merge in */ }
  finally { running = false; if (again) { again = false; schedule(0); } }
}
```

### Pattern 9: read-merge-write with conflict retry

<!-- PATTERN: sync-retry-loop -->
<!-- PURPOSE: Atomic read-merge-write against the Snapshot API using the revision as compare-and-swap token -->
<!-- REFERENCE: language=typescript http=fetch-builtin -->
<!-- ADAPT: `api.get` returns `{ snapshot, revision }` or null on 404 and throws or returns an error status otherwise; `merge` is pure (section 3 of the README); MAX_CONFLICT_RETRIES from config; map the returned `kind` to the sync state (`blocked`, `error`, `synced`) -->
```typescript
async function syncOnce(base: Data): Promise<{ kind: "ok"; text: string } | { kind: "blocked" | "error" }> {
  for (let attempt = 0; attempt < MAX_CONFLICT_RETRIES; attempt++) {
    const got = await api.get();
    const remote = got ? parseSnapshot(got.snapshot) : null;
    if (got && remote === null) return { kind: "blocked" }; // unreadable cloud copy: never overwrite
    const text = serialize({ ...base, ...merge(base, remote) } as Data);
    if (text.length > SNAPSHOT_MAX_CHARS_CLIENT) return { kind: "blocked" };
    const res = await api.put({ snapshot: text, format_version: 1, base_revision: got?.revision ?? 0 });
    if (res.status === 200) return { kind: "ok", text };
    if (res.status !== 409) return { kind: "error" };
    // 409: another device wrote in between. Read again, merge again, write again.
  }
  return { kind: "error" };
}
```

### Pattern 10: owner marker, replace instead of merge

<!-- PATTERN: owner-replace-not-merge -->
<!-- PURPOSE: Never merge one person's progress into another person's account on a shared device -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `emptyProgress(prefs)` is the default record with this device's preferences; `keepPrevious` writes the full export to PREVIOUS_KEY and returns false when the write fails (the source app ignores that failure and replaces anyway; this block does not); the sections reset on replace are the ones that have no empty form or whose edit stamps belong to the other account (here `milestones`, `edits`) -->
```typescript
const replace = owner !== undefined && owner !== uid; // owner = store.data.cloud?.uid
const base = replace ? emptyProgress(store.s.data.prefs) : store.s.data;
const out = await syncOnce(base);
if (out.kind === "ok") {
  const merged = parseSnapshot(out.text)!; // the text we just wrote is trusted
  if (replace && !keepPrevious(store.exportJSON())) return setState("error"); // no backup, no replacement
  store.update((d) => {
    const current = replace ? { ...d, ...emptyProgress(d.prefs) } : d;
    return { ...d, ...(replace ? { milestones: undefined, edits: undefined } : {}), ...merge(current, merged), cloud: { uid } };
  });
  known = serialize(store.s.data);
}
```

Note the `store.update` after the network call: it merges the cloud result with whatever the user did while the request was in flight (it calls `refresh` first and `merge` is a join), so nothing is lost either way.

## Anti-Patterns

- **DON'T** write device storage from feature code; always `update(fn)`. A direct write skips the refresh and brings back the stale-write bug.
- **DON'T** let `JSON.parse` or a validator throw out of load, refresh, import, or snapshot parse. Each has a defined fallback (INV-2).
- **DON'T** repair on import. Accepting a "fixed" version of a hostile file hides what was wrong and makes export-then-import non-idempotent.
- **DON'T** fall back to empty history when a single entry is bad (INV-7). Drop or fix the entry.
- **DON'T** delete from a set without writing a tombstone in the same `update`. The next merge brings it back.
- **DON'T** compare timestamps from the device clock inside `merge`. Merge reads only stamps stored in the data.
- **DON'T** sync `cache`, `session`, the owner marker, or unknown keys.
- **DON'T** schedule a write after the sync result merely because the store changed: compare serialized text with `known`; saving the merge result changes nothing, and must not loop.
- **DON'T** erase locally before the remote erase succeeded.
- **DON'T** key tombstones by display text; key them by `normalizeKey(key)` so spelling variants meet.

## Styling and Accessibility

- Sync state, import failures, and the offline note are text first; icons and colours support them.
- Controls are at least 44 px tall on touch devices; the sync card works at 320 px width.
- Reason texts are translated per interface language; a missing translation falls back to the generic wording, never to an empty string.
