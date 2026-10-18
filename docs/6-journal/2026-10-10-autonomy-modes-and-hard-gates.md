---
date: 2026-10-10
tags: [graph, gates, safety, cost]
status: open
post-candidate: yes
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#7-approval-points-and-autonomy-modes]
---
## Challenge

How hands-on should the human be while the factory runs?

## Context

At first the operator wanted approval at key points, with a way to switch between step-by-step,
key-points and unattended.

## Options

A fixed mode, or configurable approval points.

## Decision

Every approval point is soft (the mode decides) or hard (always stops). Hard ones: production deploy,
app store submission, real secrets or user data, budget cap, work from unapproved external sources,
policy violations, shrink-guard trips. At startup, the factory rejects any config that tries to
switch off a hard approval point.

## Result

Pending.

## Lessons

The budget cap is hard because of an ordinary failure: a flaky test makes an unattended loop
re-run the implementer all night, the subscription's weekly quota is gone by Monday, and the
operator's normal work is rate-limited too. In unattended mode, mistakes don't stay small. They
snowball, so a few stops must exist in every mode.
