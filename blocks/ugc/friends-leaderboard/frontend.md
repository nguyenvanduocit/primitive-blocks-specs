# Frontend Patterns — Friends & Leaderboard

> Snippets below are **L3 illustrative** (see `docs/SPEC_GUIDELINES.md` section 6). Pseudocode uses TypeScript for clarity; map it to the project's UI framework through each `ADAPT` list. The ranking, week and accuracy rules live on the server (`backend.md`); the frontend renders effective values and does not recompute them.

## Component Tree

```
CommunityScreen/                  # Tab or route; readable signed out
├── LeaderboardCard/              # Standard card header (icon + title)
│   ├── PeriodSwitch              # week | all, default week
│   ├── Podium                    # Optional: first three rows, the one distinctive element
│   ├── StandingRow[]             # rank, avatar, name, level, XP, streak, accuracy
│   ├── MyRankRow                 # Pinned "Your rank #N" when not among the rows
│   ├── PublicBoardToggle         # Opt-in switch + plain-language state text (signed in)
│   └── SignInCard                # Signed out: why signing in helps; leads to the sign-in screen
└── FriendsCard/                  # Signed in only
    ├── FriendCodeBadge           # Own code, copy button
    ├── AddFriendForm             # Input + submit, normalizes the code
    ├── FriendStandingRow[]       # Viewer + friends ranked on this week
    └── GapHint                   # "N XP to pass <name>"
```

Suggested test hooks (the shipped screen used these ids): `community-period-week`, `community-period-all`, `community-board-toggle`, `community-board-state`, `standing-accuracy`, `podium-accuracy`, `community-failed`.

## UI/UX Behavior

- **Signed out**: the board is fully visible. The only prompt is the `SignInCard` at the bottom. Study and every other screen never depend on this tab
- **Signed in, listed**: own row shown with the learner's current numbers; when not within the returned rows, a pinned `MyRankRow` shows `rank` from `GET /api/board/me`
- **Signed in, hidden** (`public_board = false`): no own row, no rank; the toggle card says the learner is not shown and what that costs ("your rank is not tracked")
- **Opted in with 0 XP in the period**: listed without a rank
- **Accuracy** is rendered only when the API sends a non-null value, as "82% correct". It is not a sort key and gets no medal or color of its own
- **Refresh**: on tab open (reuse a load younger than `BOARD_REFRESH_SECONDS`), on a Refresh button, and after the toggle changes. If any part fails, keep the previous rows, show a `community-failed` notice and a retry; never blank the board

## Friend code input

<!-- PATTERN: friend-code-input -->
<!-- PURPOSE: Accept codes as people paste them ("k7mq-2xad", spaces) and reject malformed ones before any request -->
<!-- REFERENCE: language=typescript framework=generic -->
<!-- ADAPT:
       - Alphabet and length must equal the server's `FRIEND_CODE_ALPHABET` / `FRIEND_CODE_LENGTH`; fetch from the config endpoint or share a constant, never retype it
       - Framework binding: controlled input in React, `v-model` in Vue, bind:value in Svelte; set `autocapitalize="characters"`, `autocomplete="off"`, `spellcheck=false`
       - Clear the field only on success; keep it on error so the learner can fix a typo
       - Server remains the authority: the client check saves a round trip, it does not replace the server check -->

```typescript
const SHAPE = new RegExp(`^[${ALPHABET}]{${LENGTH}}$`);

export function parseFriendCode(input: string): string | null {
  const code = input.replace(/[\s-]+/g, "").toUpperCase();
  return SHAPE.test(code) ? code : null;
}

async function submit(input: string) {
  const code = parseFriendCode(input);
  if (!code) return showError("badCode");
  if (code === myFriendCode) return showError("self");
  if (friends.length >= MAX_FRIENDS) return showError("full");
  const reply = await api.post("/api/friends", { code });
  if (reply.ok) return addToList(reply.body);
  showError(MAP[reply.error] ?? "server"); // friend_not_found→notFound, already_friends→already, friends_full→full
}
```

## Own row and rank below the top

<!-- PATTERN: my-rank-row -->
<!-- PURPOSE: Decide what the learner sees about their own place without loading the whole board -->
<!-- REFERENCE: language=typescript framework=generic -->
<!-- ADAPT:
       - `me` is the `GET /api/board/me` payload: `{ listed, xp, rank, count_above }`
       - `rows` are the board rows already ranked by the server
       - Render the pinned row below the list with a visual separator; do not splice it into the ordered rows
       - Number formatting via `Intl.NumberFormat` with the app locale -->

```typescript
type MyRow = { kind: "hidden" } | { kind: "unranked" } | { kind: "inRows" } | { kind: "pinned"; rank: number };

export function myRowFor(rows: { id: string }[], me: Me | null): MyRow | null {
  if (!me) return null;                       // signed out: nothing about "me"
  if (!me.listed) return { kind: "hidden" };  // public_board = false
  if (me.xp === 0) return { kind: "unranked" };
  if (rows.some((r) => r.id === me.id)) return { kind: "inRows" };
  return { kind: "pinned", rank: me.rank ?? me.count_above + 1 };
}
```

