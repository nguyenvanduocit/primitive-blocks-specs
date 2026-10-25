# Kits: bundled journeys of guides, blocks and tools

**Date**: 2026-10-22
**Status**: Approved, implemented
**Scope**: Introduce the `kit` concept and ship the first kit, `app-factory`, generalised from one mobile app that went from idea to a paid iOS and Android release.

## Intent

A primitive block is one capability (login, billing, reviews). Real work often spans many capabilities plus things that are not code: choosing a stack, opening store accounts, passing a store review, generating store graphics. That knowledge exists today as a source playbook (11 sections and 5 appendices A to E, about 1,500 lines) and a folder of scripts from one mobile app project, and the library has no place for it.

A **kit** is the missing unit: one folder that carries one journey end to end. It is made of ordered guides, references to blocks, and tools. Claude Code reads a kit the way it reads a block, and walks the user through the journey.

The first kit is `app-factory`: from idea to a paid app on the App Store and Google Play. It is written for every future app. The source project (one human, many parallel Claude sessions, a Vue web app turned into a paid iOS and Android app over about five days) is the evidence behind it and appears in the kit only as "a mobile app" or "the source project".

## Goals

1. Define the kit folder format (manifest plus guides plus tools) so a second kit can be added without changing the format.
2. Ship `kits/app-factory/` with the experience generalised: day-0 interview, lead-time items, architecture contract, backend and login choices, payments, signing, store submission, how to direct agents.
3. Ship a generic entry skill, `skills/implement-kit.md`, that finds a kit, runs its interview, sequences its guides and blocks, and reports. It mirrors `skills/implement-block.md`.
4. Ship the generic tools from the source project as parameterised scripts that work for any app.
5. Show kits on the docs site (list page plus one page per kit), built by `docs/build.mjs` like blocks.

## Non-goals

- No kit dependency graph, no kit-in-kit nesting, no versions between kits. A kit lists blocks; it never lists kits.
- No package manager or installer. A kit is read by Claude Code from a cloned repo, like a block.
- No copy of block content inside a kit. Guides link to a block id and say when to run it.
- No content-pipeline tooling from the source project. Its question-extraction, validator, glossary and product-asset scripts only make sense for that product and are left out.
- No Shopify scope. `app-factory` is for store-distributed mobile apps.

## Anti-goals (failure even if it technically works)

- Any guide, tool, example or comment that names the source product or reads as its diary. Every guide must be usable by someone who has never seen it.
- Numbers presented as guarantees. Every observed duration or count is marked "observed once, on one project" and cites the source appendix section.
- Content copied from blocks into guides, so two places drift apart.
- Tools that silently do nothing or silently spend money when a key is missing.
- Personal data, local paths, team or account identifiers, or credentials from the source project in any committed file.

## Decisions made by the owner

- A kit is one folder for one journey with ordered chapters. It is not many small composable kits.
- The kit replaces `skills/ship-mobile-app.md` (a draft written from the source playbook by a parallel session). That draft is a source for the kit guides. Once the kit exists, `ship-mobile-app.md` is removed and its sequencing content lives in `kits/app-factory/` and `skills/implement-kit.md`.
- Kits may include executable tools (scripts), unlike blocks which stay blueprints.
- The source project is never named. Kit content, design documents and plans refer to it as "a mobile app" or "the source project", because the kit serves every later app.

## Calls made by the author (owner may override)

- **Language**: English, matching the source playbook and the five new mobile blocks.
- **Tools may call external services** (for example image generation through OpenRouter). Each such tool declares the environment variable it needs in the kit manifest, reads the key only from the environment, and exits with a clear message naming the variable when it is missing. No key is ever stored in the repo.
- **Entry point**: a generic `skills/implement-kit.md` plus the kit's own `README.md`, not one skill per kit. A second kit then needs no new skill.
- **Stack stance**: `app-factory` names a default stack (Vue 3 + Vite, Capacitor, Firebase Auth and Firestore, RevenueCat) because the playbook's value is a journey that was actually completed. Each guide states the decision rule first and the default second, so a user on another stack can still use the rule. Block references stay stack-neutral as the blocks themselves are.
- **Removing `skills/ship-mobile-app.md`**: it is untracked, so deleting it cannot be undone from git. The removal is the last step of the build, after its content has been merged into the guides, and the builder asks the owner before running it.
- **Docs site source of truth**: kit pages are generated from the kit's `README.md` frontmatter and guide files, not from a hand-copied list. The `KITS` list in `docs/build.mjs` holds only the kit folder names. Pages show the manifest, the interview, and the guide list with links to GitHub, matching how block pages link their files.
- **Tool testing**: every tool has a `--dry-run` that validates arguments and config and prints what it would send, without calling a service. Acceptance is the dry run. A live run needs the owner's key and is optional; the kit states which tools were live-tested.
- **Folder name**: top-level `kits/`, next to the block category folders. A kit id is its folder name (`app-factory`), with no category prefix, since kits have no categories.
- **Source location**: the build reads the source playbook and tools from a local path the owner supplies at build time. That path is not written into any committed file.

