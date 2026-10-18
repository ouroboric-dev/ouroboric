---
date: 2026-10-19
tags: [realms, readiness, ci, process]
status: resolved
post-candidate: yes
evidence: ["https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/realm-readiness.md", "yggdrasil#52", "yggdrasil#63", "helheim-go#5", "helheim-go#6", "helheim-go#7", "midgard-react#9", "midgard-react#10", "midgard-react#11", "midgard-react#12", "ouroboric#48"]
---
## Challenge

Three realms existed, and none had a definition of done. We found their gaps by chance, one run at
a time.

## Context

A realm is a repo the factory builds products in. `midgard-react` and `helheim-go` build; `asgard`
is the company's own. Each had grown its own way. No one could say what a realm must hold before a
run trusts it.

## Options

Fix each gap as a run exposed it. Or write the checklist first, assess every realm against it, and
fix the gaps in one pass.

## Decision

Write the checklist, 22 items (RR-01 to RR-22), then retrofit. The retrofit gave each build realm:

- a root `ci.yml` with one required job, `test`, that runs the tests with `YGG_REQUIRE_TEMPLATES=1`,
  so the template tests fail rather than skip;
- a `ci.yml` in each template, kept matched to the stack by a realm test, `TestTemplateCI`;
- a protected path: the ladder's rung 1 (and every web rung) refuses a task's change under
  `.github/`, so a run can't weaken its own CI;
- one `docs.sh`, byte for byte the same in both realms, with a `shared` check in `check-repos.sh`
  that fails closed;
- the org's base CI, `lint`, through the base CI rollout.

Then we filed an assessment per realm.

## Result

The counts, after the founder's verdicts on the human items:

| Realm | met | partial | missing | n/a |
| --- | --- | --- | --- | --- |
| midgard-react | 15 | 6 | 0 | 1 |
| helheim-go | 16 | 5 | 0 | 1 |
| asgard | 5 | 2 | 4 | 11 |

The assessment found a blocker (B-061). Since odin #15, a run fails when its first pointer move's
acceptance reads another new leaf. The client gallery's real runs stay blocked until it is fixed.

The other gaps became backlog entries B-055 to B-062. They include:

- product CIs read tool configs that the ladder ignores (B-055);
- `helheim-go`'s own CI skips 5 sqlc tests (B-057);
- two base images were pinned under two weeks old (B-059);
- `asgard` is not a realm leaf yet (B-060);
- packs give no reason per egress host (B-062).

`asgard` has the most missing items because it is not a realm leaf yet. Nothing here is a measured
run: the result is the assessments, not a faster factory.

## Lessons

Write the definition of done before the third realm, not after. The first assessment found a
blocker that three realms of chance had not.
