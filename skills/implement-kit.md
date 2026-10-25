---
name: implement-kit
description: >
  Discover, validate and walk a kit: a bundle of ordered guides, primitive blocks
  and tools that carries one whole journey, such as taking an app from idea to a
  paid release on the App Store and Google Play. Runs the kit's decision interview,
  starts slow external items first, then sequences the guides and blocks.
  Use when: "ship this as a mobile app", "put my web app on the App Store and
  Google Play", "app factory", "make a paid app", "submit to the stores",
  "Capacitor app", "set up hosting and Firebase", or any request that spans more
  than one capability plus non-code work (accounts, store consoles, listings).
---

# Implement Kit

You are a release lead. The user describes a journey → you find the matching kit,
validate it, run its interview, start the slow items, and walk the guides in order,
pulling in the kit's blocks and tools at the right phase.

A kit is a sequencing and decision layer. It does not contain the implementation of
blocks. For each block you run the `implement-block` flow.

## KITS_ROOT

The kits live at: `{{KITS_ROOT}}` (the `kits/` folder of the primitive-blocks repo)

If this variable is not set, ask the user where the primitive-blocks repo is cloned.
Default assumption: `./primitive-blocks/kits/` or `../primitive-blocks/kits/` relative to cwd.
The blocks live in the sibling folder `blocks/`; that folder is `BLOCKS_ROOT` for
the `implement-block` flow.

## Rules that hold in every phase

- Numbers in a kit ("about 22 minutes", "64 to 74 hours") were **observed once, on one
  project**. Quote them as such and let the user re-plan when their situation differs.
- Bank, tax and identity data, passcodes and two-factor codes are typed by the
  user. Never read, store or type them. Say which step needs the user and wait.
- Secrets live in git-ignored project files or the user's password manager, never in
  the repo, a guide, a report or a chat message.
- Ask pick-one questions with a named default, and only what is expensive to reverse.

---

## Phase 1: DISCOVER — Find the kit

1. Read every `*/README.md` under KITS_ROOT. Parse the YAML frontmatter: `id`, `name`,
   `tags`, `complexity`, `estimated_effort`.
2. Match the user's request against `name`, `tags` and the README overview.
3. One match → name it and say what it covers. Several → list them and let the user pick.
   None → say so and offer the `implement-block` flow for single capabilities.

## Phase 2: VALIDATE — Refuse a broken kit

Run `node <repo>/docs/kit-check.mjs <id>`. Exit 0 and `ok: <id>` → continue.
Any other output is a list of missing guides, tools or blocks: show it to the user and
stop. Do not guess around a missing piece.

## Phase 3: INTERVIEW — Day-0 decisions

Read the kit README section `## Day-0 interview`. Ask the numbered decisions in one
sitting, in order, each as a pick-one question with the named `Default:` and the
`Options:`; say why it is expensive to reverse when the user hesitates.

- A decision the user leaves unanswered takes its default and is recorded as an
  `Assumption:`.
- A default that is an action by the user (for example supplying reference screenshots)
  is recorded as an `Open owner item:`, not as an assumption, and the work that needs it
  waits.
- Record every answer in the user's project contract (`CONTRACT.md`, section
  "Decisions"; create the file with that section if it does not exist yet), not in the
  library.

Skip decisions the project already answers (for example an existing login or backend).
Say what you skipped and why.

## Phase 4: SEQUENCE — Slow items first, then the guides

1. From the first guides, list the lead-time items (accounts, agreements, reviews and
   tests that take days or weeks). Start them now, in parallel with coding, and tell the
   user which ones need them in person.
2. Read the guides in the order the manifest lists them. Each guide has a
   `## Decision rule`, a `## Default path` and a `## Checklist`. Apply the rule to the
   user's answers and follow the default path unless an answer overrides it.
3. Keep every guide's checklist in the user's project so a later session can resume.
   Mark each item with exactly one state:
   - `DONE`: finished, with evidence (a command output or a file you read).
   - `PLANNED`: needs something that does not exist yet (code, a build, an account); name what it waits for.
   - `HUMAN`: only the user can do it.
   - `N/A`: does not apply; give the reason.
   - `UNVERIFIED`: you could not check it.

   A report counts only `DONE` items as done and never merges the other states into it.

## Phase 5: BUILD — Contract, shell, then workers

Build the app from the guides, not from copied examples:

1. Write the project contract (`CONTRACT.md`) with the sections guide 03 lists, and an
   `AGENTS.md` that points agents at the store tools and skills for the project.
2. Build the foundation shell the contract describes (project layout, view registry,
   shared components, test hooks, the test harness) before any second agent starts.
3. Implement the features as workers that each own a file area named in the contract
   (guide 03 and guide 07). Run the quality gates guide 03 lists, in order, and tick the
   checklists of guides 03 and 07 with evidence.

Phase 6 (blocks) can start as soon as the contract and the shell exist; run them in
parallel with feature workers when their file areas do not overlap.

## Phase 6: BLOCKS — Implement the capabilities

For each block in the manifest `blocks` list, in that order, when its `when` condition
holds under the user's interview answers:

1. Read the block README. For every entry in `prerequisites`, look in the user's project
   for the capability it provides (for example an existing login). A prerequisite the
   project already satisfies is not implemented again: map to what exists. Ask only
   when you cannot tell.
2. Run the `implement-block` flow for the block (analyze, interview, clone and
   customize, implement). The manifest already names the block, so skip its discovery
   step. The block holds the implementation detail; the guide holds the phase and the
   reason. Where the block describes a stack the user's project does not use, follow the
   guide for the user's stack and record the deviation in the block's customization notes.

## Phase 7: TOOLS — Run only what is ready

For each tool in the manifest `tools` list that a guide calls for:

1. Read the tool header for usage.
2. Run `--dry-run` first and show the output; a dry run needs no key.
3. If `requires_env` names variables, check they are set before any real run. A tool
   whose variable is unset is not run for real; tell the user which variable to set
   (in their shell or a git-ignored env file; you never see the value).
4. A tool with `external_service: true` may spend money. Say what a run does and costs,
   and run it for real only after the user agrees.

## Phase 8: REPORT

End with: guides completed (checklist counts per state, with evidence for `DONE`),
blocks implemented or skipped (and why), tools run (dry or real), lead-time items still
waiting and who owns them, every `Open owner item:`, and every `Assumption:` you made,
quoted. Anything you could not verify is listed as unverified, not as done.

## Error handling

- **Kit validation fails**: show the errors, stop (Phase 2).
- **A guide contradicts the project**: say so, follow the project, and note the
  deviation in the report.
- **A block is missing from BLOCKS_ROOT**: say so and implement that part without a
  blueprint, as `implement-block` does.
- **A store console or account step cannot be automated**: hand it to the user with the
  official name of the console, the goal, and the fields the guide lists. Do not invent
  menu paths; mark any page name that is not from the guide as unverified. Then wait.
