---
title: Local Qwen 3.8 27B coding assistant
status: accepted
date: 2026-10-19
style: spec
---

# Local Qwen 3.8 27B coding assistant

## 1. Intent

The founder wants a coding assistant that runs on their own machine: Qwen 3.8 27B on the RTX 4090,
driven by OpenCode, and also by Claude Code for comparison. There are three reasons:

- **Limits and cost.** Claude subscription limits and paid API usage cap how much agentic work
  happens in a day. A local model has no rate limit and no per-token bill.
- **Curiosity and learning.** The founder wants to understand local inference: quantization,
  context memory, reasoning effort, speculative decoding, and how agent tools behave on a smaller
  model.
- **Groundwork.** OpenCode is the harness that Yggdrasil's Gleipnir already drives. Lessons about its
  configuration and failure modes carry over.

**Split from Yggdrasil.** Routing Yggdrasil roles to Qwen is a separate track. It uses the OpenRouter
path that already exists (`openrouter/qwen/qwen3.8-27b`) and is out of scope here. Hosted Qwen 3.8 27B
costs about $0.02 per million input tokens and $0.50 per million output tokens on
[OpenRouter](https://openrouter.ai/qwen/qwen3.8-27b), so local inference does not win on cost for
Yggdrasil. It wins on limits, privacy, offline use and learning.

## 2. Goals

1. One command starts the model server, and one command stops it.
2. OpenCode, connected to the local server, completes a real small task in one of the founder's
   repos.
3. Claude Code, connected to the same server, completes the same task, so the two harnesses can be
   compared on one model.
4. The setup reaches about 100K tokens of context and records the measured decode speed. The target
   is 40 tokens per second or more.
5. A short notes page records what the founder learned: the settings that mattered, where each
   harness struggled, and how the result compares with Claude.

## 3. Non-goals

- Yggdrasil integration (see §1).
- Parallel sessions or serving other people. One session at a time.
- vLLM, SGLang, or a Windows-native server.
- Community forks of llama.cpp (for example [ninfer-4090](https://github.com/sergiuszm/ninfer-4090)
  or BeeLlama). They are candidate follow-ups for curiosity, not part of this work.
- Vision input, fine-tuning, or other models.

## 4. Anti-goals

These make the work a failure even if the model runs:

- **The Claude account split breaks.** The founder runs two Claude Code accounts, split by folder
  (a work folder with `~/.claude`, a personal folder with `~/.claude-personal`),
  with `claude`, `claude-work` and `claude-personal` shell functions in
  `~/.config/claude-accounts.zsh` and an `account-guard.sh` hook in each config. The local setup MUST
  NOT change either config dir, either login, or the `claude` function's routing. Local Claude Code
  MUST use its own config dir and its own command, and MUST NOT log in to an Anthropic account.
- **Requests leave the machine.** The local Claude Code and OpenCode MUST send model requests only to
  the local server. Local Claude Code SHOULD turn off non-essential traffic
  (`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`).
- **A pile of one-off commands.** The setup MUST be repeatable from the repo (see §6).

## 5. Constraints

Measured on 2026-10-19:

| Item | Value |
| --- | --- |
| GPU | NVIDIA RTX 4090, 24 GB; about 2.1 GB already used by the Windows desktop |
| Driver | NVIDIA 610.57 (WSL), CUDA 13.3 user-mode driver |
| CPU | AMD Ryzen 7 7800X3D, 8 cores, 16 threads; WSL gets 12 |
| RAM | 32 GB on Windows; WSL is capped at 12 GB by `C:\Users\Bruno\.wslconfig` |
| Disk | about 708 GB free on `/` |
| OS | WSL2, Linux 6.18; shell zsh |
| Already installed | gcc, podman (aliased as `docker`, runtime crun). Not installed: CUDA toolkit (`nvcc`), cmake, llama.cpp, OpenCode. No NVIDIA CDI spec for podman |

The model (from [Hugging Face](https://huggingface.co/Qwen/Qwen3.8-27B)):

- 27B dense, Apache 2.0, 262,144-token native context.
- Hybrid layout: of the 64 layers, only 16 use full attention (4 KV heads, head dim 256). The other
  48 are Gated DeltaNet with a fixed-size state. The KV cache is therefore about 64 KB per token at
  16 bits, or about 32 KB at 8 bits. [ANALYSIS: 16 layers × 2 × 4 × 256 × 2 bytes.]
- Trained with multi-token prediction (MTP), which llama.cpp can use for speculative decoding.
- Thinking is on by default, and `reasoning_effort` defaults to `xhigh`. Levels are `xhigh`,
  `medium` and `low`; `enable_thinking` turns thinking off. Qwen notes that low effort can make
  multi-turn agentic tasks slower overall, because they fail and retry more.
- Recommended sampling with thinking: temperature 1.0, top_p 0.95, top_k 20, min_p 0.
- Qwen ran its coding benchmarks in the Claude Code harness with a 256K context.

Memory budget [ANALYSIS]: a Q4-class GGUF is about 17–18 GB. About 2 GB is already used and about
1 GB goes to compute buffers, which leaves roughly 3–4 GB for the KV cache. That is about 100–128K
tokens at 8-bit KV. MTP buffers also take memory: one user hit the VRAM limit at 196K context
([unsloth discussion](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/discussions/32)).

Reported speeds on a 4090 ([computingforgeeks](https://computingforgeeks.com/run-qwen3-8-27b-locally/),
[gist](https://gist.github.com/ryan4yin/19db9fa44972c5735c1d181e8888d4fe)): about 47 tokens per
second without MTP and about 60–110 with MTP, depending on context length and prompt. In
[Simon Willison's review](https://simonwillison.net/2026/Aug/16/qwen-38-27b/), tool calls in a coding
agent worked, but the default `xhigh` effort spent about 22K reasoning tokens on one small prompt.

## 6. Decided

These are the founder's decisions, or calls Claude made in the conversation that the founder
accepted:

- **Runtime:** `llama-server` from upstream llama.cpp, built with CUDA, running in WSL with every
  layer on the GPU. It serves the OpenAI-compatible API, and the Anthropic Messages API at
  `/v1/messages` that Claude Code uses
  ([Hugging Face blog](https://huggingface.co/blog/ggml-org/anthropic-messages-api-in-llamacpp)).
- **Model file:** a Q4-class GGUF of Qwen 3.8 27B, plus the MTP draft file if llama.cpp needs one.
- **Main harness:** OpenCode, with the local server configured as an OpenAI-compatible provider.
- **Comparison harness:** Claude Code with `ANTHROPIC_BASE_URL` pointing at the local server, under a
  separate config dir and a separate command (see §4).
- **Hosted baseline:** the same task also runs once on hosted Claude, through the founder's
  personal account, to give a measured baseline: wall time, tokens, retries, and pass or fail. The
  task MUST be small, so the baseline uses few subscription tokens.
- **Defaults:** one session at a time; about 100K tokens of context; low reasoning effort by
  default, which the founder can raise for each task.
- **Location:** scripts in `ouroboric/scripts`, with tests in `ouroboric/scripts/tests` in the same
  style as the existing ones (fake commands, no GPU or network needed). The work goes in through a
  pull request. The notes page goes in `ouroboric/docs/` beside this document.

Claude's calls after the builder check (the founder can override them):

- **When the targets collide.** 40 tokens per second is a target that gets recorded, not a pass/fail
  gate. Measure speed twice: on a near-empty context, and with about 100K tokens filled. If the
  Q4 file, MTP and 100K context don't all fit in 24 GB, keep the Q4 file and MTP, and reduce the
  context. The floor is 64K tokens. Record what fits.
- **One-time setup.** Installing the CUDA toolkit, building llama.cpp, installing OpenCode and
  downloading the model are a written procedure in the notes page. The founder runs the steps that
  need `sudo`. The download and build steps MAY be scripts. They need tests only if they hold logic
  that can break. Start, stop and the local Claude Code launcher MUST be scripts with tests.
- **WSL memory cap.** Leave `.wslconfig` as it is, because changing it needs `wsl --shutdown`. If the
  build or model load fails at 12 GB, use fewer build jobs, then ask the founder.
- **Network.** Configuration is enough; no firewall or network namespace. "Model requests" means
  calls to an LLM only. Turn off OpenCode's auto-update and sharing, and point its small model at
  the local server too. Check once, by reading the server log, that every model call reached the
  local server.
- **The test task's result.** Each run (OpenCode, local Claude Code, hosted Claude) works in its own
  throwaway git worktree, directly on the host, in the harness's default ask-before-acting
  permission mode. The founder judges each diff, then the worktree is removed. Nothing is pushed,
  and the local agents get no GitHub access.
- **The local Claude Code config dir (founder's decision: match the personal setup, for a fair
  comparison).** It gets the same plugins as `~/.claude-personal` (`superpowers`, `gopls-lsp`,
  `skill-creator` from `claude-plugins-official`), the same user skills (`~/.claude-personal/skills`),
  and the `merge-requires-green.sh` hook. It leaves out three things:
  - the `account-guard.sh` hook, because the local config has no account;
  - claude.ai connectors (Claude Docs, Artifacts), because they need an account and would send data
    off the machine;
  - the personal auto-memory.

  Install the plugins into the local config dir, or link to them. Do not change the files in
  `~/.claude-personal`. Record the remaining differences in the notes page. The task prompt for all
  three runs is the same, and it says to skip clarifying questions, so the `superpowers` brainstorming
  gate doesn't stall the comparison.
- **Reasoning effort.** Changing the default effort MAY need a server restart with a different
  flag. Per-request control inside a harness is a nice-to-have. Record whether each harness
  supports it.

## 7. Left to the builder

- How to install the CUDA toolkit and build llama.cpp: build from source in WSL, or use the
  `server-cuda` container under podman with an NVIDIA CDI spec. Building from source is preferred if
  it is not much harder, because MTP support is recent.
- The exact quant: unsloth Q4_K_M or UD-Q4_K_XL, or another Q4-class file. Pick one, and record why.
- Where model files live (outside every repo) and how the scripts find them.
- The `llama-server` flags: context size, KV cache type, MTP settings, sampling, and how the default
  reasoning effort is set.
- Script names and the command names for start, stop, and local Claude Code. Do not shadow `claude`,
  `claude-work` or `claude-personal`.
- How OpenCode's config is installed: global config or an env var such as `OPENCODE_CONFIG`.
- The task used for goals 2 and 3. Pick a small, real task from a backlog in one of the founder's
  repos, and confirm it with the founder before running it.
- How to measure speed and context: the server's own timings are enough.
