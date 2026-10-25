# Stack and Contract

How to set up the code so several agents can build in parallel without breaking each other, and how to prove the result works before an owner or a store reviewer sees it.

## Decision rule

Choose the stack and the working agreement with three questions, in this order.

1. **Can the logic outlive the UI framework?** Put everything that is not rendering (rules, scoring, scheduling, storage, parsing, sync merge) in plain modules that never import the UI framework. Each module has a type declaration file next to it. If this holds, the framework choice is cheap to reverse; if it does not, every framework mistake becomes a rewrite.
2. **Who owns each file area, and where is it written down?** Parallel agents need one contract document that names every shared interface, every file area and its owner, and every extension point with the owner of its wiring. No second agent starts writing code until the contract exists and one foundation owner has built the shell it describes.
3. **Which checks decide "done"?** A build is done when an ordered list of gates passes and an independent judge, who has seen no earlier report, cannot reject it. Unit tests alone never decide it.

A stack that satisfies these three questions is acceptable. The default below is one such stack.

## Default path

Default stack: Vue 3, Vite and TypeScript, with vitest on happy-dom for tests and `vue-tsc` for types. Native shells come later (guide 05). Any framework with a fast typecheck and a component test runner works the same way.

### 1. Logic without UI

- Pure modules for rules and data (`lib/`-style folder), each with a declaration file. They take their clock, random source, storage and network as injected parameters, so tests pass fakes and never touch a browser or a service.
- Views call these modules through one composable or hook layer. A view never reimplements a rule.
- On the source project, a framework switch cost on the order of 30 minutes because of this split. That figure was observed once, on one project.

### 2. The contract document first

Write it before fan-out. One file, read by every worker before touching code. Sections:

- Layout: folders and what lives in each.
- View registry: the list of screens, one file per screen. A feature worker replaces the body of its own screen file; the registry, the app root and the shell components belong to the shell owner.
- Composables or hooks API: a table of name, inputs, outputs.
- Store schema: versioned, with the migration rule.
- Language and string rules: how dictionaries are named, how a missing key fails a test, how plurals work.
- Design tokens and shared components: published names (colour, spacing, radius, motion, shared card, button, sheet) and a coherence rule. Tokens get neutral names (`--ui-*`), not names tied to the current look.
- Test hooks: every `data-testid` and accessibility name that browser acceptance scripts use. They are API; restyling must not change them.
- Ownership: each file area and each extension point has one named owner, and each extension point also has a named owner of its wiring.
- Build and run notes: which command builds, which server the owner runs.

Rules that are enforced by tests rather than prose, because prose gets ignored: dictionary pairing and key parity, no raw durations or easing strings in components, golden replays for date logic across daylight-saving changes.

### 3. Information architecture before screens

Decide navigation and shell before any view worker starts, and give it a single owner: bottom tab bar with at most four or five tabs, a home screen with one primary action, a full-screen session flow, bottom sheets for secondary content, breakpoints for phone, tablet and desktop. On the source project each view was built by a separate worker into a shell that only offered top tabs and a generic card; every screen was a stack of bordered sections, and the result was rejected by the owner as looking like generic AI output. Fixing it cost a research document and a shell rebuild.

### 4. Quality gates, in order

Run them in this order; a later gate never replaces an earlier one.

1. Data validator and independent audits, if the app ships a content bank.
2. Type check (`vue-tsc --noEmit` or the framework equivalent), part of the build command.
3. Unit and component tests on the real app mounted over fake storage.
4. Mutation check: revert the fix, confirm the new test fails. A test that passes without the fix proves nothing.
5. Scripted real browser run against the built artifact, using the contract's test hooks.
6. Layout audits as scripts: overflow, minimum touch target size, colour contrast, motion; at the smallest phone width and at wide desktop, in every shipped language.
7. Performance audit. Lighthouse (or equivalent) measures the web layer; cold start of the packaged app is measured separately on a device or simulator. Write both rules into the acceptance checklist on day 0: throttled or unthrottled, device class, and the size budget. Re-measure when content or art doubles the bundle.
8. Independent adversarial judge on a frozen copy of the build.
9. After deploy: compare a checksum of the deployed bytes with the build, then run a fresh judge on the live bytes.
10. The owner on a real phone and a real desktop.

