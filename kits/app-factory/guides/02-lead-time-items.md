# Lead-Time Items

Some items take a day or more regardless of how fast agents code. Start them on day 0, in parallel with the build, and name who must act on each. Most of them need the owner personally.

Evidence: source playbook sections 3 and 8, and the store-submission and process-timeline appendices. Every duration and count in this guide was observed once, on one project; treat them as the scale of the wait, not as promises.

## Decision rule

Start an item on day 0 if it has an external wait, a legal or financial statement made in the owner's name, or a step only a physical person can complete.

An agent may do an action only if it is reversible and needs no identity proof. An agent stops and hands over to the owner for:

- sign-in and two-factor codes on a developer account;
- legal and tax certifications, content-rights declarations and agreements;
- passcodes, biometric prompts and anything on the owner's own phone;
- spending money or buying an account;
- deleting data.

**Bank, tax and identity data are typed by the owner and never stored or read by an agent.** The agent opens the form and stops. The owner types the bank details, the tax form fields, the legal-entity details and every passcode, and then tells the agent to continue. No such value is pasted into a file, a chat, a log or a note, and no agent reads it off a screen, a phone app or a document. If it appears on a screen by accident, the agent does not copy it.

## Default path

Start these on day 0 and track each with an owner and a status:

| Item | Observed wait (observed once, on one project) | Who must act |
|---|---|---|
| Apple developer membership (individual or organisation, owner as Account Holder) | about 24 hours to 1.5 days when renewing an expired one | Owner: purchase, identity, sign-in |
| Paid-apps agreement, bank account, tax form, EU trader decision (or remove EU storefronts) | about 40 minutes of hands-on work, then the agreement went active 26 to 37 minutes later | Owner: legal entity, bank, tax, passcodes, two-factor |
| Google Play developer account, payments profile, service account for the purchase provider | access grant propagated in about 20 to 35 minutes | Owner: sign-in, policy consent |
| Google Play closed test, only for a personal account created after 13 November 2023 | at least 14 days with at least 12 testers opted in (Google's published rule, checked 2026-10-22) | Owner: recruit the testers; start it on day 0 |
| Content permission in writing | unknown; depends on the rights holder | Owner |
| A test iPhone: unlocked, USB trust accepted, screen-recording tile in Control Center, a clean throwaway demo account | minutes | Owner |
| Privacy page matching the real data flows, support URL, a neutral contact address | 0.5 to 1 hour | Owner decides; agent drafts |
| Promo codes for Play reviewers (they must start before review) | the start date is the next day | Owner: consent to terms |

Steps that worked:

1. **Apple first.** Decide individual versus organisation and which team owns the bundle id (see guide 01). Enrol or confirm the Account Holder. Start the paid-apps agreement, bank, tax form and EU decision in the same sitting.
2. **Google Play in parallel.** Create the developer account and payments profile, publish the privacy URL on a neutral contact address, create the service account for the purchase provider, and request reviewer promo codes with a start date before submission. For the purchase flow, see the `billing.in-app-purchase` block.
3. **Test device.** Unlocked, trusted over USB, screen-recording tile added to Control Center, a clean account with no personal chats or contacts on screen. Observed once, on one project: one recording captured a personal chat and another showed the owner's email and other people's names, and both were discarded.
4. **Rights.** Confirm in writing who may license content before the first extraction agent runs.
5. **Login hygiene.** Sign in to every console once in the shared browser profile, keep the two-factor phone at hand, and schedule the submission for when the owner is available for about 3 hours. Observed once, on one project: the Apple console signed the session out several times in a few days and each status check was blocked until the owner signed in again.
6. **Keys.** Keep credentials in a project-local, git-ignored secrets folder plus a password-manager entry from the first day. Public SDK keys go in git-ignored local env files.
7. **Account deletion.** Apple requires it for any app with account creation and may ask to see it on first review. Plan the `compliance.account-deletion` block and a device recording of it early, because the recording needs the owner's phone. Sign-in providers: `auth.google-login`, `auth.sign-in-with-apple`.

A first submission from a new Apple account may be answered with an information request asking for a physical-device screen recording and written answers, not a defect. Observed once, on one project: the answer came after 21.5 hours. Prepare the recording package before the first submission.

## Checklist

- [ ] Every lead-time item above started on day 0 with an owner and a status.
- [ ] Apple membership active with the owner as Account Holder.
- [ ] Paid-apps agreement, bank and tax forms completed by the owner personally; the EU storefront decision made.
- [ ] Google Play account, payments profile and purchase-provider service account created.
- [ ] Content permission in writing on file.
- [ ] Test iPhone prepared and cleaned; clean throwaway account created.
- [ ] Privacy page and support URL live, matching the real data flows, on a neutral contact address.
- [ ] Reviewer promo codes requested with a start date before review.
- [ ] Every console signed in once; two-factor phone available; submission slot scheduled.
- [ ] Credentials stored only in a git-ignored folder and a password manager.
- [ ] Bank, tax and identity values typed by the owner; none stored, pasted or read by an agent.
- [ ] Agents stop and hand over at every sign-in, code, certification and passcode prompt; they do not retry or route around a handover.
- [ ] Any "done" reported by an agent is re-checked by re-reading the console or re-running the command.
