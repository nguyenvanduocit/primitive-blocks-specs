# Working With Agents

How the human directs the agents that build the app, and which mistakes to avoid. The numbers in this guide were observed once, on one project; the rules do not depend on them.

## Decision rule

Ask or decide, by the cost of being wrong.

- **Ask** when the choice is expensive to reverse or changes scope, money, a legal statement, account ownership, the stack, the auth provider, the backend, the business model or the content rights. Ask once, as a pick-one question with a named default and the consequence of each option.
- **Decide** when the choice is reversible and inside the stated scope. State the choice and the reason in one line, continue, and keep going. Record the line as `Assumption: X because Y` so the human can overrule it later.
- **Never** pick a risky default silently. On the source project an agent wrote "Defaults I'm choosing: own server, local database, email and password login", built it, and the human reversed all three; the work was thrown away.
- Ask decision questions, not feelings questions. "Which login providers: Google only, Google plus Apple (default), or email as well?" is a decision question. "What do you picture the user feeling?" is not. Over-asking and stopping early were the second most frequent complaint on the source project.
- If you cannot list at least two options, you do not understand the problem well enough to choose; read more before asking.

## Default path

### 1. Day-0 interview

One short interview before the first agent is dispatched, pick-one answers, named defaults (observed once, on one project: about ten minutes of human time). Ask only decisions that are expensive to reverse:

- Distribution, price and the role of the web copy.
- Content rights, in writing.
- Stack and design system, with five to ten reference apps.
- Backend tier (default: a managed backend) and login providers.
- Domain and hosting, decided once.
- Apple team and bundle id on both stores; which account owns each console (guide 05).
- Languages, and who reviews them natively.
- Acceptance criteria that are reachable (see anti-patterns).

### 2. Contract first

Coordinate through files, not chat.

- A `CONTRACT.md` has the sections listed in guide 03 (layout, view registry, hooks API, store schema, strings, tokens, test hooks, ownership, build notes). Every worker updates its own section.
- An `AGENTS.md` points agents at the store CLIs and skills for the project (guide 06, section 7). For each CLI it records the install command, the default app or app id, where the git-ignored credential file lives, the permission level that credential currently has, and the commands that read status. A read-only credential written down saves an agent from trying a release that Google will reject.
- Gate phases by data. Validate extracted content with a script before any UI work starts, and honour "do not start phase 2 until I approve".
- Stable test hooks let judges and end-to-end scripts survive restyling.

### 3. Three layers and a ledger

1. **Orchestrator.** It does not do the work. It assigns tasks to workers, checks them with its own commands, and accepts or rejects them. It keeps a ledger (objective, goals, tasks, open questions, resources, recap). A worker's "done" counts as medium confidence until the orchestrator re-runs the verify command itself. Cap rework at two rounds, then mark the task blocked and escalate to the owner. (Observed once, on one project: 61 tasks, 44 accepted.)
2. **Workers.** Each brief carries a done-when condition, a verify command and criteria. Workers code to the contract.
3. **Independent judges.** A fresh agent that did not write the code runs the owner's acceptance checklist adversarially on a frozen copy of the build, identified by a hash, with real-browser or real-device evidence. A verdict is tied to bytes; a verdict on a moving tree is stale. Judges caught what green tests missed: five rejections on the source project for defects such as a missing control, a double tap, a scroll jump on tab switch.

Real-surface verification beats unit tests for anything the user sees. A popover defect and a 30-second page expansion passed in a simulated DOM and failed in a real browser.

### 4. Standing authority

Grant authority once, in a named scope, so approval round trips stop.

- Example scope that worked: verify (typecheck, tests, end-to-end, audits), deploy, then run a fresh judge on the live bytes. Other outward actions still need approval.
- "Do it yourself" covers the named task. It does not authorise the next outward action.
- A stop condition on a worker ("do not end the turn until X is deployed") prevents agents ending with work left.
- Human-only steps (guide 06) stay human-only whatever authority was granted.

### 5. Human direction style

What worked for the human, so agents can match it:

