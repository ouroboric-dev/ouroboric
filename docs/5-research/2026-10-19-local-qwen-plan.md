---
title: Local Qwen 3.8 27B coding assistant, implementation plan
status: draft
date: 2026-10-19
style: spec
---

# Local Qwen 3.8 27B Coding Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Qwen 3.8 27B on the local RTX 4090 with `llama-server`, use it from OpenCode and from a
separate Claude Code config, and compare both with hosted Claude on one small real task.

**Architecture:** Upstream llama.cpp, built with CUDA in WSL, serves the model on `127.0.0.1`. One
script starts and stops the server. Two launchers start OpenCode and Claude Code with environment
variables that point them only at that server. A shared library holds the defaults and the running
server's state. A notes page holds the founder-run setup procedure, the measurements and the
comparison.

**Tech Stack:** bash (shellcheck-clean, `set -euo pipefail`), llama.cpp `llama-server`, CUDA toolkit
for WSL-Ubuntu, a Q4-class GGUF from Hugging Face, OpenCode (Homebrew), Claude Code (Homebrew,
already installed at `/home/linuxbrew/.linuxbrew/bin/claude`), python3 only inside tests.

**Spec:** [`2026-10-19-local-qwen-design.md`](2026-10-19-local-qwen-design.md)

## Global Constraints

- Repo: `~/brunogbv/ouroboric/ouroboric`, branch `local-qwen`. Stage explicit paths only; never
  `git add -A` (the tree has an untracked `docs/assets/logo/` that is not ours).
- Scripts go in `scripts/`, tests in `scripts/tests/<name>.test.sh`, in the style of
  `scripts/tests/ygg-engine.test.sh`: a temp `HOME`, fake commands, no GPU and no network. Scripts are
  AGPL-3.0-only through `REUSE.toml`; add no SPDX headers.
- Each script opens with a comment block: what it does, one usage line per mode, the environment it
  reads, in the style of `scripts/ygg-engine.sh`.
- The server binds `127.0.0.1` only. Default port `8088`. Model alias `qwen3.8-27b`.
- Default context `102400` tokens; floor `65536`. KV cache `q8_0` for K and V.
- Default reasoning effort `low`. Allowed: `low`, `medium`, `xhigh`, `off`.
- Sampling: temperature 1.0, top_p 0.95, top_k 20, min_p 0.
- One session at a time: `--parallel 1`.
- Model files, the llama.cpp build and run state live in `QWEN_HOME`, default
  `$HOME/.local/share/qwen-local`, never in a repo.
- The local Claude Code config dir is `QWEN_CLAUDE_DIR`, default `$HOME/.claude-qwen`. No script may
  write to `~/.claude`, `~/.claude.json`, `~/.claude-personal`, or `~/.config/claude-accounts.zsh`, or
  shadow the `claude`, `claude-work` or `claude-personal` commands.
- Launchers MUST unset `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN` and `OPENROUTER_API_KEY`.
- `.wslconfig` stays as it is. Steps that need `sudo` are founder-run; the agent prints them and
  waits.
- No session links in commits or the PR. Commits end with the `Co-Authored-By` line in use.
- Lint must pass: `pre-commit run --files <changed files>` (shellcheck, markdownlint, reuse,
  gitleaks).

## Review Focus

1. **A stale pid file** after a crash or `wsl --shutdown`: `status` says "not running" and `start`
   works, without manual cleanup. (Task 2)
2. **A reused pid:** the pid file names a live process that is not `llama-server`. `stop` MUST NOT
   kill it. (Task 2)
3. **Another program already on port 8088:** `start` refuses with a clear message instead of
   reporting that program as the model. (Task 2)
4. **The model does not fit in VRAM:** `llama-server` exits while loading. `start` reports failure
   and shows the end of the log, instead of waiting out the timeout. (Task 2)
5. **Launchers with the server down, or with a cloud credential in the caller's shell:** they refuse,
   or they strip the credential, so no session reaches a hosted model by accident. (Tasks 3 and 4)

---

## File Structure

