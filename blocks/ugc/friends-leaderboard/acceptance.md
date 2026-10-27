# Acceptance Checklist — Friends & Leaderboard

Claude Code runs this checklist after implementation, before reporting done. Tests are generated from the `.feature` files and `fixtures/*.json`; invariant ids (I-1..I-10) refer to `security.md`. Fixture clock: `2026-10-21T12:00:00Z`.

## Database

- [ ] Migration runs successfully (`board_profiles` and `friend_links` created)
- [ ] `UNIQUE (tenant_id, account_id)` and `UNIQUE (tenant_id, friend_code)` exist on `board_profiles`
- [ ] `UNIQUE (tenant_id, owner_profile_id, friend_profile_id)` exists on `friend_links`
- [ ] `CHECK (owner_profile_id <> friend_profile_id)` is active (insert a self-link directly and see it fail)
- [ ] Range `CHECK`s are active on `xp`, `level`, `streak_days`, `answered`, `accuracy`, `week_xp`
- [ ] `board_profiles.account_id` is a foreign key to `accounts.id` (not `users.id`); a guest account holds a profile and a row on the board before it links
- [ ] Foreign keys cascade: deleting an account removes the profile; deleting a profile removes links in both directions
- [ ] Board queries use the two partial indexes (check the query plan for both periods)
- [ ] All queries include `tenant_id` in the `WHERE` clause

## Friend code

- [ ] Every code the generator produces matches `^[ABCDEFGHJKMNPQRSTVWXYZ23456789]{8}$` (generate 10,000 and check)
- [ ] Generation uses a CSPRNG and unbiased sampling (no bare `byte % 30`)
- [ ] All `accepted` and `rejected` vectors in `fixtures/friend-codes.json` normalize as listed
- [ ] A forced collision on the UNIQUE index triggers a redraw; after `FRIEND_CODE_ATTEMPTS` collisions the response is 503 `no_free_friend_code`
- [ ] `friend_code` cannot be changed by any endpoint (I-6)

## Profile

- [ ] `PUT /api/board/me` creates the profile once and is idempotent; two simultaneous first calls produce one row
- [ ] New profile has `public_board = PUBLIC_BOARD_DEFAULT`, `xp 0`, `level 1`, `week_xp 0`, `week_start_day` of the current week
- [ ] Display name is trimmed, whitespace-collapsed, at most `MAX_DISPLAY_NAME` characters, and falls back to `Learner`
- [ ] `PATCH /api/board/me` accepts only `public_board`; any other field returns 422

## Board

- [ ] `GET /api/board?period=week` at the fixture clock returns exactly `expected.week_board` from `fixtures/profiles.json`, in that order, with those ranks
- [ ] `GET /api/board?period=all` returns exactly `expected.all_board`
- [ ] Both work **without a session**
- [ ] Hidden (`public_board = false`), zero-XP and stale-week learners are absent from the boards they do not qualify for (I-3)
- [ ] Equal XP shares a rank and the next rank skips (1, 1, 3, 4)
- [ ] Order is XP, then effective streak, then name (case-insensitive), then id, applied **before** `LIMIT`
- [ ] Rows never exceed `BOARD_SIZE`, regardless of any client parameter
- [ ] Effective streak is `0` when the last write is before the start of yesterday (UTC)
- [ ] Accuracy is `null` below `MIN_ANSWERED_FOR_ACCURACY` answers and is never used in ordering
- [ ] `GET /api/board/me` returns `rank = count_above + 1` when listed, `null` when hidden or at 0 XP
- [ ] Repeating the request with `public_board=false` or any other extra parameter does not change the rows

## Report progress

