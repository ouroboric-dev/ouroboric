---
title: Local Qwen 3.8 27B coding assistant, notes
status: draft
date: 2026-10-20
style: research
related: [2026-10-19-local-qwen-design.md, 2026-10-19-local-qwen-plan.md]
---

# Local Qwen 3.8 27B coding assistant, notes

What it took to run Qwen 3.8 27B on one RTX 4090 under WSL2, how fast it is, and how it compares
with hosted Claude. The design is [2026-10-19-local-qwen-design.md](2026-10-19-local-qwen-design.md).

## Setup

Done on 2026-10-19 and 2026-10-20. Everything except steps 1 and 2 runs without `sudo`. Files live in
`QWEN_HOME`, which is `~/.local/share/qwen-local` by default.

1. **Install the CUDA toolkit (founder, `sudo`).** Use NVIDIA's `wsl-ubuntu` repository. Install only
   `cuda-toolkit-13-3`, because the driver's CUDA user-mode version is 13.3. Never install `cuda`,
   `cuda-drivers` or `nvidia-driver-*`: in WSL, the Windows driver provides the GPU driver.

   ```zsh
   cd /tmp && wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-keyring_1.1-1_all.deb
   sudo dpkg -i cuda-keyring_1.1-1_all.deb
   sudo apt-get update
   sudo apt-get install -y cuda-toolkit-13-3
   ```

2. **Check the toolkit.** `/usr/local/cuda/bin/nvcc --version` prints `release 13.3, V13.3.73`.
3. **Install cmake and OpenCode with Homebrew.** `brew install cmake opencode` installed cmake 4.4.4
   and OpenCode 2.0.32. The Homebrew formula is `opencode`, not `sst/tap/opencode`.
4. **Build llama.cpp.** The upstream build was at commit `4c3c581` (2026-10-19, version 0.7.0-dev, build
   50). Build with a `PATH` that leaves Homebrew out. With Homebrew first on `PATH`, the first build
   failed twice:
   - Homebrew's `ld` did not search the CUDA library folder (`undefined reference to
     cudaGetLastError@libcudart.so.13`).
   - Homebrew's OpenSSL needs glibc 2.38, and Ubuntu 22.04 has 2.35 (`undefined reference to
     __isoc23_strtol@GLIBC_2.38`). llama-server uses OpenSSL only to download models, so it is
     turned off.

   `-j 6` keeps the build inside WSL's 12 GB memory cap.

   ```zsh
   git clone https://github.com/ggml-org/llama.cpp ~/.local/share/qwen-local/llama.cpp
   cd ~/.local/share/qwen-local/llama.cpp
   export PATH=/usr/local/cuda/bin:/usr/bin:/bin
   /home/linuxbrew/.linuxbrew/bin/cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89 \
     -DCMAKE_BUILD_TYPE=Release -DLLAMA_OPENSSL=OFF
   /home/linuxbrew/.linuxbrew/bin/cmake --build build --config Release -j 6 --target llama-server
   ```

5. **Download the model and the MTP draft file**, then link them to the names the scripts expect.

   ```zsh
   cd ~/.local/share/qwen-local/models
   uvx --from huggingface_hub hf download unsloth/Qwen3.8-27B-GGUF \
     Qwen3.8-27B-UD-Q4_K_M.gguf MTP/mtp-Qwen3.8-27B-Q4_0.gguf --local-dir .
   ln -sfn Qwen3.8-27B-UD-Q4_K_M.gguf model.gguf
   ln -sfn MTP/mtp-Qwen3.8-27B-Q4_0.gguf mtp.gguf
   ```

   **Why UD-Q4_K_M (16.46 GB):** with the 1.37 GB MTP file, it leaves about 1 GB more for the
   context than UD-Q4_K_XL (17.56 GB) does. The design targets about 100K tokens of context, and
   Windows already holds about 2.1 GB of the card's 24 GB. [ANALYSIS]

6. **Start the server.** Run `scripts/qwen-local.sh start`. It takes about 23 seconds. The flags,
   checked against `llama-server --help` of this build, are in `scripts/qwen-local.sh cmd`.
   - MTP is `--spec-type draft-mtp -md mtp.gguf -ngld all`. The draft's KV cache is `q8_0` as well
     (`-ctkd q8_0 -ctvd q8_0`).
   - Reasoning effort has native flags: `--reasoning-effort low|medium|xhigh`, and `--reasoning off`
     turns thinking off.
   - At 102,400 tokens of context, with MTP, the card holds 23.5 of 24.6 GB, of which Windows uses
     about 2.1 GB.
7. **Save a fixed chat template, once.** With the server running, run `scripts/qwen-local.sh template`, then
   restart the server. Claude Code sends hook context, such as superpowers' SessionStart text, as a
   `system` message in the middle of the conversation. The model's template refuses any system
   message after the first (`Jinja Exception: System message must be at the beginning.`), so every
   Claude Code request failed with HTTP 500. The saved copy renders such a message as a system turn,
   and `start` uses it from then on (`--chat-template-file`).
8. **Set up the local Claude Code config dir.** Run `scripts/qwen-claude.sh init`. It added the
   marketplace and installed the three plugins into `~/.claude-qwen`. Claude Code does not know the
   model, so `qwen-claude.sh` sets `CLAUDE_CODE_MAX_CONTEXT_TOKENS` to the server's context. Without
   it, Claude Code assumes 200K tokens and would compact too late.

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

## Lessons