| File | Responsibility |
| --- | --- |
| `scripts/qwen-lib.sh` | sourced only: defaults, the server URL, the health check, the running server's state file |
| `scripts/qwen-local.sh` | `start`, `stop`, `status`, `cmd` for `llama-server` |
| `scripts/qwen-opencode.sh` | runs OpenCode against the local server |
| `scripts/qwen-claude.sh` | `init` the local Claude Code config dir; run Claude Code against the local server |
| `scripts/tests/qwen-local.test.sh` | tests `qwen-lib.sh` and `qwen-local.sh` |
| `scripts/tests/qwen-opencode.test.sh` | tests `qwen-opencode.sh` |
| `scripts/tests/qwen-claude.test.sh` | tests `qwen-claude.sh` |
| `docs/5-research/2026-10-19-local-qwen-notes.md` | setup procedure, measurements, comparison, lessons (style `research`) |

---

### Task 0: Branch

- [ ] **Step 1: Create the branch and commit the design and this plan**

```bash
cd ~/brunogbv/ouroboric/ouroboric
git switch main && git pull --ff-only
git switch -c local-qwen
git add docs/5-research/2026-10-19-local-qwen-design.md docs/5-research/2026-10-19-local-qwen-plan.md
git commit -m "Local Qwen 3.8 27B: design and plan"
```

---

### Task 1: Setup procedure and a first manual run

Founder-run where `sudo` is needed. This task produces the verified facts that Task 2 encodes.

**Files:**

- Create: `docs/5-research/2026-10-19-local-qwen-notes.md`: front matter (`title`, `status: draft`,
  `date`, `style: research`) and sections `## Setup`, `## Measurements`, `## Comparison`,
  `## Lessons`. This task fills `## Setup`.