- [ ] Every `valid` case in `fixtures/progress-reports.json` ends in its `after` state
- [ ] Every `invalid` case returns 422 `invalid_stats` and leaves the stored profile unchanged
- [ ] `xp`, `level`, `answered` never decrease through a report (I-7)
- [ ] Weekly credit equals `min(xp gain, 500 + floor(hours * 2000))`; the first report credits 0; a new week starts from base 0 (I-8)
- [ ] `updated_at` and `week_start_day` come from the server clock; a body field naming them is rejected
- [ ] Two simultaneous reports for the same profile serialize (row lock or `BEGIN IMMEDIATE`) and neither is lost
- [ ] Reset sets exactly the zero state and keeps `friend_code`, `created_at`, `public_board` (I-9)
- [ ] If `REPORT_MIN_INTERVAL_SECONDS > 0`, a second report inside the interval returns 429 (extrapolated feature)
- [ ] With `REQUIRE_ATTEMPT_PROOF = true`, the weekly credit is granted only when `attemptState(account_id, attempt_id)` is `confirmed`, `won` or `failed`; `open`, `cancelled`, `expired`, `rejected`, an unknown id and a missing id credit `0` and return 200 (the `unplayed-attempt-credits-nothing` case and the outline in `report-progress.feature`)
- [ ] With the setting off (default), a report is credited as before and no attempt lookup is made
- [ ] The report body accepts `attempt_id` as its only optional key and rejects a malformed one with 422 `invalid_stats`; no response or log carries the attempt state of another account

## Friends

- [ ] `POST /api/friends` with a valid code returns 201 and the public projection; the friend's own list is untouched
- [ ] A hidden learner can be added by code and then appears in the adder's list
- [ ] Errors: `invalid_friend_code` 422, `friend_not_found` 404, `cannot_add_self` 422, `already_friends` 409, `friends_full` 409
- [ ] The cap holds under concurrency: 2 simultaneous adds at `MAX_FRIENDS - 1` produce exactly one success (I-10)
- [ ] `GET /api/friends` returns the viewer plus friends ranked on effective week XP, and `gap` matches `expected.friends_of_eve_week`
- [ ] `DELETE /api/friends/:profile_id` returns 204 whether or not the link existed, and frees a slot
- [ ] Deleting a friend's account removes the link and the slot it used

## Authorization and privacy

- [ ] No endpoint accepts a profile id and returns a profile that is not listed and not in the caller's friend links (I-4)
- [ ] No response contains `account_id`, `tenant_id`, `answered`, `public_board` (of others) or timestamps; rows contain exactly the projection fields (I-2)
- [ ] No table, endpoint or log in this block stores or returns individual answers (I-5)
- [ ] All signed-in endpoints return 401 without a session; `account_id` and the profile are derived from the session only (I-1)
- [ ] Hiding from the board does not revoke existing friend links (documented behavior) and the toggle text says so
- [ ] Account deletion (`compliance.account-deletion`) removes the profile and all links, and the old code resolves to 404
- [ ] Failed friend-code lookups are rate-limited per account (`FRIEND_LOOKUP_RATE_LIMIT`) and the codes themselves are not logged

## Frontend

- [ ] The Community screen renders the board for a signed-out user and offers sign-in without blocking any other screen
- [ ] Period switch toggles `week` and `all`; the default is `week`
- [ ] Own row is pinned with the correct rank when the learner is below the returned rows; hidden learners see the hidden state and no rank
- [ ] The opt-in toggle shows state text that lists the visible fields and the limits of hiding; a failed change rolls back
- [ ] A failed refresh keeps the previous rows and shows a retry notice
- [ ] Friend code input accepts `k7mq-2xad` and `  K7MQ 2XAD `, and shows `badCode` for the `rejected` vectors without sending a request
- [ ] All names render as plain text (no raw HTML injection path)
- [ ] Verified on the surface the learner sees: open the screen on a phone-width viewport and a desktop viewport with the seeded fixtures and compare to `expected.*` (a passing API test alone is not enough)

## Privacy copy

- [ ] First-run or sign-in copy lists the six points in `security.md` "Privacy Copy Requirement" before the learner is first listed
- [ ] The privacy policy sentence about the board names exactly the fields of the projection (display name, level, XP, streak, accuracy, friend code) and says the board is readable without signing in
- [ ] The label the policy uses for the screen matches the label in the app

## Security

- [ ] No hardcoded secrets; fixtures contain only synthetic ids and names
- [ ] Board and friend endpoints are rate-limited per client; board responses are cacheable for `BOARD_REFRESH_SECONDS`
- [ ] Product owner has been told in writing what the bounds do not stop (`security.md` T-1: forged all-time XP, per-report weekly burst, free streak and accuracy) and has accepted that the board has no real stakes
- [ ] A way to report or hide an abusive name is provided, or the decision not to provide one is recorded (T-6)

## Type Safety & Build

- [ ] `tsc --noEmit` passes (or equivalent type check for the project)
- [ ] Request bodies validated at the API boundary with unknown keys rejected
- [ ] All `.feature` scenarios pass as automated tests on the merchant's stack
