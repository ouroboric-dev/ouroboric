# AGENTS.md: Ouroboric

Ouroboric is the company. This umbrella holds the company docs, the standards every product
inherits, and the products as submodules under `products/`. Start with `docs/README.md`.

## Invariants

These rules apply to every repo in this tree. A product's `AGENTS.md` may add rules; it must not
loosen these.

1. Humans steer. Stop and ask when work would leave an approved charter, spec or plan.
2. Write the failing test first. A test that never failed proves nothing.
3. Never merge a pull request, and never push to `main`. Humans merge: an agent may arm auto-merge on a pull
   request it opens (`scripts/pr-open.sh`), because the ruleset still requires a human's approval, and that approval
   is the merge decision. Never approve a pull request, never use an admin bypass, and never arm auto-merge on a
   repo whose ruleset does not require an approval.
4. Never read, print or store secrets, tokens or keys.
5. Never weaken a guardrail: approval points, sandbox settings, policies, rulesets or security tests.
6. Write each document in the style the docs standard assigns to its path.
7. Never commit raw sources that should not be published, such as AI-generated rasters or the
   founder's source images. Commit only final vectors and exports.
8. Work on a branch, stage files by path, and open a pull request for every change.
9. Never commit an operator's own config, such as a personal account name, a local path or a personal
   setting. The scripts serve any operator: such config goes in a gitignored folder, such as
   `scripts/orgs/local/`, and only generic examples are committed. Docs, plans and fixtures never name
   an operator either: `scripts/check-repos.sh --check operator` fails when they do.

## Map

- Company direction: `docs/1-company/` (charter, roadmap, budget, legal, readiness, repositories).
- Standards: `docs/4-ways-of-working/` (spec-driven development, docs standard, writing styles,
  diagrams).
- Research and journal: `docs/5-research/`, `docs/6-journal/`.
- Brand: `docs/7-branding/` (story, identity, logo).

## Scripts

`scripts/` holds the tools of this tree. Before you run a GitHub, container-engine, plan or repo command by hand,
look here: a script exists for it, and the script is the deterministic way. Read the header of a script before
you run it. If you write a reusable script, it goes here with a test in `scripts/tests/`, never only in a scratch
folder.