- [ ] **Step 1: Print the `sudo` steps for the founder, and wait until they confirm they ran them**
  - The CUDA toolkit, from NVIDIA's `wsl-ubuntu` repository for Ubuntu 22.04, at a version no newer
    than CUDA 13.3 (the driver's user-mode version). **Install only a `cuda-toolkit-*` package, never
    `cuda`, `cuda-drivers` or any `nvidia-driver-*` package: in WSL the Windows driver provides the GPU
    driver.**
  - `cmake` and `build-essential`, from apt (or `brew install cmake`, which needs no `sudo`).
- [ ] **Step 2: Verify the toolkit**

Run: `/usr/local/cuda/bin/nvcc --version && nvidia-smi --query-gpu=name,memory.total --format=csv`
Expected: a CUDA 13.x release line, and `NVIDIA GeForce RTX 4090, 24564 MiB`.

- [ ] **Step 3: Build llama.cpp in `$QWEN_HOME/llama.cpp`**

Clone `https://github.com/ggml-org/llama.cpp`, record the commit, then
`cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89 && cmake --build build --config Release -j 6 --target llama-server`.
Use `-j 6` because WSL has 12 GB. If the build is killed for lack of memory, retry with `-j 3`, then
ask the founder.

Run: `$QWEN_HOME/llama.cpp/build/bin/llama-server --version`
Expected: a version line that names CUDA.

- [ ] **Step 4: Pick the quant and download it**

Look at `unsloth/Qwen3.8-27B-GGUF` (and the official Qwen GGUF repo, if there is one). Pick a
Q4-class file of 18 GB or less: Q4_K_M, or UD-Q4_K_XL. Download it with
`uvx --from huggingface_hub hf download <repo> <file> --local-dir $QWEN_HOME/models`. Also download
the MTP draft file, if llama.cpp needs one for this model. Link the files:
`$QWEN_HOME/models/model.gguf` (and `$QWEN_HOME/models/mtp.gguf`, if there is a draft file). Record
the repo, the file names, the sizes and the reason for the choice in `## Setup`.

- [ ] **Step 5: Confirm the server flags against the built binary**

Run `llama-server --help` and confirm the spelling of every flag in Task 2's `cmd` list. In
particular, confirm:

- the flash-attention flag (`-fa on`);
- `--chat-template-kwargs`;
- the KV cache type flags;
- `-ngl`;
- the MTP or speculative-decoding flags for this model.

Write the confirmed MTP flags as one string. That string becomes the default of `QWEN_MTP_ARGS` in
Task 2. Willison used `--spec-type draft-mtp`; the upstream spelling may differ. If a flag in Task 2's
list is spelled differently, correct Task 2 in this plan and say so in the commit message.

- [ ] **Step 6: First manual run**

Start the server by hand with the Task 2 flags, at context `102400` and with MTP. Then:

- `curl -s 127.0.0.1:8088/v1/chat/completions` with a short prompt. It must answer, with a reasoning
  part that is short at `low` effort.
- `curl -s 127.0.0.1:8088/v1/messages` with the Anthropic body shape (`model`, `max_tokens`,
  `messages`). It must answer, which confirms the endpoint Claude Code needs.
- Read `nvidia-smi` and record the VRAM in use.

If loading fails for lack of memory, reduce the context in steps of 8192 tokens, but not below
`65536`. Record the largest value that loads. That value replaces `102400` as the default in Task 2.

- [ ] **Step 7: Install OpenCode, without `sudo`**

Run: `brew install sst/tap/opencode` (or the current Homebrew name), then `opencode --version`.
Record the version.

- [ ] **Step 8: Write `## Setup` as numbered steps that the founder can repeat, then commit**

```bash
git add docs/5-research/2026-10-19-local-qwen-notes.md
git commit -m "Local Qwen: setup procedure and verified server flags"
```

---

### Task 2: `qwen-lib.sh` and `qwen-local.sh`

**Files:**

- Create: `scripts/qwen-lib.sh`, `scripts/qwen-local.sh` (executable)
- Test: `scripts/tests/qwen-local.test.sh` (executable)

**Interfaces:**

- Produces (`qwen-lib.sh`, sourced; it sets these unless the caller already did):
  - `QWEN_HOME` (default `$HOME/.local/share/qwen-local`), `QWEN_PORT` (`8088`), `QWEN_CTX`
    (`102400`, or the value Task 1 recorded), `QWEN_ALIAS` (`qwen3.8-27b`).
  - `QWEN_STATE="$QWEN_HOME/run/server.env"`: written by `start`, removed by `stop`. It holds the
    lines `QWEN_PORT=<n>` and `QWEN_CTX=<n>` of the running server.
  - `qwen_load_state`: if `$QWEN_STATE` exists, set `QWEN_PORT` and `QWEN_CTX` from it. Read it as
    data, with `sed`; do not `source` it.
  - `qwen_url`: prints `http://127.0.0.1:$QWEN_PORT`.
  - `qwen_healthy`: exit 0 if `curl -fsS -m 2 "$(qwen_url)/health"` succeeds.
  - `qwen_require_server`: runs `qwen_load_state`, then fails with exit 2 and
    `the local model server is not running on <url>; start it with scripts/qwen-local.sh start`
    when it is not healthy.
- Produces (`qwen-local.sh start|stop|status|cmd`). Environment: `QWEN_LLAMA_SERVER` (default
  `$QWEN_HOME/llama.cpp/build/bin/llama-server`), `QWEN_MODEL` (default
  `$QWEN_HOME/models/model.gguf`), `QWEN_EFFORT` (`low`), `QWEN_MTP_ARGS` (the string from Task 1,
  word-split; empty means no MTP), `QWEN_START_TIMEOUT` (seconds, `300`). Files: pid
  `$QWEN_HOME/run/server.pid`, log `$QWEN_HOME/logs/server.log`. The previous log is kept as
  `server.log.1`.

The `cmd` argument list, in this order:
`-m $QWEN_MODEL --alias $QWEN_ALIAS --host 127.0.0.1 --port $QWEN_PORT -ngl 999 -c $QWEN_CTX -fa on --cache-type-k q8_0 --cache-type-v q8_0 --parallel 1 --jinja --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 --chat-template-kwargs <json> $QWEN_MTP_ARGS`.
The `<json>` is `{"reasoning_effort":"<effort>"}`, or `{"enable_thinking":false}` for `off`.

- [ ] **Step 1: Write the failing tests** in `scripts/tests/qwen-local.test.sh`

Use the `check`, `run` and `has` helpers from `ygg-engine.test.sh`. Put fakes in `$T/bin`, first on
`PATH`:

- a fake `llama-server` that writes its arguments, one per line, to `$T/args`, then sleeps (or exits
  with code 1 at once when `FAKE_DIE` is set);
- a fake `curl` that exits 0 when `$T/healthy` exists, and exits 7 otherwise.

`QWEN_LLAMA_SERVER` points to the fake server, `QWEN_MODEL` to an empty file, and
`QWEN_START_TIMEOUT=3`. The cases:

```text
cmd: default line contains "--host 127.0.0.1", "--port 8088", "-c 102400", "--cache-type-k q8_0",
     "--parallel 1", and '{"reasoning_effort":"low"}'
cmd: QWEN_EFFORT=off -> contains '{"enable_thinking":false}'
cmd: QWEN_EFFORT=high -> exit 2, message names QWEN_EFFORT and the four allowed values
cmd: QWEN_MTP_ARGS="--spec-a x" -> last two args are "--spec-a" "x"; QWEN_MTP_ARGS="" -> no "--spec-a"
start: QWEN_MODEL missing -> exit 2, message names the path; no fake server started
start: fake becomes healthy -> exit 0, prints "ready on http://127.0.0.1:8088", pid file names a live
       process, $T/args has "-m" "<model path>", server.env has QWEN_PORT=8088 and QWEN_CTX=102400
start: run again while running -> exit 0, "already running", still one fake process
start: FAKE_DIE -> exit 1, prints "exited while starting" and the log tail; no pid file, no server.env
start: never healthy -> exit 1 within ~3 s, "did not become ready", fake process killed, no pid file
start: port already healthy and no pid file -> exit 2, "port 8088 already answers"; fake not started
status: running -> exit 0, "running", the URL; not running -> exit 3, "not running"
status: stale pid file (dead pid) -> exit 3, "not running", pid file and server.env removed
stop: running -> exit 0, process gone within 30 s, pid file and server.env removed
stop: not running -> exit 0, "not running"
stop: pid file names a live `sleep` (not llama-server) -> exit 0, "stale", the sleep still alive,
      pid file removed
qwen_load_state: server.env with QWEN_PORT=9000 -> qwen_url prints http://127.0.0.1:9000
```

- [ ] **Step 2: Run the tests, and check that they fail**

Run: `bash scripts/tests/qwen-local.test.sh`
Expected: `FAIL` lines, because `qwen-local.sh` does not exist.

- [ ] **Step 3: Implement `scripts/qwen-lib.sh` and `scripts/qwen-local.sh`**

`qwen-local.sh` sources `qwen-lib.sh` from its own folder.

- Liveness means: the pid is alive, and `/proc/<pid>/cmdline` contains `llama-server`. Anything else
  is a stale pid file.
- `start`: launch the server in the background with `nohup`, writing to the log. Poll
  `qwen_healthy` once a second, and stop polling early if the process dies.
- `stop`: send TERM, wait up to 30 s, then send KILL.

- [ ] **Step 4: Run the tests and shellcheck, and check that they pass**

Run: `bash scripts/tests/qwen-local.test.sh && shellcheck scripts/qwen-lib.sh scripts/qwen-local.sh scripts/tests/qwen-local.test.sh`
Expected: only `ok` lines, and no shellcheck output.

- [ ] **Step 5: Real smoke**

Run: `scripts/qwen-local.sh start && scripts/qwen-local.sh status && scripts/qwen-local.sh stop`
Expected: `ready on http://127.0.0.1:8088`, then `running`, then a clean stop. `nvidia-smi` shows the
VRAM freed.

- [ ] **Step 6: Commit**

```bash
git add scripts/qwen-lib.sh scripts/qwen-local.sh scripts/tests/qwen-local.test.sh
git commit -m "qwen-local.sh: start, stop and status for the local llama-server"
```

---

### Task 3: `qwen-opencode.sh`

**Files:**

- Create: `scripts/qwen-opencode.sh` (executable)
- Test: `scripts/tests/qwen-opencode.test.sh` (executable)

**Interfaces:**

- Consumes: `qwen_require_server`, `qwen_url`, `QWEN_CTX`, `QWEN_ALIAS` from `qwen-lib.sh`.
- Produces: `qwen-opencode.sh [OPENCODE ARGS...]`. It execs `${QWEN_OPENCODE_BIN:-opencode}` with the
  arguments unchanged, and with:
  - `OPENCODE_CONFIG_CONTENT`: the JSON below;
  - `OPENCODE_DISABLE_CLAUDE_CODE=1` and `OPENCODE_DISABLE_EXTERNAL_SKILLS=1`, so that OpenCode does
    not read `~/.claude`, which is the work account;
  - `OPENCODE_DISABLE_AUTOUPDATE=true`, `OPENCODE_DISABLE_SHARE=true` and
    `OPENCODE_DISABLE_MODELS_FETCH=true`.

  The project's own OpenCode config stays enabled.

The config, as built by the script (`<url>`, `<ctx>` and `<alias>` filled in):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": false,
  "share": "disabled",
  "enabled_providers": ["qwen-local"],
  "provider": {
    "qwen-local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Qwen local",
      "options": { "baseURL": "<url>/v1" },
      "models": { "<alias>": { "name": "Qwen 3.8 27B (local)", "tool_call": true, "reasoning": true,
                               "limit": { "context": <ctx>, "output": 32768 } } }
    }
  },
  "model": "qwen-local/<alias>",
  "small_model": "qwen-local/<alias>"
}
```

Check `enabled_providers` against the installed OpenCode's config schema. If the key has a different
name, use the schema's name, and record the change.

- [ ] **Step 1: Write the failing tests**

Use a fake `opencode` that writes its arguments and its full environment to files, and the fake
`curl` from Task 2. Parse the config with `python3 -c 'import json,os; ...'`. The cases:

```text
server down -> exit 2, message from qwen_require_server; fake opencode not run
server up, server.env says QWEN_PORT=9000 QWEN_CTX=65536 -> baseURL "http://127.0.0.1:9000/v1",
    limit.context 65536, model and small_model "qwen-local/qwen3.8-27b", enabled_providers ["qwen-local"]
