---
title: Run Qwen 3.8 27B locally and repeat the experiment
status: accepted
date: 2026-10-20
style: guide
related: [2026-10-19-local-qwen-design.md, 2026-10-19-local-qwen-notes.md]
---

# Run Qwen 3.8 27B locally and repeat the experiment

> **To set up and run the local model server, follow the operations guide instead:**
> [Local models](https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/3-using/operations/local-models.md)
> (`scripts/ygg-models.sh setup`). This page keeps the experiment: the measurements and the three-way
> comparison.

This guide sets up Qwen 3.8 27B on one NVIDIA RTX 4090 under WSL2. Then you use it from OpenCode and
from Claude Code, and repeat the measurements and the three-way comparison in
[the notes](2026-10-19-local-qwen-notes.md). Every command runs in zsh, from the root of the
`ouroboric` repo, unless a step says otherwise.

## Before you start

You need:

- An RTX 4090, or another 24 GB NVIDIA card, with a Windows driver that offers CUDA 13.3 or newer in
  WSL. Check with `nvidia-smi`.
- WSL2 with Ubuntu 22.04, about 25 GB of free disk, Homebrew, `uv`, and the factory's engine (a Podman machine
  with GPU access: `scripts/ygg-gpu.sh setup` prepares it). The server image builds `llama-server` itself, so the
  host needs no CUDA toolkit, no cmake and no build.
- Claude Code (`claude`) on `PATH`. The personal Claude Code config in `~/.claude-personal` is optional: without it, `init` leaves out the
  skills link and the merge hook, and says so.

The model and the run state of the measurement scripts live in `~/.local/share/qwen-local` (`QWEN_HOME`),
outside every repo. The engine sees host files only through the `sandbox.mounts` of the factory folder's
`factory.yaml` (for the founder's setup, `~/ygg-it`), so the weights and the state folder of the model list must
be under a folder of those mounts: put the model under `~/ygg-it` and link it from there.
A symlink in the weights folder that points outside the mounts does not resolve in the engine, so link only to
files under them.

## Set up the server

1. Install OpenCode: `brew install opencode`.
1. Download the model (16.5 GB) and its MTP draft file (1.4 GB), and link them to the names the
   scripts use:

   ```zsh
   mkdir -p ~/ygg-it/models/weights && cd ~/ygg-it/models/weights
   uvx --from huggingface_hub hf download unsloth/Qwen3.8-27B-GGUF \
     Qwen3.8-27B-UD-Q4_K_M.gguf MTP/mtp-Qwen3.8-27B-Q4_0.gguf --local-dir .
   ln -sfn Qwen3.8-27B-UD-Q4_K_M.gguf model.gguf
   ln -sfn MTP/mtp-Qwen3.8-27B-Q4_0.gguf mtp.gguf
   ```

1. Write your model list from `scripts/testdata/models/models.example.yaml` to
   `~/.config/ygg/models.yaml`. Set `weights` to the folder from the last step and `state` to another folder under
   `~/ygg-it` (both must be under a folder of `sandbox.mounts`; `ygg models server --config` refuses others), then
   start the server: `scripts/ygg-models.sh start`. It builds the image on the first start, which takes long. The
   flags are the list's `args`; the preset `ygg models preset` prints shows them.
1. Fix the chat template. Claude Code sends a system message after the first, which the model's own template
   refuses. With the server running, load the model and save the fixed template:

   ```zsh
   scripts/ygg-models.sh load qwen3.8-27b
   scripts/ygg-models.sh template qwen3.8-27b
   ```

   It saves `chat-template.jinja` in the weights folder. Uncomment `chat-template-file` in the list, then run
   `scripts/ygg-models.sh stop && scripts/ygg-models.sh start`.
1. Set up the local Claude Code config dir, `~/.claude-qwen`: `scripts/qwen-claude.sh init`. It
   installs the three plugins and, when the personal setup has them, links its skills and adds its merge hook. It never touches `~/.claude` or
   `~/.claude-personal`.

The server's settings are the model list's `context` and `args` (reasoning effort, cache and checkpoint
keys). The launchers read `QWEN_CTX` (102400; keep it equal to `context`), `QWEN_ALIAS` (the list's model
name), `QWEN_MODELS` (the list file, when it is not the default) and `QWEN_FOLDER` (the factory folder, when it
is not `~/ygg-it`). The comment block at the top of
`scripts/ygg-models.sh` explains the commands.

## Use it

- **OpenCode:** `scripts/qwen-opencode.sh` opens the interactive session. For a headless run, use
  `scripts/qwen-opencode.sh run --auto "..."`; without `--auto`, a run that calls a tool waits for an
  approval that it cannot get.
- **Claude Code:** `scripts/qwen-claude.sh` opens the interactive session, and
  `scripts/qwen-claude.sh -p "..."` runs one prompt headless. It asks before it acts. Claude Code's own
  effort setting has no effect here; change `reasoning-effort` in the list and restart the server instead.
- **Status and stop:** `scripts/ygg-models.sh status` and `scripts/ygg-models.sh stop`.

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

   To measure without MTP, remove its keys from the list's `args`, restart and run it again.

1. Speed with about 95K tokens of context:

   ```zsh
   python3 -I scripts/qwen-measure.py prompt --tokens 95000 --out /tmp/long.txt \
     "../yggdrasil/gleipnir/**/*.go"
   python3 -I scripts/qwen-measure.py speed --runs 1 --max-tokens 256 /tmp/long.txt
   ```

1. Reasoning effort: set `reasoning-effort` to `low`, `medium` and `xhigh` in the list in turn, restarting each time, and run
   `speed --runs 1 --max-tokens 20000 /tmp/short.txt` each time.
1. The server's memory over a growing conversation. The server's process runs in the Podman machine's own
   WSL distro, so `/proc` on the host does not show it, and `qwen-measure.py growth` (which needs a host
   pid) does not apply. Watch the container instead, through the engine script, while a long OpenCode or
   Claude Code session runs in another terminal:

   ```zsh
   watch -n 10 'scripts/ygg-engine.sh run -- podman stats --no-stream ygg-models'
   ```

   To see the problem the defaults fix, set `ctx-checkpoints` to 32 and `cache-ram` to 8192 in the
   list's `args`, restart and watch again.

## Repeat the comparison

The comparison runs one task three times. Each run gets a throwaway worktree of the same commit and
the same prompt. Tools are approved without asking, so use a task you trust the agents with.

```zsh
scripts/ygg-models.sh start
scripts/qwen-compare.sh --repo ../yggdrasil/odin --commit bc973e3 \
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
  fixed chat template is missing. Run `scripts/ygg-models.sh template qwen3.8-27b` and restart, as in
  [Set up the server](#set-up-the-server).
- **The server disappears in a long session, and `dmesg` shows `Out of memory: Killed process
  (llama-server)`.** WSL ran out of system RAM. Keep `cache-ram` and `ctx-checkpoints` low in the list's `args`,
  or raise `memory=` in `C:\Users\<you>\.wslconfig`. Run `wsl --shutdown` from Windows to apply it; this
  closes every WSL session.
- **OpenCode ignores a changed config.** A background `opencode serve --service` from an earlier
  session holds the old one. `scripts/qwen-opencode.sh` avoids it with `--standalone`. To stop the
  service, run `opencode service stop`.
- **`start` fails to publish the port.** Another program uses `host_port` (8088). Stop it, or change
  `host_port` in the list.
