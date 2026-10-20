---
date: 2026-10-20
tags: [models, review, routing, measurement, cost, sandbox]
status: open
post-candidate: yes
evidence: ["https://github.com/ouroboric-dev/gleipnir/pull/14", "https://github.com/ouroboric-dev/gleipnir/pull/15", "https://github.com/ouroboric-dev/gleipnir/pull/16", "https://github.com/ouroboric-dev/odin/pull/21", "https://github.com/ouroboric-dev/odin/pull/22", "https://github.com/ouroboric-dev/odin/pull/23", "v0-H17", "run 20261020-070542-d844d0", "run 20261020-190818-5b02ff", "run 20261020-205528-86a693"]
---
## Challenge

The real-agent smoke builds a small web product with Claude Code (the implementer) and reviews it with a
cheap model on OpenRouter (the reviewer). It failed four times at the reviewer, for four different reasons. The first two were a permission and a
prompt. The last two were the model.

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

Measure on our own failure, with our own prompt, on the same product, 3 to 8 sessions per model. Two
tests: does the model give a valid report without inventing a fault, and does it still find a real fault
when we plant one. Qwen3.8 27B becomes the reviewer of the smoke.

## Result

The smoke passes with Qwen3.8 27B as the reviewer (first section). The fault-finding loop with a real fault is not proved yet (open questions, at the end). The model comparison follows. Every session ran on the same product (the
one the failed run built), with the engine's real reviewer prompt and the adapter's real settings: strict
privacy, `effort: high`, read-only permissions. "Tokens in" counts everything the model read, cache included;
the figure in brackets is what was not served from the cache. "Tokens out" includes reasoning. Averages per
session.

### The full smoke, with Qwen as the reviewer

Run 20261020-205528-86a693, the same graph and prompts as the failed runs, only the reviewer changed:

| Step | Result |
| --- | --- |
| Implementer (Claude Sonnet, on the subscription) | one session, 3 turns, 36 s, 8.1k tokens in (20.2k cached), 4.2k out, $0.079 at API prices |
| `unit` check | passed |
| Reviewer (Qwen3.8 27B) | one session, 4 turns, 50 s, 14.8k in (11.5k cached), 1.6k out, about $0.012; report: no findings |
| Merge, pointer move, grade | done; the public sample suite of the task gave reward 1.0, 6 of 6 fail-to-pass, 1 of 1 pass-to-pass |