args pass through: qwen-opencode.sh run "hi" -> fake got "run" "hi"
env: the five OPENCODE_DISABLE_* variables set as above
env: caller exports ANTHROPIC_API_KEY, CLAUDE_CODE_OAUTH_TOKEN, OPENROUTER_API_KEY -> none reach the fake
```

- [ ] **Step 2: Run the tests, and check that they fail**

Run: `bash scripts/tests/qwen-opencode.test.sh`
Expected: `FAIL` lines.

- [ ] **Step 3: Implement `scripts/qwen-opencode.sh`**

Build the JSON with `printf`. Every value is a number or a fixed string, so no escaping is needed.
Use `exec env -u … VAR=… "$bin" "$@"`.

- [ ] **Step 4: Run the tests and shellcheck, and check that they pass**

Run: `bash scripts/tests/qwen-opencode.test.sh && shellcheck scripts/qwen-opencode.sh scripts/tests/qwen-opencode.test.sh`
Expected: only `ok` lines, and no shellcheck output.

- [ ] **Step 5: Real smoke**

With the server running, in `~/brunogbv/ouroboric/ouroboric`, run:
`scripts/qwen-opencode.sh run "List the files in scripts/ that start with qwen, using a tool"`.

Expected: an answer that names the qwen scripts, after at least one tool call. The server log shows
the requests. Record the OpenCode version and any setting that needed a change in `## Setup`.