## Folder format

```
kits/
  app-factory/
    README.md           # manifest (frontmatter) + overview + day-0 interview
    guides/
      NN-<topic>.md     # ordered chapters
    tools/
      <script>          # one file per tool, header comment states usage, inputs, env vars
```

### Manifest (frontmatter of `README.md`)

```yaml
---
id: "app-factory"
name: "App Factory: idea to paid app on both stores"
version: "1.0.0"
tags: [mobile, ios, android, capacitor, firebase, revenuecat, store-submission]
complexity: high
estimated_effort: "days, dominated by account lead times and store review"
blocks:                       # ids that exist in this repo; each with the phase it runs in
  - id: "billing.in-app-purchase"
    phase: "payments"
    when: "app charges for anything"
guides:                       # ordered; file names relative to guides/
  - 01-day-0-decisions.md
tools:
  - file: tools/store-art-gen.py
    purpose: "Generate store listing background art"
    requires_env: [OPENROUTER_API_KEY]
    external_service: true
---
```

Field list is the contract; extra fields are allowed. `implement-kit.md` must refuse to proceed if a listed block id, guide file or tool file does not exist. Before it runs any block, it checks the user's project for the capability each prerequisite provides (for example an existing login). A prerequisite already satisfied by the project is not implemented again; the kit asks the user only when it cannot tell. `implement-block.md` keeps its current rule until the owner asks to change it.

## First kit: `app-factory` contents

**Guides** (generalised from the source playbook; the chapter split is a starting point, the builder may merge or split):

| Guide | Source section |
|---|---|
| Day-0 decisions (the interview with named defaults) | playbook section 2 |
| Lead-time items and the human boundary | section 3, appendix D section 3 |
| Stack and the architecture contract | section 4, appendix A |
| Hosting, backend tier, login, privacy page | section 5, appendix B |
| Mobile shell, payments, signing | section 6, appendix C |
| Store submission runbooks (Play, App Store) | section 7, appendix D |
| Working with agents; anti-patterns | sections 8 and 9, appendix E |

The "starter checklist" (section 11) becomes the checklist at the end of the kit README.

**Blocks referenced** (all exist in the working tree, written in a parallel session): `billing.in-app-purchase`, `auth.google-login`, `auth.sign-in-with-apple`, `compliance.account-deletion`, `data.progress-sync`, `ugc.friends-leaderboard`. Guides name the phase and condition for each; the block holds the implementation detail. `auth.google-login` is listed with `when: "app has no login yet"`: `compliance.account-deletion`, `ugc.friends-leaderboard` and `auth.sign-in-with-apple` keep it as a prerequisite and each has an "Identity precondition" section saying any existing authenticated-user model satisfies it. The login guide states that on the default Firebase stack the Firebase user is the identity.

**Tools**:
- `store-art-gen.py` (15 lines in the source project): already generic except a hard-coded output directory; make the output directory an argument.
- `store-art-compose.py` (319 lines in the source project): headlines, mascot sprites and paths are hard-coded in a `SHOTS` table; replace it with a config file the user supplies.
- Candidates to evaluate: an icon-set generator (its icon list is app-specific; keep only if the generator part separates cleanly) and a deploy script (a pattern, probably a guide snippet rather than a tool).
- Not available: the source project's e2e and audit harness was kept in a temporary directory and no longer exists (playbook section 4). The kit guide says to commit such a harness on day 1; it ships no harness.

## Docs site

`docs/build.mjs` gets a `KITS` list parallel to `BLOCKS` and emits `docs/kits.html` and `docs/kits/<id>.html`; the landing and nav link to it. Visual style follows the existing pages, and the project rule against decorative metadata applies (no fake document numbers, sheet labels or revision numbers, no padding paragraphs).

## Constraints

- Repository layout: `blocks/<category>/<slug>/` for blocks, `kits/<id>/` for kits, `skills/`, `docs/`. A block id `category.slug` maps to `blocks/<category>/<slug>/`. All 16 existing blocks move under `blocks/`; paths in `docs/build.mjs`, `README.md` and `skills/implement-block.md` are updated, block content is not.
- Abstraction discipline from `docs/SPEC_GUIDELINES.md` applies to the block references; guides describe WHAT and WHY and the decision rules, not stack-specific code.
- `docs/build.mjs`, `docs/index.html` and generated block pages are shared with a parallel session that also edits this repo. Run `node docs/build.mjs` after editing and tell that session first.
- Nothing is committed until the owner asks. Before any git command, message the parallel session.
- Secrets and personal data never enter the repo; the guides repeat this rule for keystores, `.p8` files, service accounts and bank or tax data (playbook sections 3 and 5). The source appendices contain team ids, personal emails and app ids; the builder scrubs them while generalising.

## Left to the builder

- Exact guide split and file names.
- The wording of the interview inside the kit README.
- How `implement-kit.md` resumes a half-finished journey (suggested: a checklist the user's project keeps, not state inside the library).
- Python/Node versions and dependency declarations for tools (the scripts use Pillow and fontTools).
- The visual layout of the kits pages.
