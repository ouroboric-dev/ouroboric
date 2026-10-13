---
title: Budget
status: accepted
date: 2026-10-12
related: [charter.md, readiness/2026-10-11-ready-to-build.md]
style: direction
---

# Budget

What **Ouroboric itself** spends, and the caps that enforce it. The charter's boundary applies:
cost-conscious, with hard caps everywhere.

## Scope

- **Covered:** Ouroboric's own work. That means building and improving its factories, and the runs in
  which Yggdrasil builds Ouroboric's own demonstration and benchmark products, such as client gallery
  lite.
- **Not covered:** what operators build. An operator who runs a factory sets their own budget, caps,
  subscriptions and keys in their own factory configuration, and is responsible for the software
  they produce with it. The factory provides the mechanism (the caps and the `budget-cap` hard
  approval point) and enforces whatever limits the operator sets. The figures below are Ouroboric's
  choices, not defaults for operators.

## Accounts

- **Decided 2026-10-13:** the factory runs on the founder's **personal Claude subscription, which the
  founder started for Ouroboric**. It replaces the 2026-10-12 decision to buy a second, dedicated one.
  It is never an employer's account, so ownership of the factory's output stays clear (readiness
  RB-10). The founder's sessions that build the factory share its quota with factory runs, so the
  per-run and per-day caps below matter from the first run. Run metrics come from the factory's own
  ledger (`ygg metrics`), not from the subscription's usage page, so the shared quota doesn't mix them.
- **Decided 2026-10-12:** API spend goes through **one OpenRouter key with a hard credit limit of $25
  a month**. It pays for running a role on another model or agent tool (v0 success criterion 2) and for
  routing experiments. **Decided 2026-10-13:** the key runs open-weight models only, chosen for cost.
  Claude runs on the subscription, never through this key.
- The factory authenticates to Claude with a token from `claude setup-token`, created for the factory
  only, so it can be revoked without touching anything else (readiness RB-14).

## Caps

- **Decided 2026-10-12:** default caps, enforced by the `budget-cap` hard approval point (v0 spec
  §7.4). A run that hits a cap stops with everything resumable.

| Cap | Turns | Tokens | API spend |
|---|---|---|---|
| per run | 400 | 8M | $5 |
| per day | 1,000 | 20M | $10 |

The per-run cap fits one full client-gallery build with retries; the daily cap allows two or three
runs. The OpenRouter key's credit limit is the backstop behind both: even if every cap failed, API
spend can't exceed $25 a month.

## Keeping keys safe

- Keys and tokens live in a password manager and in an environment file outside every repository
  (for example `~/.config/ouroboric/factory.env`, readable only by its owner). They never go into a
  repository, a chat, a ticket or a log.
- A key pasted into a chat stays in its transcript. A key committed to a public repository is copied
  by scanners within minutes, even if the commit is removed right after. `gitleaks` and GitHub push
  protection are there to catch mistakes, not to replace care.
- If a key leaks, revoke it first, then investigate.

## Review

Revisit this budget after v0's first real runs, using `ygg metrics`: cost per task and the share of
the subscription's limits that a run uses.
