---
title: Local Qwen 3.8 27B coding assistant, notes
status: accepted
date: 2026-10-20
style: research
related: [2026-10-19-local-qwen-design.md, 2026-10-19-local-qwen-plan.md]
---

# Local Qwen 3.8 27B coding assistant, notes

What it took to run Qwen 3.8 27B on one RTX 4090 under WSL2, how fast it is, and how it compares
with hosted Claude. The design is [2026-10-19-local-qwen-design.md](2026-10-19-local-qwen-design.md).

## Setup

Done on 2026-10-19 and 2026-10-20. The steps to repeat it are in
[2026-10-19-local-qwen-howto.md](2026-10-19-local-qwen-howto.md). What happened along the way:

- **Versions.** CUDA toolkit 13.3 (`cuda-toolkit-13-3`, which matches the driver's CUDA 13.3), cmake
  4.4.4, OpenCode 2.0.32 (the Homebrew formula is `opencode`, not `sst/tap/opencode`), and llama.cpp at
  `4c3c581` (2026-10-19, version 0.7.0-dev, build 50).
- **The build failed twice with Homebrew first on `PATH`.**
  - Homebrew's `ld` did not search the CUDA library folder (`undefined reference to
    cudaGetLastError@libcudart.so.13`).
  - Homebrew's OpenSSL needs glibc 2.38, and Ubuntu 22.04 has 2.35 (`undefined reference to
    __isoc23_strtol@GLIBC_2.38`). llama-server uses OpenSSL only to download models, so it is turned
    off.
- **The model file.** UD-Q4_K_M (16.46 GB), with the 1.37 GB MTP draft file. It leaves about 1 GB more
  for the context than UD-Q4_K_XL (17.56 GB) does. The design targets about 100K tokens of context,
  and Windows already holds about 2.1 GB of the card's 24 GB. [ANALYSIS]
- **The flags, checked against this build's `--help`.**
  - MTP is `--spec-type draft-mtp -md mtp.gguf -ngld all`, and the draft's KV cache is `q8_0` too.
  - Reasoning effort has native flags: `--reasoning-effort low|medium|xhigh`, and `--reasoning off`.
  - At 102,400 tokens of context with MTP, the card holds 23.5 of 24.6 GB, Windows included.
- **Claude Code needed two fixes.**
  - It sends hook context, such as superpowers' SessionStart text, as a `system` message in the
    middle of the conversation. The model's template refuses any system message after the first
    (`Jinja Exception: System message must be at the beginning.`), so every request failed with HTTP
    500. `qwen-local.sh template` saves a copy that renders such a message as a system turn.
  - Claude Code does not know the model, and assumes 200K tokens of context. `qwen-claude.sh` sets
    `CLAUDE_CODE_MAX_CONTEXT_TOKENS` to the server's real context.

First run (2026-10-20), with a 30-token coding prompt at low effort:

- Decode speed was 98.5 tokens per second.
- MTP accepted 210 of 309 drafted tokens (68%).
- The reasoning was 887 characters long.

`/v1/messages`, the Anthropic Messages API, answered with a `thinking` block and a `text` block.

Smoke runs (2026-10-20). Each was asked which files in `scripts/` start with `qwen`, and each made a
tool call and answered correctly:

- OpenCode: 8 seconds. After the `--standalone` fix (see [Measurements](#measurements)), 4.5
  seconds with `run --auto`.
- Claude Code, after the template fix: 14 seconds.

## Measurements

All measurements were taken on 2026-10-20, with UD-Q4_K_M at a 102,400-token context and a q8_0 KV
cache. The figures are the server's own timings for each request (`timings` in the
`/v1/chat/completions` response, and `print_timing` in the server log). The short prompt asked for a
Go duration parser with table-driven tests (75 tokens, 512 tokens out).

| Run | Decode (tokens/s) | Prompt (tokens/s) | MTP drafts accepted | VRAM in use |
| --- | --- | --- | --- | --- |
| Short prompt, MTP on (3 runs) | 83.9 median (82.3–92.2) | about 180 (cold) | 58–67% | 23.5 GB |
| Short prompt, MTP off (3 runs) | 46.5 median (46.3–46.6) | about 200 (cold) | none | 21.2 GB |
| 94,975-token prompt of Go source, MTP on | 68.6 | 1,987 (48 s to read it) | 82% | 23.6 GB |

- **MTP pays.** It gives about 1.8 times the decode speed, for about 2.3 GB of VRAM. [ANALYSIS]
- **The full context fits.** About 95K tokens of context loaded and answered, with no out-of-memory
  error. The design's floor of 64K was not needed, so the default stays at 102,400.
- **Speed at long context.** Decode slowed to about 69 tokens per second at 95K tokens filled, which
  is still above the 40 target. The cost of a long context is in reading it: about 2,000 tokens per
  second, so a fresh 95K-token prompt takes about 48 seconds. Later turns reuse the prompt cache.

**Reasoning effort.** The server was restarted at each level, then given the short prompt with a
20,000-token cap. Each level was run once, so these are rough figures:

| `QWEN_EFFORT` | Output tokens | Reasoning (characters) | Wall time |
| --- | --- | --- | --- |
| `low` | 2,635 | 4,777 | 27.0 s |
| `medium` | 2,365 | 4,138 | 23.9 s |
| `xhigh` (the model's default) | 6,042 | 19,928 | 67.8 s |

`xhigh` spent about four times the reasoning of `low`, for the same small task. `low` and `medium`
were about the same on this prompt. [ANALYSIS]

**Per-request effort.** The template adds different instructions for each level, so the prompt's
token count shows which level a request got: 75 tokens at `low`, 45 at `medium` and 87 at `xhigh`.

- **The OpenAI API honours it.** `"reasoning_effort": "xhigh"` in a `/v1/chat/completions` request
  overrides the server's default.
- **OpenCode can send it.** A capture of its requests showed that a model's
  `"options": {"reasoningEffort": "xhigh"}` arrives as `reasoning_effort`. Its title requests ask for
  `low`.
- **The Anthropic API ignores it.** `/v1/messages` gives the same prompt whatever
  `output_config.effort` or `thinking` says. Claude Code sends `effort: high` and adaptive thinking,
  and the server ignores both. For Claude Code, only the server's `QWEN_EFFORT` counts.

**OpenCode's background service.**

- OpenCode 2 starts `opencode serve --service` on first use. Later `opencode run` calls connect to it,
  and it keeps the config and environment it started with. A new `OPENCODE_CONFIG_CONTENT` was
  silently ignored, so the launcher's provider limit and credential stripping would not have applied.
- `qwen-opencode.sh` now always passes `--standalone`, which gives each session a private server. The
  flag must come after `run` (`opencode run --standalone`), or first for the interactive session.
- In standalone mode, a headless `run` that calls a tool waits for approval, with no way to give
  it. Pass `--auto` to approve tools in a run you trust.

**Only the local server got model calls.**

- Every model call in the smoke runs appears in the server log as a slot task.
- The launcher tests prove that `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN` and
  `OPENROUTER_API_KEY` never reach either tool.
- The two capture runs, pointed at a dummy server, showed that each tool sends its model calls only
  to the configured base URL. Claude Code sent one `/v1/messages` request; OpenCode sent 13
  `/v1/chat/completions` requests.

Verified on 2026-10-20.

## Comparison

**The task.** The founder chose backlog item B-071 in `odin`: `Advance` had no `default` case, so a
graph node of an unknown kind passed silently. Each run started from `odin` `bc973e3`, in a
throwaway worktree.

**The setup.**

- All three runs got the same prompt: fix it, add a test, run `go test ./internal/engine/` (about 90
  seconds), do not commit, and do not ask questions.
- They ran headless, by the founder's choice:
  - OpenCode with `run --auto`.
  - Claude Code with `-p --permission-mode acceptEdits`, and Bash limited to `go`, `gofmt`,
    `git diff` and `git status`.
- The server ran at `QWEN_EFFORT=low`, with MTP on.

| Run | Wall time | Turns or requests | Tokens | Result |
| --- | --- | --- | --- | --- |
| OpenCode + local Qwen | 508 s | 46 tool calls, 42 model requests | 131,591 prompt tokens read and 21,137 generated (server log); largest context 91,707 | `default` case + test; `go test` and `go vet` pass |
| Claude Code + local Qwen | 551 s | 64 turns, 54 model requests | 109,008 prompt tokens read and 25,005 generated (server log); largest context 76,439 | `default` case + test; `go test` and `go vet` pass |
| Claude Code + hosted Sonnet | 146 s | 12 turns | 20 input + 295,376 cache-read + 31,908 cache-write, and 4,403 output; $0.20 of usage | `default` case + helper + test; `go test` and `go vet` pass |

**How the results were checked.**

- `go vet ./...` and `go test ./internal/engine/` ran in each worktree after the runs.
- Each new test was run again with `-count=1`.
- Each new test was then run against the original `engine.go`. All three failed there with the bug's
  symptom (`Status:done`, when the test wants a failed run), so each test does catch the bug.

**The three fixes.**

- All three chose the engine's existing failure path: a `nodeFailure` that `fail()` turns into a
  failed run, with `bad_manifest` in the error.
- **Hosted Sonnet** added a helper. It uses the `gungnir.GradeBadManifest` constant, logs a
  `node_failed` event, and repeats the node ID in the message (which `fail()` already adds).
- **OpenCode** noticed that `fail()` adds the node ID, and left it out of its message on purpose.
- **Claude Code on Qwen** wrote the smallest change. Both Qwen runs wrote `bad_manifest` as a
  string, not as the constant.

**Retries.** None of the runs needed a correction. Two earlier attempts of the local runs ended
when the kernel's out-of-memory killer stopped `llama-server` (see [Lessons](#lessons)); those
attempts are not counted above.

The diffs, the prompt and the run summary are kept in
[2026-10-19-local-qwen-comparison/](2026-10-19-local-qwen-comparison/). The founder took no fix from these
runs into `odin`, and B-071 stays open in the backlog. The worktrees were removed after the pull
request.

Claude Code puts an "estimated cost" of $2.37 on the local run. It prices the local model's tokens
as if they were Anthropic's; the real cost was GPU time and electricity.

## Lessons

- **Local Qwen did the real task.** Both local harnesses produced a correct, tested fix to a real
  backlog item, with a test that fails without the fix. It took about 3.5 to 4 times the hosted
  run's wall time, and no subscription usage. [ANALYSIS]
- **The hosted model was more efficient and slightly more thorough.** It took 12 turns, against 46 to
  64 for the local model, and used the package's constant and event log. The local runs read more
  code before they acted: OpenCode's context reached 91,707 tokens, close to the 102,400 limit.
  [ANALYSIS]
- **On this task, OpenCode and Claude Code were about even on Qwen.** OpenCode was a little faster and
  more careful about the message. Claude Code made a smaller diff. [ANALYSIS]
- **Qwen handled superpowers well enough.** The local Claude Code had the founder's superpowers
  plugin, whose SessionStart text tells the model to use skills first. The task prompt said not to
  ask questions, and the run went straight to the work. [ANALYSIS: one run only.]
- **System RAM, not VRAM, was the binding limit.** The GPU held the model and the context with room
  to spare. The kernel's out-of-memory killer stopped `llama-server` three times under WSL's 12 GB
  cap, because two llama-server defaults keep state in system RAM:
  - the prompt cache, `--cache-ram`, 8 GB by default;
  - for this hybrid model, 32 context checkpoints of its recurrent state, which grew the server from
    2.0 to 5.7 GB in a 20-turn test.

  With `--cache-ram 2048` and `--ctx-checkpoints 4`, the server peaked at 3.0 GB during both local
  runs. On the founder's request, `.wslconfig` now gives WSL 20 GB (it was 12 GB). That takes effect
  after `wsl --shutdown`.
- **Each harness had a surprise.**
  - Claude Code sends hook context as a mid-conversation `system` message, which Qwen's template
    refuses. The fix is a saved template.
  - Claude Code does not know the model's context size and assumes 200K.
  - Claude Code's effort settings are ignored by `/v1/messages`.
  - OpenCode 2's background service ignores a new config, so the launcher passes `--standalone`.
  - OpenCode's `run` waits for a tool approval that a headless run cannot give, so pass `--auto`.
- **The remaining unfairness.** The local Claude Code shares the personal setup's three plugins,
  its skills and its merge hook. It differs from the hosted run in these ways:
  - The hosted run had the personal auto-memory and the claude.ai connectors. Neither was relevant
    to this task.
  - `~/.claude-personal/settings.json` sets `defaultMode: auto`, a permissions allowlist, and
    `effortLevel` (`high` for Opus 5.5). The local config uses `defaultMode: default` and has no
    allowlist. All three headless runs overrode the mode with `acceptEdits` and the same Bash
    allowlist. The local server ignores Claude Code's effort setting.
  - Each configuration ran once, so the timing and token figures are one sample each.
- **The skills link is a write path.** `~/.claude-qwen/skills` links to `~/.claude-personal/skills`, so
  the local model sees the same skills, as the founder asked. A local session could change a personal
  skill through that link, for example with skill-creator, but only through an action that the
  founder approves. Copy the skills instead if that matters more than staying in sync.