## Opt-in toggle

<!-- PATTERN: public-board-toggle -->
<!-- PURPOSE: One switch that states, in words, what changes and what does not -->
<!-- REFERENCE: language=typescript framework=generic -->
<!-- ADAPT:
       - Role/semantics: native checkbox with `role="switch"` and `aria-checked`; visible text, not color, carries the state
       - Copy: use the privacy copy requirement in security.md, translated per supported locale; keep the list of visible fields in one i18n key shared with the first-run card and the privacy page
       - Optimistic UI is allowed, but roll back on error and show the error toast
       - After success, force a board refresh (the own row appears or disappears) -->

```typescript
async function setPublic(value: boolean) {
  const prev = state.publicBoard;
  state.publicBoard = value;                       // optimistic
  const r = await api.patch("/api/board/me", { public_board: value });
  if (!r.ok) { state.publicBoard = prev; return toastError("server"); }
  await refresh({ force: true });
}
// State text (EN), always visible beside the switch:
//   on : "You are on the public leaderboard. Anyone can see your name, level, XP, streak and accuracy."
//   off: "You are hidden from the leaderboard. People who already have your friend code can still add you."
```

## Avatar from the profile id

<!-- PATTERN: avatar-from-id -->
<!-- PURPOSE: Give every learner a stable coloured disc and an initial without storing or uploading a picture -->
<!-- REFERENCE: language=typescript framework=generic -->
<!-- ADAPT:
       - `DISCS`: the design system's colour tokens (shipped: five discs); any hash with a fixed seed works, the point is that the same id always yields the same disc
       - Initial: first grapheme of the display name, upper-cased with the locale; `Array.from` splits code points, use `Intl.Segmenter` if combined emoji matter
       - Use the public profile `id`, never the account id -->

```typescript
const DISCS = ["disc-yellow", "disc-pink", "disc-teal", "disc-blue", "disc-green"] as const;

export function avatarOf(id: string, name: string) {
  let h = 5381;
  for (let i = 0; i < id.length; i++) h = (h * 33 + id.charCodeAt(i)) >>> 0;
  const initial = Array.from(name.trim())[0] ?? "?";
  return { disc: DISCS[h % DISCS.length], letter: initial.toLocaleUpperCase() };
}
```

## Client messages

| Problem | When | Message (EN) |
|---------|------|--------------|
| `badCode` | Code fails the shape check | "That is not a friend code. Codes have 8 letters and digits." |
| `self` | Own code | "That is your own code." |
| `notFound` | 404 `friend_not_found` | "No one has that code. Check it and try again." |
| `already` | 409 `already_friends` | "You already added this friend." |
| `full` | 409 `friends_full` or local check | "Your friend list is full (50)." |
| `network` | Request failed to leave the device | "No connection. Try again." |
| `server` | Anything else | "Something went wrong. Try again." |

## UI/UX States

| State | Visual | Behavior |
|-------|--------|----------|
| Loading board | Skeleton rows (3 to 5) | No layout shift when rows arrive |
| Empty board | Short invitation: "Be the first this week" | Shown when no listed learner has XP in the period |
| Failed refresh | Notice above the list, previous rows kept | Retry button; `community-failed` hook |
| Signed out | Board + `SignInCard` | No friends card, no toggle |
| Hidden | Toggle card with "you are hidden" text | No own row, no rank |
| Adding friend | Submit disabled, spinner | Prevent double submit |
| Friends empty | "Add a friend with their code" + own code with copy | Own code is always shown to signed-in users |
| Week rollover | Board for the new week is empty until learners report | No special handling; the server filter does it |

## Styling and Accessibility

- Rank, name and XP are text; medals or colors on places 1 to 3 never carry meaning alone
- Rows are a list (`ul`/`ol`); the pinned own row has its own landmark label ("Your rank")
- The period switch is a radio group or tabs with keyboard support
- Long names truncate with ellipsis and keep the full name in the accessible name
- Render all names as plain text (no `innerHTML`, `v-html`, `dangerouslySetInnerHTML`)

## Anti-patterns

**DON'T** recompute rank, effective streak or week XP in the client from raw fields. The server returns effective values; a second implementation drifts.

**DON'T** hide a value in the UI that the API still sends (for example accuracy under 10 answers). The API must not send it; the UI must not be the only guard.

**DON'T** show the learner a "private profile" promise that the toggle does not keep. The toggle removes the board listing only; the state text must say that holders of the code can still find them.

**DON'T** gate the board behind sign-in by habit. Reading it signed out is a product requirement of this block (see `security.md`, read matrix).

**DON'T** blank the screen on a failed refresh. Keep stale rows and say they are stale.

**DON'T** log or analytics-track friend codes typed by the learner.
