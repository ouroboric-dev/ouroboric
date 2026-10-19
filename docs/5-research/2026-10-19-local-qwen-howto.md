---
title: Run Qwen 3.8 27B locally and repeat the experiment
status: accepted
date: 2026-10-20
style: guide
related: [2026-10-19-local-qwen-design.md, 2026-10-19-local-qwen-notes.md]
---

# Run Qwen 3.8 27B locally and repeat the experiment

This guide sets up Qwen 3.8 27B on one NVIDIA RTX 4090 under WSL2. Then you use it from OpenCode and
from Claude Code, and repeat the measurements and the three-way comparison in
[the notes](2026-10-19-local-qwen-notes.md). Every command runs in zsh, from the root of the
`ouroboric` repo, unless a step says otherwise.

## Before you start

You need:

- An RTX 4090, or another 24 GB NVIDIA card, with a Windows driver that offers CUDA 13.3 or newer in
  WSL. Check with `nvidia-smi`.
- WSL2 with Ubuntu 22.04, about 25 GB of free disk, Homebrew, `uv`, and `sudo` for one step.
- Claude Code (`claude`) on `PATH`, and the personal Claude Code config in `~/.claude-personal`.

The model, the llama.cpp build and the run state live in `~/.local/share/qwen-local` (`QWEN_HOME`),
outside every repo.

## Set up the server

1. Install the CUDA toolkit. This is the only step that needs `sudo`. Install only
   `cuda-toolkit-13-3`. Never install `cuda`, `cuda-drivers` or `nvidia-driver-*`: in WSL, the Windows
   driver is the GPU driver.

   ```zsh
   cd /tmp && wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-keyring_1.1-1_all.deb
   sudo dpkg -i cuda-keyring_1.1-1_all.deb
   sudo apt-get update
   sudo apt-get install -y cuda-toolkit-13-3
   ```

   `/usr/local/cuda/bin/nvcc --version` now prints `release 13.3`.

1. Install cmake and OpenCode: `brew install cmake opencode`.
1. Build `llama-server` with CUDA. Keep Homebrew off `PATH` for the build: Homebrew's linker misses
   the CUDA libraries, and Homebrew's OpenSSL needs a newer glibc than Ubuntu 22.04 has.

   ```zsh
   git clone https://github.com/ggml-org/llama.cpp ~/.local/share/qwen-local/llama.cpp
   cd ~/.local/share/qwen-local/llama.cpp
   git checkout 4c3c581   # the build the notes measured; leave this out for the latest
   export PATH=/usr/local/cuda/bin:/usr/bin:/bin
   /home/linuxbrew/.linuxbrew/bin/cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89 \
     -DCMAKE_BUILD_TYPE=Release -DLLAMA_OPENSSL=OFF
   /home/linuxbrew/.linuxbrew/bin/cmake --build build --config Release -j 6 --target llama-server
   ```

   Open a new terminal afterwards, to get your usual `PATH` back. `-j 6` keeps the build inside a
   12 GB WSL memory cap.

1. Download the model (16.5 GB) and its MTP draft file (1.4 GB), and link them to the names the
   scripts use:

   ```zsh
   mkdir -p ~/.local/share/qwen-local/models && cd ~/.local/share/qwen-local/models
   uvx --from huggingface_hub hf download unsloth/Qwen3.8-27B-GGUF \
     Qwen3.8-27B-UD-Q4_K_M.gguf MTP/mtp-Qwen3.8-27B-Q4_0.gguf --local-dir .
   ln -sfn Qwen3.8-27B-UD-Q4_K_M.gguf model.gguf
   ln -sfn MTP/mtp-Qwen3.8-27B-Q4_0.gguf mtp.gguf
   ```

1. Start the server: `scripts/qwen-local.sh start`. It is ready in about 25 seconds. To see the
   flags, run `scripts/qwen-local.sh cmd`.
1. Save the fixed chat template, then restart, so Claude Code works:

   ```zsh
   scripts/qwen-local.sh template
   scripts/qwen-local.sh stop && scripts/qwen-local.sh start
   ```

1. Set up the local Claude Code config dir, `~/.claude-qwen`: `scripts/qwen-claude.sh init`. It
   installs the personal setup's three plugins and links its skills. It never touches `~/.claude` or
   `~/.claude-personal`.

The server's settings come from environment variables: `QWEN_CTX` (102400), `QWEN_EFFORT` (`low`,
`medium`, `xhigh` or `off`), `QWEN_MTP_ARGS` (empty turns MTP off), `QWEN_CACHE_RAM` (2048) and
`QWEN_CTX_CHECKPOINTS` (4). The comment block at the top of `scripts/qwen-local.sh` explains each one.

## Use it

- **OpenCode:** `scripts/qwen-opencode.sh` opens the interactive session. For a headless run, use
  `scripts/qwen-opencode.sh run --auto "..."`; without `--auto`, a run that calls a tool waits for an
  approval that it cannot get.
