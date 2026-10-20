---
date: 2026-10-20
tags: [models, review, routing, measurement, cost, sandbox]
status: open
post-candidate: yes
evidence: ["https://github.com/ouroboric-dev/gleipnir/pull/14", "https://github.com/ouroboric-dev/gleipnir/pull/15", "https://github.com/ouroboric-dev/gleipnir/pull/16", "https://github.com/ouroboric-dev/odin/pull/21", "https://github.com/ouroboric-dev/odin/pull/22", "https://github.com/ouroboric-dev/odin/pull/23", "v0-H17", "run 20261020-070542-d844d0", "run 20261020-190818-5b02ff"]
---
## Challenge

The real-agent smoke builds a small web product with Claude Code (the implementer) and reviews it with a
cheap model on OpenRouter (the reviewer). It failed three times at the reviewer, each time for a different
reason. The first two looked like wiring faults. The third was the model.

## Context

The reviewer was `deepseek-v4-flash`: about 5 cents per million input tokens, a provider that keeps no
data, and a good price for a role that only reads. The loop gives the reviewer two tries to answer in a
fixed JSON format. A reviewer that cannot answer twice in a row stops the run.

## Options

What went wrong, in the order we found it:

1. **A folder outside the sandbox.** The brief said `/app`. The reviewer tried to read it, the tool asked
   for permission, nobody could answer, and the session ended with no text. Fix: deny reads outside the
   leaf, and tell the reviewer where the product is.
2. **A prompt that asked for the impossible.** The reviewer could not run commands, but its prompt told it
   to start the product with `curl`. It spent all its steps on that and wrote a summary in prose. Fix: say
   what the reviewer cannot do, and deny sub-agents and questions.
3. **A model that thinks the message is empty.** The model answered "What would you like help with?" to
   its whole prompt, in about half of the sessions. We first blamed the wiring and proved it fine: the
   prompt reaches the model whole. The cause was in the model's own reasoning ("there's no actual user
   query yet"). It happened only when the request named no reasoning effort. With one named, it stopped.
   Fix: name `high` on every OpenCode session.
4. **A model that is sure of a false fact.** With 1 to 3 fixed, the loop ran for the first time. The
   reviewer reported that `findIndex` is not a JavaScript method. The implementer checked, said so, and
   changed nothing. The reviewer repeated the claim twice. Nothing in the loop settles a dispute, so the
   run stopped.

Candidates for the reviewer, from OpenRouter's list of models with zero-data-retention endpoints that
support tools: Qwen3.8 27B, GLM 5.3 Flash, Claude Haiku 5.5, Claude Sonnet 5.5, and DeepSeek V4 Flash as the
control. Public benchmarks do not measure code review: they measure writing code or general ability, so
they only ranked the candidates. We ran our own.

## Decision

Measure on our own failure, with our own prompt, on the same product, 6 to 8 sessions per model. Two
tests: does the model give a valid report without inventing a fault, and does it still find a real fault
when we plant one. Qwen3.8 27B becomes the reviewer of the smoke.

## Result

Pending: the full smoke has not passed yet. What we have, from about 20 cents of calls:

| Model | Valid report | Invents a fault |
| --- | --- | --- |
| DeepSeek V4 Flash | 6 of 8 | 6 of 8 sessions |
| Qwen3.8 27B | 8 of 8 | never |
| GLM 5.3 Flash | 8 of 8 | never |
| Claude Haiku 5.5 | 8 of 8 | never; reports a minor point every time |
| Claude Sonnet 5.5 | 6 of 6 | never |

Planted faults (a typo in `start.sh`, the wrong port, notes in the wrong order): Qwen3.8 27B reported the
planted fault and nothing else in 18 of 18 sessions; Sonnet 5.5 in 9 of 9. A Qwen session costs about one
cent. The reviewer's price per token matters less than its output: a strong model such as Sonnet writes
about 400 tokens per review, and a weak reasoning model wrote 10,000.

Open questions, to answer in this entry:

- Does the smoke pass end to end with Qwen as the reviewer?
- Does Qwen find a subtler fault, such as one user reaching another's notes?
- Would Qwen also work as the implementer? Claude Code runs on a flat subscription, so the implementer
  costs nothing per run, and a swap only pays when that limit binds.

## Lessons

- A model that fails the same way every time is a fact about the model, not the wiring. We spent two
  fixes on the wrong cause before we captured what the model saw.
- Our first trials looked good (12 of 14) and then failed the next hour with the same prompt. A model
  behind a hosted provider changes under you. Repeat a trial later before you trust it.
- Choose the reviewer on the failure you have, not on a leaderboard. No public number tests whether a
  model invents a fault.
- A reviewer's precision matters more than its recall in a loop with no arbiter. One false blocker ends
  the run.
- Test the reviewer on a product with a known fault, as well as one without. A reviewer that always says
  "fine" scores perfectly on a good product.