### 5. Independent judges

- A judge is a fresh agent that did not write the code and is told that nobody has told it the results of earlier checks.
- Give it a frozen, checksum-pinned copy of the build, a numbered checklist taken from the acceptance criteria, and the instruction to try to break the build. Each item ends PASS, FAIL or PARTIAL with the command that shows it.
- Judges earned their cost: on the source project five judges in a row rejected builds that all unit tests had passed. The findings were a feature that no caller wired up, an import that crashed on malformed data, two browser tabs overwriting each other's saved data, the back gesture fighting in-app history, a double-tap on the main action, and scroll position kept across tab switches. Count observed once, on one project.
- Ask for an adversarial review of the derived-number layer (scores, streaks, levels, readiness), not only of the UI. A whole-algorithm review on the source project found inflated learner-visible numbers and history that was erased on the next load past a size limit.

### 6. Commit the test harness on day 1

The browser acceptance script, the layout and contrast audits, the Lighthouse command, the judge brief template and the mount helper with injectable clock, storage, history and media queries live in the repository (an `e2e/` folder), not in a temporary directory. On the source project they lived in a temporary folder that was later gone while the contract still referenced them.

### 7. Failure modes to design against

- Green tests, absent feature: every extension point needs a wiring owner and one end-to-end check on the built artifact.
- Persisted-data robustness was the richest bug source: validate on load and on import, merge before write across tabs, version the store, cap sizes, never drop history silently, fuzz the loader.
- Mobile interaction: double-tap, hardware or gesture back versus in-app history, landscape sheets, scroll after tab switch, fixed bars covering content, animation fill modes that leave a transform behind.
- Locale-driven layout: translated labels run 20 to 40 percent longer; audit every screen at the smallest width in every language.
- A fix that causes the next bug: re-run the simulation after every rule change.
- Tooling that lies: a laptop sleeping looked like a test stall; a minifier rewrote a duration string and broke a parser; a network failure killed background agents mid-task. Check the environment before blaming the code.
- Stale decision notes: when the owner reverses a decision, delete the old one from memory and from the contract.

### 8. Working tree and dev loop

- Per-agent worktrees, or at minimum per-area branches, and commit early. On the source project one shared tree with no branches produced overwritten test files and typechecks blocked by someone else's uncommitted edit.
- The owner runs the dev server. Agents keep the tree compiling, build to private output copies, and never start competing servers or public preview tunnels.
- Pre-authorise the deploy once the gates pass, so an agent never waits for approval on a step the rules already cover.

Figures in this guide (30 minutes, five judges, 20 to 40 percent longer labels) were observed once, on one project; treat them as orders of magnitude, not targets.

## Checklist

- [ ] Logic modules never import the UI framework; each has a declaration file; clock, storage and network are injected.
- [ ] The contract document exists and lists layout, view registry, hooks API, store schema, string rules, tokens, test hooks, ownership.
- [ ] Navigation and shell have one named owner and exist before view workers start.
- [ ] Every extension point has a named wiring owner and an end-to-end check.
- [ ] Rules that matter are enforced by tests (string pairing, motion tokens, date golden replays).
- [ ] Type check is part of the build command.
- [ ] A mutation check was done for each fix test.
- [ ] A scripted browser run against the built artifact uses the contract's test hooks.
- [ ] Layout, contrast, touch target and motion audits run as scripts at smallest and widest widths, in every language.
- [ ] The performance rule (throttled or not, size budget) is in the acceptance checklist.
- [ ] An independent judge reviewed a frozen, checksum-pinned build with a numbered checklist and no earlier reports.
- [ ] After deploy, the checksum of the live bytes matches the build.
- [ ] The test harness, audit scripts and judge brief template are committed in the repository.
- [ ] Each agent works in its own worktree or branch; commits are early and small.
- [ ] The owner runs the dev server; agents do not start competing ones.