- [ ] **Step 6: Commit**

```bash
git add scripts/qwen-opencode.sh scripts/tests/qwen-opencode.test.sh docs/5-research/2026-10-19-local-qwen-notes.md
git commit -m "qwen-opencode.sh: OpenCode on the local Qwen server"
```

---

### Task 4: `qwen-claude.sh`

**Files:**

- Create: `scripts/qwen-claude.sh` (executable)
- Test: `scripts/tests/qwen-claude.test.sh` (executable)

**Interfaces:**

- Consumes: `qwen_require_server`, `qwen_url`, `QWEN_ALIAS`.
- Produces: `qwen-claude.sh init` and `qwen-claude.sh [CLAUDE ARGS...]`.
  - Environment: `QWEN_CLAUDE_DIR` (default `$HOME/.claude-qwen`), `QWEN_CLAUDE_BIN` (default: the
    `claude` binary that `command -v claude` finds in bash, which is not the zsh function),
    `QWEN_PERSONAL_DIR` (default `$HOME/.claude-personal`; it is only read).
  - `init` refuses with exit 2 when `QWEN_CLAUDE_DIR` resolves to `$HOME/.claude`, to
    `$QWEN_PERSONAL_DIR`, or to a path inside either one.
  - `init` writes `$QWEN_CLAUDE_DIR/settings.json` (it regenerates the file each time) and
    `$QWEN_CLAUDE_DIR/.claude.json` with `{"hasCompletedOnboarding": true}`, but only if that file
    does not exist yet.
  - `init` links `$QWEN_CLAUDE_DIR/skills` to `$QWEN_PERSONAL_DIR/skills`.
  - `init` then runs, with `CLAUDE_CONFIG_DIR=$QWEN_CLAUDE_DIR`:
    `claude plugin marketplace add anthropics/claude-plugins-official`, and
    `claude plugin install <p>@claude-plugins-official` for each of `superpowers`, `gopls-lsp` and
    `skill-creator`. Check these subcommands against `claude --help` on the installed version.
  - Run mode requires the server and `settings.json`. Otherwise it fails with exit 2 and
    `run scripts/qwen-claude.sh init first`.
  - Run mode then execs the binary with the arguments unchanged. It unsets `ANTHROPIC_API_KEY`,
    `CLAUDE_CODE_OAUTH_TOKEN` and `OPENROUTER_API_KEY`, and sets:
    - `CLAUDE_CONFIG_DIR=$QWEN_CLAUDE_DIR`
    - `ANTHROPIC_BASE_URL=$(qwen_url)`
    - `ANTHROPIC_AUTH_TOKEN=local-qwen`
    - `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`,
      `ANTHROPIC_DEFAULT_HAIKU_MODEL` and `CLAUDE_CODE_SUBAGENT_MODEL`, all set to `$QWEN_ALIAS`
    - `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` and `DISABLE_AUTOUPDATER=1`