| Need | Script |
| --- | --- |
| Push, open a pull request or read GitHub as `ouroboric-pr-bot` | `scripts/as-bot.sh <repo> <cmd>`; `--read all` to read. The only way an agent reaches GitHub; to open a pull request, `scripts/pr-open.sh` is the default |
| Open a pull request as `ouroboric-pr-bot` and arm auto-merge on it: the default way an agent opens one. A human's approval still decides the merge; if arming fails the PR stays open and the script says why. A PR stacked on a branch other than the default one is opened without auto-merge | `scripts/pr-open.sh <repo> [gh pr create args]`, e.g. `scripts/pr-open.sh gleipnir --base main --head my-branch --title "…" --body-file body.md`. Prints the PR's URL. Never merges directly, never `--admin` |
| Build `ygg` from the umbrella's checkouts, so a smoke or proof run never uses a stale one | `scripts/ygg-build.sh [--yggdrasil DIR] [--out FILE] [--allow-behind] [--force]`. Refuses a dirty module or one behind its local `origin/main` (it fetches nothing); builds to the `ygg` first on PATH (else `$(go env GOPATH)/bin/ygg`) and writes the commits to `OUT.build.txt`; a link is followed to its target; an error if `command -v ygg` is not OUT. Never overwrites a file that is not a Go binary without `--force`. The smoke and proof scripts refuse a `ygg` from PATH whose facts do not name odin's HEAD (`--any-ygg` skips that) |
| Clean up after runs that have ended: the empty pods and leftover containers | `scripts/ygg-clean.sh --dry-run [--folder DIR] [--keep PROJECT]... [PROJECT...]`, then without `--dry-run`. Runs `ygg doctor` on each project under DIR (default `~/ygg-it`) with the config its runs used; skips a project with a live run (its lock in `/proc/locks`, or open in a process) and refuses when it cannot tell; never deletes a run, a project or an image, and never starts or stops the engine |
| Set up and check the GPU for the engine: the NVIDIA toolkit (pinned 1.20.1) and the CDI spec in the Podman machine's distro on WSL2, repeatable after a driver update or on a new machine | `scripts/ygg-gpu.sh setup\|check [--machine NAME] [--folder DIR]`. `setup` installs only what is missing and regenerates a stale spec, then runs `check`; `check` runs the CUDA image (by digest) through `ygg-engine.sh` and prints `gpu: <name> <memory>`, or exits 3 with `missing: toolkit\|spec\|stale spec` and the fix, or 2 when the engine does not answer. Root commands go through `wsl.exe -u root`, never sudo; it never starts, stops or re-creates the machine |
| Start, stop and check the local model server (llama-server and the model gate in one container, on the engine's GPU), from the operator's model list; the qwen scripts find it through it | `scripts/ygg-models.sh [--models FILE] start\|stop\|status\|load NAME`. FILE defaults to `~/.config/ygg/models.yaml` (example: `scripts/testdata/models/models.example.yaml`). `start` runs `ygg-gpu.sh check` first (a stale spec is set up again), builds the image only when its tag is missing (long, CUDA), creates the internal network when absent, writes the preset and runs the container with `127.0.0.1:<host_port>` as its only published port; `status` prints `running on <url>, loaded: <name\|none>` or exits 3; `stop` keeps the network and the image. Engine calls go through `ygg-engine.sh` |
| Any real-engine run (Podman, devcontainer, the sandbox): the engine, registry config and checks | `scripts/ygg-engine.sh check\|env\|run --folder DIR`. Never set `CONTAINER_HOST` by hand: the root socket is the wrong one |
| The realms smoke runs (v0-H13, v0-H15) and their evidence | `scripts/ygg-smoke-realms.sh`, `scripts/ygg-smoke-loop.sh`, `scripts/ygg-evidence.sh` |
| The grader smoke on a real engine (v0-H16), with the public sample suite | `scripts/ygg-smoke-grade.sh [--build]`. Never a hidden suite by default; `--task ID --suite-dir DIR --reference DIR [--suite-engine DIR]` points the grader at a suite store as it is (never copied or read) and grades the task's reference solution; its output holds numbers only |
| The runtime smoke (gallery-runtime T26): the templates' releases started by Niflheim's product start, in the task image, on an internal network, checked from a second container | `scripts/ygg-smoke-runtime.sh [--image REF] [--folder DIR] [--yggdrasil DIR] [--api-image REF] [--web-image REF]`. It prints PASS or FAIL per check and never prints the store's key |
| The real-agent smoke (v0-H17): costs money; `--dry-run` first; the cost from the ledger; a start from a planted-fault leaf; another implementer; a note before the brief; the repair path from the ledger | `scripts/ygg-smoke-real.sh --dry-run`, then without it; `--from-leaf LEAF`, `--implementer AGENT:MODEL`, `--brief-note FILE` (narrows the implementer's task; the run is graded against a derived task version in its folder; the ygg line says if the build used go.work); `scripts/ygg-cost.sh LEDGER`, `scripts/ygg-repair-path.sh LEDGER`. It never prints the credentials file |
| Compare reviewer models: costs money unless `--dry-run`; on the planted-fault leaves in `scripts/testdata/reviewer-bench`; runs the OpenCode version gleipnir pins (installed once with npm; `--opencode BIN`, `--any-opencode`) | `scripts/ygg-reviewer-bench.sh --model MODEL --leaf DIR --sessions N --dry-run`, then without it |
| A Phase 6 proof run (v0-T290, v0-T291): costs money without `--dry-run`; `--dry-run` first; the `software` graph on the real task with three roles and caps you set, then the grade and the evidence; never reads the suites folder or prints the credentials | `scripts/ygg-proof-run.sh --name NAME --dry-run [--planner AGENT:MODEL --implementer AGENT:MODEL --reviewer AGENT:MODEL --run-usd N ...]`, then without `--dry-run`. `--reviewer-reasoning EFFORT` (low, medium, high or off; default `medium`) sets the reviewer's reasoning effort; `--build` builds the sandbox images first; `--baseline RUN_ID` compares with a run of an earlier proof run; `--continue RUN_ID --approve GATE`, `--reject GATE --reason TEXT` or `--resume` continues a stopped or paused run (a rejection starts sessions, so it needs the credentials as an approval does); `--clip` copies the report. The run's output is in `run.txt` and the evidence in `report.txt`, in `DIR/proof-NAME-TIME`. The example config is `scripts/testdata/proof/factory.proof.example.yaml` |
| Build a plan from reference commits, or execute one task by task | `scripts/plan-*` (`plan-generate.py`, `plan-replay.py`, `plan-states.sh`, `plan-red.sh`, `plan-defences.py`; `plan-blocks.py`, `plan-task-start.sh`, `plan-task-done.sh`, `plan-task-land.sh`) |
| Check that the repos have the required setup, and that the realms' shared files match | `scripts/as-bot.sh --read all scripts/check-repos.sh`; `--check shared` runs the realms check alone; `--check operator` (local, no GitHub) checks that no tracked file names you; `--check services` (not a default, once per call) keeps the services' versions equal in niflheim-local, mimir and helheim-go |
| Scan git history for secrets | `scripts/scan-history.sh` |
| Create a repo with its first commit (`README.md`, licences, base CI) and its protection | `scripts/new-repo.sh --org <org> <repo> "<description>"`. Founder only |
| Write the licence files or the base CI into a folder | `scripts/add-licences.sh`, `scripts/add-ci.sh`. Founder only |
| Push the prepared `base-ci` branches of existing repos and open their PRs, then require `lint` after the merge | `scripts/rollout-ci.sh --org <org> push\|protect <repo>...`. Founder only |
| Prove that a Markdown change is formatting only, such as `markdownlint-cli2 --fix` output | `scripts/md-same-text.sh <base-ref> <head-ref>` |
| Check the journal against spec §10.5 and design criterion 6: front matter, sections, the index, evidence once resolved, a `factory-change` entry citing `ygg metrics --compare` | `scripts/journal-check.sh [DIR]` |
| Scaffold a new Go component | `scripts/scaffold-component.sh` |
| Render and check diagrams | `scripts/diagrams.sh` |

Only the founder runs `scripts/new-repo.sh`, `scripts/create-repo.sh`, `scripts/add-licences.sh`, `scripts/add-ci.sh`,
`scripts/setup-repo.sh`, `scripts/rollout-ci.sh` and `scripts/create-pr-bot.sh`.