The loop passed in its first attempt. The run took under two minutes and cost $0.09 in all (an estimate: the
implementer's figure is what the same tokens would cost on the API). The four earlier runs all ended at the
reviewer, and the last of them cost $0.12.

This run did not use the loop's repair path: the reviewer found nothing, so the implementer was never sent
back. The planted-fault tests show that Qwen reports a real fault. They do not show that the implementer
fixes it, or that Qwen then drops the finding. That needs a run with a fault the implementer actually makes.

### A product with no known fault

| Model | Sessions | Valid reports | Findings per session | Tokens in (new) | Tokens out | Cost per session |
| --- | --- | --- | --- | --- | --- | --- |
| DeepSeek V4 Flash | 8 | 6 | 0, 1, 1, 1, 0, 2 (2 answers in prose) | 36.3k (11.0k) | 10.9k (largest 19.0k) | $0.002 |
| Qwen3.8 27B | 8 | 8 | 0 in all 8 | 25.3k (7.9k) | 2.1k | $0.011 |
| GLM 5.3 Flash | 8 | 8 | 0 in 7, 1 in 1 | 20.4k (12.3k) | 6.0k (largest 18.5k) | $0.005 |
| Claude Haiku 5.5 | 8 | 8 | 1, 2, 1, 1, 1, 2, 2, 2 | 29.7k (6.1k) | 2.4k | about $0.002 (estimate) |
| Claude Sonnet 5.5 | 6 | 6 | 0 in all 6 | 26.5k (9.5k) | 0.5k | about $0.03 (estimate) |

Costs are what OpenRouter reported. It reported nothing for the two Claude models, so theirs are estimates
from list prices ($0.10 and $0.50 per million tokens for Haiku, $2 and $10 for Sonnet, cached input at a
tenth of the input price).

What the findings were:

- **DeepSeek V4 Flash** said `findIndex` is not a JavaScript method in 5 of 8 sessions (4 inside a valid
  report, 1 in an answer written as prose). One session also said that `req.destroy()` does not exist. Both
  are false. It stated the same false claim in the real smoke twice more, after the implementer had shown it
  wrong. Only 2 of 8 sessions gave a valid and clean report.
- **Qwen3.8 27B** reported nothing in all 8 sessions.
- **GLM 5.3 Flash** reported nothing in 7 sessions. The other one pointed out that `POST /api/logout` answers
  204 when there is no session. The brief lists 204 for logout, so this is a judgement call.
- **Claude Haiku 5.5** reported something in every session, nearly always that the note length is counted in
  UTF-16 code units and not in characters. It sometimes said the same of the password. That is true of the
  code and small, and in a loop it would send the implementer back for a nitpick every time.
- **Claude Sonnet 5.5** reported nothing in all 6 sessions, with the smallest output of all.

A reviewer that says "fine" every time would pass this table, so we planted faults.

### The same product with one planted fault

Three copies of the product, each with one change, as small as a real mistake:

1. `start.sh` runs `node servr.js` (a typo), so the product cannot start.
2. The server listens on port 8080, not 3000 as the brief requires.
3. `GET /api/notes` no longer reverses the list, so notes come back oldest first, against the brief.

A session counts as a catch when its report names the planted fault. We read the claims, not only a keyword
match.

| Planted fault | Model | Sessions | Caught | Findings per session | Tokens in (new) | Tokens out | Cost per session |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1. `servr.js` typo | Qwen3.8 27B | 6 | 6 | 1 in all 6 | 22.9k (5.1k) | 1.3k | $0.008 |
| 1. `servr.js` typo | Claude Sonnet 5.5 | 3 | 3 | 1 in all 3 | 22.6k (10.2k) | 0.4k | about $0.03 (estimate) |
| 2. port 8080 | Qwen3.8 27B | 6 | 6 | 1 in all 6 | 22.0k (6.5k) | 1.0k | $0.007 |
| 2. port 8080 | Claude Sonnet 5.5 | 3 | 3 | 1 in all 3 | 26.6k (3.9k) | 0.5k | about $0.02 (estimate) |
| 3. oldest first | Qwen3.8 27B | 6 | 6 | 1 in all 6 | 23.2k (4.9k) | 2.0k | $0.010 |
| 3. oldest first | Claude Sonnet 5.5 | 3 | 3 | 1 in all 3 | 26.5k (4.0k) | 0.5k | about $0.02 (estimate) |

Every report held one finding, the planted one, and nothing else. The wording was specific. For fault 1 the
models wrote that `start.sh` runs `node servr.js` and the only program file is `server.js`. For fault 2 they
quoted `server.listen(8080, '0.0.0.0')` against the brief's port 3000. For fault 3 they wrote that
`GET /api/notes` returns notes oldest first (some: "in insertion order") and the brief requires newest first.
We did not test GLM or Haiku on the planted faults.

What these tests do not show: all three faults are visible by reading a few lines. A fault that needs
reasoning across files, such as one user reaching another user's notes, is untested. The sample is small
(3 to 8 sessions a cell), and the hosted models change from hour to hour.

### Cost of the experiment

OpenRouter reported about $0.29 for the DeepSeek, Qwen and GLM sessions. The Claude sessions were not
reported. At list prices they come to about $0.45. The check on your OpenRouter dashboard is the truth.

### The reasoning effort setting

The same captured request sent six times straight to OpenRouter, with the effort not named: 2 of 6 started
the review, 4 of 6 asked what to do. With `low`, `high` or reasoning off: 8 of 8 started in each case. In whole
sessions, `high` gave 9 of 10 valid reports. Switching reasoning off gave 2 of 10: the model narrated before
its answer and invented more faults.

Open questions, to answer in this entry:

- Answered: the smoke passes end to end with Qwen as the reviewer (reward 1.0, $0.09).
- Does the repair path work with Qwen: a real finding, a fix by the implementer, and the finding closed?
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
- Output narrows the price gap between models. Sonnet costs 40 to 60 times more per token than DeepSeek, but
  it wrote 0.5k tokens a session against 10.9k, so a session cost it about 15 times more (an estimate).
- A reviewer's precision matters more than its recall in a loop with no arbiter. One false blocker ends
  the run.
- Test the reviewer on a product with a known fault, as well as one without. A reviewer that always says
  "fine" scores perfectly on a good product.