- **Claude Code:** `scripts/qwen-claude.sh` opens the interactive session, and
  `scripts/qwen-claude.sh -p "..."` runs one prompt headless. It asks before it acts. Claude Code's own
  effort setting has no effect here; restart the server with another `QWEN_EFFORT` instead.
- **Status and stop:** `scripts/qwen-local.sh status` and `scripts/qwen-local.sh stop`.

Both launchers send model calls only to the local server, and remove `ANTHROPIC_API_KEY`,
`CLAUDE_CODE_OAUTH_TOKEN` and `OPENROUTER_API_KEY` from the session. `qwen-claude.sh` also removes the
Bedrock, Vertex and Foundry switches.

## Repeat the measurements

Start the server, then run these commands. The figures in each answer come from the server itself.

1. Decode speed on a short prompt, three runs:

   ```zsh
   printf 'Write a Go function that parses a duration like "1h30m" or "45s" into seconds, with table-driven tests. Explain your choices briefly.' > /tmp/short.txt
   python3 -I scripts/qwen-measure.py speed --runs 3 --max-tokens 512 /tmp/short.txt
   ```

   To measure without MTP, restart with `QWEN_MTP_ARGS="" scripts/qwen-local.sh start` and run it
   again.

1. Speed with about 95K tokens of context:

   ```zsh
   python3 -I scripts/qwen-measure.py prompt --tokens 95000 --out /tmp/long.txt \
     "$HOME/brunogbv/ouroboric/yggdrasil/gleipnir/**/*.go"
   python3 -I scripts/qwen-measure.py speed --runs 1 --max-tokens 256 /tmp/long.txt
   ```

1. Reasoning effort: restart with `QWEN_EFFORT=low`, `medium` and `xhigh` in turn, and run
   `speed --runs 1 --max-tokens 20000 /tmp/short.txt` each time.
1. The server's memory over a growing conversation:

   ```zsh
   python3 -I scripts/qwen-measure.py growth --turns 20 --pid "$(cat ~/.local/share/qwen-local/run/server.pid)" /tmp/long.txt
   ```

   To see the problem the defaults fix, restart with `QWEN_CTX_CHECKPOINTS=32 QWEN_CACHE_RAM=8192`
   and run it again.

## Repeat the comparison

The comparison runs one task three times. Each run gets a throwaway worktree of the same commit and
the same prompt. Tools are approved without asking, so use a task you trust the agents with.

```zsh
scripts/qwen-local.sh start
scripts/qwen-compare.sh --repo ~/brunogbv/ouroboric/yggdrasil/odin --commit bc973e3 \
  --prompt docs/5-research/2026-10-19-local-qwen-comparison/prompt.txt --out /tmp/qwen-compare-b071
```

- **What it runs:** OpenCode and Claude Code on the local model, then Claude Code on Sonnet through the
  personal account. The Sonnet run uses that subscription. Change the model with `--hosted-model`, or
  skip runs with `--only opencode,qwen-claude`.
- **What it keeps:** each run's output, diff and slice of the server log, a `summary.tsv` with exit
  codes and wall times, and `rss.log`.
- **The task:** `bc973e3` is the `odin` commit the notes used, before B-071 was fixed. The diffs from
  the recorded runs are in
  [2026-10-19-local-qwen-comparison/](2026-10-19-local-qwen-comparison/).
- **Clean up:** when you have read the diffs, run the cleanup commands that the script prints at the
  end.

## Debug what a tool sends

`scripts/qwen-capture.py` stands in for the model server. It saves each request body and answers it
with an error:

```zsh
python3 -I scripts/qwen-capture.py 8099 /tmp/capture &
ANTHROPIC_BASE_URL=http://127.0.0.1:8099 CLAUDE_CONFIG_DIR=~/.claude-qwen ANTHROPIC_AUTH_TOKEN=x command claude -p hi
kill %1
```

The bodies are in `/tmp/capture/00-v1_messages.json` and the files after it. For OpenCode, set the
provider's `baseURL` to `http://127.0.0.1:8099/v1`, and pass `--standalone`.

## Troubleshooting

- **Every Claude Code request fails with HTTP 500, "System message must be at the beginning".** The
  fixed chat template is missing. Run the template step in [Set up the server](#set-up-the-server).
- **The server disappears in a long session, and `dmesg` shows `Out of memory: Killed process
  (llama-server)`.** WSL ran out of system RAM. Keep `QWEN_CACHE_RAM` and `QWEN_CTX_CHECKPOINTS` low,
  or raise `memory=` in `C:\Users\<you>\.wslconfig`. Run `wsl --shutdown` from Windows to apply it; this
  closes every WSL session.
- **OpenCode ignores a changed config.** A background `opencode serve --service` from an earlier
  session holds the old one. `scripts/qwen-opencode.sh` avoids it with `--standalone`. To stop the
  service, run `opencode service stop`.
- **`start` says the port already answers.** Another program uses port 8088. Stop it, or set
  `QWEN_PORT`.