- One large structured spec at the start, then short imperatives.
- Decisions by pointing: element annotations with a selector, or a screenshot plus one sentence.
- Pick-one questions in a Q&A panel; one-word acknowledgements for human-only steps ("done").
- A strategy question first ("what would pay best?", "is this option accepted by the stores?"), then a one-line acceptance of the recommendation.
- Routing knowledge into the repo ("add that to AGENTS.md") so the next session starts informed.
- Pointing at another agent's working method instead of re-deriving it.

What agents owe in return:

- Size every visual change to what a person can see. A nudge from 4 px to 8 px with no before and after screenshot drew "I do not see any change". Show the screenshot.
- Build verification copies into your own output directory and never start servers on the human's ports.
- Propose first when a request touches a risky default (see the decision rule).

### 6. Collisions

- Exactly one owner per file area, per console task space and per deploy. Publish the ownership list so a new session can see it.
- Lock protocol between peers: broadcast the files you hold until you broadcast done; a peer holds its build until you release.
- One deploy path (a script), run by one owner.
- Commit on a schedule. Judges need a clean tree and the shipped build must be reproducible from git. (Observed once, on one project: five days with a single commit; peers overwrote each other's files and the shipped build came from a dirty tree.)
- Fan-out amplifies a single outage. If many agents stop together on a network error, recover from the ledger and notes, not from memory of the conversation.
- Long full-suite runs stall when the laptop sleeps; keep the machine awake or run them elsewhere (medium confidence).

### 7. Memory and secrets hygiene

- Keep decisions in memory notes so new sessions do not re-ask.
- When the owner reverses a decision, delete the superseded note. A stale note ("dark theme only" after the app turned light; "needs an OAuth client" after the provider removed that need) misleads every later session.
- Keys, service accounts and keystores live in a git-ignored project-local folder, never in a global location. Policies and public pages use a role-based contact, never a personal name or address.

### 8. Anti-patterns

Each of these cost real time on the source project.

1. Starting before the stack and design system are chosen. The UI was rewritten after the owner named the toolkit they already used.
2. Building the spec's literal feature without pricing a cheaper alternative. Runtime translation of a fixed body of content was built, caused two rework rounds and a performance bug, and was replaced by shipping translated content.
3. Deciding the business model and content rights after building. Licensing surfaced on submission day.
4. Store work started in the evening before the account that owns the bundle id was ready.
5. Days without commits: judges had no clean tree and peers overwrote each other's files.
6. Several agents driving one console or one deploy at once.
7. Acceptance criteria copied from a generic checklist without checking they are reachable. A throttled performance score on an offline single-file build stalled a worker for hours until the owner redefined the criterion.
8. Keys, service accounts or personal names outside the project or on public pages.
9. Stale memory after a reversed decision.
10. Treating a green suite as done. Independent judges and real-surface checks caught defects the tests missed.
11. Feelings questions instead of decision questions; ending a turn with work left.
12. UI designed from words with no references. Several rounds of "this is cluttered" ended only when the owner supplied reference apps and a measured screenshot loop.
13. Screens built from a feature list instead of the patterns of similar apps ("looks like AI slop"). Research comparable apps first.
14. A backend or feature with no visible surface. Acceptance was tests and rules, not what the user sees.
15. Changes sized to the code, not to what is visible; agent and human looking at different servers.
16. An agent silently choosing a risky default (own server, email and password login).

## Checklist

```
BEFORE THE FIRST AGENT
[ ] Day-0 interview done: pick-one, named defaults, answers written down
[ ] CONTRACT.md and AGENTS.md exist; test hooks listed
[ ] Git repo created; commit schedule agreed
[ ] Ownership list published: file areas, console task spaces, deploy owner

WHILE WORKING
[ ] Every orchestrator acceptance backed by a command it ran itself
[ ] Rework capped at two rounds, then blocked and escalated
[ ] Independent judge runs on a frozen, hashed copy; real-surface evidence
[ ] Assumptions recorded as "Assumption: X because Y"; no risky default chosen silently
[ ] Visual changes shown as before and after screenshots
[ ] Standing authority written with its scope; human-only steps respected

CLOSING
[ ] Superseded decisions deleted from memory notes
[ ] Secrets only in the project-local ignored folder; contacts role-based
[ ] Tree clean and the shipped build reproducible from git
[ ] Open questions handed back to the owner, each with its default
```