`settings.json`:

```json
{
  "permissions": { "defaultMode": "default" },
  "model": "qwen3.8-27b",
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "gopls-lsp@claude-plugins-official": true,
    "skill-creator@claude-plugins-official": true
  },
  "extraKnownMarketplaces": {
    "claude-plugins-official": { "source": { "source": "github", "repo": "anthropics/claude-plugins-official" } }
  },
  "hooks": {
    "PreToolUse": [ { "matcher": "Bash", "hooks": [
      { "type": "command", "command": "<QWEN_PERSONAL_DIR>/hooks/merge-requires-green.sh" } ] } ]
  }
}
```

- [ ] **Step 1: Write the failing tests**

Use a temp `HOME` that holds a `.claude-personal` with `settings.json`, `skills/a/SKILL.md` and
`hooks/merge-requires-green.sh`, plus a `.claude/settings.json`. Use a fake `claude` that appends its
arguments, `CLAUDE_CONFIG_DIR` and its full environment to files, and the fake `curl` from Task 2. The
cases:

```text
init: writes settings.json with the three plugins, defaultMode "default", the hook path under
      $HOME/.claude-personal; .claude.json has hasCompletedOnboarding true; skills is a link to
      $HOME/.claude-personal/skills; fake claude got the marketplace add and three plugin installs,
      each with CLAUDE_CONFIG_DIR=$HOME/.claude-qwen
init: an existing .claude.json is left as it is
init: QWEN_CLAUDE_DIR=$HOME/.claude-personal -> exit 2, nothing written, fake not run
init: QWEN_CLAUDE_DIR=$HOME/.claude/sub -> exit 2
init + run: sha256 of every file under $HOME/.claude-personal and $HOME/.claude unchanged
run: before init -> exit 2 "init first"
run: server down -> exit 2, fake not run
run: args pass through; env has ANTHROPIC_BASE_URL=http://127.0.0.1:8088, CLAUDE_CONFIG_DIR=$HOME/.claude-qwen,
     ANTHROPIC_MODEL=qwen3.8-27b, CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
run: caller exports ANTHROPIC_API_KEY, CLAUDE_CODE_OAUTH_TOKEN, OPENROUTER_API_KEY -> none reach the fake
```

- [ ] **Step 2: Run the tests, and check that they fail**

Run: `bash scripts/tests/qwen-claude.test.sh`
Expected: `FAIL` lines.

- [ ] **Step 3: Implement `scripts/qwen-claude.sh`**

Resolve the paths with `realpath -m` before the refusal check. Build `settings.json` with `printf`;
the only variable value is the hook path, and it has no quotes in it.

- [ ] **Step 4: Run the tests and shellcheck, and check that they pass**

Run: `bash scripts/tests/qwen-claude.test.sh && shellcheck scripts/qwen-claude.sh scripts/tests/qwen-claude.test.sh`
Expected: only `ok` lines, and no shellcheck output.

- [ ] **Step 5: Real smoke**

1. Run `scripts/qwen-claude.sh init`.
2. With the server running, in `~/brunogbv/ouroboric/ouroboric`, run
   `scripts/qwen-claude.sh -p "Which scripts in scripts/ start with qwen? Use a tool."`.
3. Check the answer. Expected: it names the qwen scripts. No login prompt appears, and
   `ls ~/.claude-qwen/plugins` shows the three plugins.
4. Check the server log. Expected: the server log shows `/v1/messages` requests.
5. Check the personal config. Expected: `claude-whoami` in `~/brunogbv` still reports the personal
   account.

- [ ] **Step 6: Commit**

```bash
git add scripts/qwen-claude.sh scripts/tests/qwen-claude.test.sh
git commit -m "qwen-claude.sh: Claude Code on the local Qwen server, in its own config dir"
```

---

### Task 5: Measurements

**Files:**

- Modify: `docs/5-research/2026-10-19-local-qwen-notes.md` (`## Measurements`)
- Modify, only if the measurements say so: `scripts/qwen-lib.sh` (the `QWEN_CTX` default) and its
  test

- [ ] **Step 1: Decode speed at a near-empty context**

1. With MTP on, send three `/v1/chat/completions` requests. Each has a coding prompt of about 200
   tokens and `max_tokens: 512`.
2. Read `timings.predicted_per_second` and `timings.prompt_per_second` from each response.
3. Repeat with `QWEN_MTP_ARGS=""`.
4. Record the median of each run, and the draft acceptance rate from the log.

- [ ] **Step 2: Speed with about 100K tokens filled**

Build a prompt of about 95,000 tokens from real source files (for example, the contents of
`~/brunogbv/ouroboric/yggdrasil/gleipnir`, repeated). Send it with `max_tokens: 256`, with MTP on.
Record the prompt speed, the decode speed and the VRAM in use. If the request fails for lack of
memory, lower `QWEN_CTX` in steps of 8192 tokens, but not below `65536`. Record the result.

- [ ] **Step 3: Reasoning effort**

Send the same prompt at `QWEN_EFFORT=low`, `medium` and `xhigh` (restart the server each time).
Record the reasoning tokens and the wall time.

Then test per-request control:

- OpenCode: does a model `options` entry, or a variant with `reasoning_effort`, reach the server?
  Check the server log.
- Claude Code: does a thinking or effort setting change the request that the server gets?

Record yes or no for each.

- [ ] **Step 4: Check that only the local server gets model calls**

During the Task 4 smoke and the Task 6 runs, every model call appears in the server log, and neither
launcher's environment holds a cloud credential (the tests prove this). Record "verified on YYYY-MM-DD".

- [ ] **Step 5: If the measured context differs from the default**

Change the `QWEN_CTX` default in `qwen-lib.sh` and the matching test case. Then run all three test
files.

- [ ] **Step 6: Commit**

```bash
git add docs/5-research/2026-10-19-local-qwen-notes.md   # plus qwen-lib.sh and its test, if changed
git commit -m "Local Qwen: measured speed, context and reasoning effort"
```

---

### Task 6: Three-way comparison

**Files:**

- Modify: `docs/5-research/2026-10-19-local-qwen-notes.md` (`## Comparison`, `## Lessons`)

- [ ] **Step 1: Propose the task, and wait for the founder's choice**

Propose two or three small, real tasks from a backlog in the founder's repos, for example
`yggdrasil/docs/2-engineering/backlog.md` or a small script fix in `ouroboric`. A good task touches
one or two files and has a check that can pass or fail. Ask the founder:

- which task to use;
- which hosted model to use for the baseline (their default, or Sonnet, which costs less).

Write down the one prompt that all three runs get. It ends with:
"Do not ask clarifying questions; make reasonable choices and say what you chose."

- [ ] **Step 2: Make three throwaway worktrees from the same commit**

Run in the target repo: `git worktree add ../<repo>-cmp-<tool> -b cmp-<tool>`, for `<tool>` =
`opencode`, `qwen-claude` and `hosted`.

- [ ] **Step 3: Run the task three times, one after the other**

1. Run `scripts/qwen-opencode.sh` in the opencode worktree.
2. Run `scripts/qwen-claude.sh` in the qwen-claude worktree.
3. Run `claude-personal --model <chosen>` in the hosted worktree.

All three runs are interactive, in the default ask-before-acting mode, with the founder approving
each step. For each run, record:

- the wall time;
- the tokens: the server log for the local runs, `/cost` or the session file for hosted;
- the turns and the retries: failed tool calls, or the founder correcting it;
- whether the task's check passed;
- the founder's verdict on the diff.

- [ ] **Step 4: Write `## Comparison` and `## Lessons`**

`## Comparison` holds a table with one row per run. `## Lessons` covers:

- the settings that mattered;
- where each harness struggled, including how Qwen handled the superpowers process;
- the remaining unfairness: the hosted run had the personal memory and the claude.ai connectors.

Mark analysis `[ANALYSIS]`, as the `research` style requires.

- [ ] **Step 5: Remove the worktrees, after the founder has judged the diffs and says so**

For each worktree, run `git worktree remove ../<repo>-cmp-<tool>` and then `git branch -D cmp-<tool>`.
Run one short command per worktree.

- [ ] **Step 6: Commit**

```bash
git add docs/5-research/2026-10-19-local-qwen-notes.md
git commit -m "Local Qwen: three-way comparison and lessons"
```

---

### Task 7: Pull request

- [ ] **Step 1: Run the whole check**

```bash
for t in qwen-local qwen-opencode qwen-claude; do bash scripts/tests/$t.test.sh || echo "FAILED $t"; done
pre-commit run --files scripts/qwen-*.sh scripts/tests/qwen-*.test.sh docs/5-research/2026-10-19-local-qwen-*.md
```

Expected: only `ok` lines, no `FAILED` line, and every hook `Passed`.

- [ ] **Step 2: Set the design and the notes to `status: accepted`, then push and open the PR**

Run `scripts/as-bot.sh ouroboric git push -u origin local-qwen`, then
`scripts/as-bot.sh ouroboric gh pr create --title "Local Qwen 3.8 27B: scripts, setup and comparison" --body-file <file>`.

The body names the design, the plan and the notes. It sums up the measurements and the comparison,
and ends with the attribution line. It holds no session links.

- [ ] **Step 3: After the founder merges, return to main**

Run `git switch main && git pull --ff-only`.
