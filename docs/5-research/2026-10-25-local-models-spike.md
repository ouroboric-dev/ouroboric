---
title: Local models spike
status: draft
date: 2026-10-25
style: research
related: [2026-10-19-local-qwen-notes.md]
---

# Local models spike

The local models spec (Yggdrasil, `docs/2-engineering/specs/2026-10-25-local-models.md`) lists in §9 five
facts to confirm on the founder's engine before the feature is built. This note records each fact, the
command that showed it and its output. It was done on 2026-10-25 (task LM-T01). Analysis is marked
[ANALYSIS]. Paths under the operator's home are written `$HOME/...`.

## Summary

| Item | Fact | Result |
| --- | --- | --- |
| 1 | CUDA in rootless Podman through CDI | **Differed; confirmed after a founder step.** The CDI spec is read by the engine, which runs in the Podman machine's own WSL distro. Generated there, the GPU is reachable |
| 2 | A container on an internal network publishes a port on `127.0.0.1` | **Confirmed.** No second network is needed |
| 3 | The router's endpoints and the preset's key format | **Confirmed, with details the spec must add:** a flag is `key = true`; a bare key or an unknown key stops the server; a load of a running model answers 400 |
| 4 | OpenCode uses `@ai-sdk/openai-compatible` without npm | **Confirmed.** OpenCode 1.18.32 fails on the connection, not on a package fetch |
| 5 | The firewall sidecar resolves the server's name on the joined network | **Confirmed** |

## Environment

- The engine is a rootless Podman machine on WSL2. The machine is its own WSL distro,
  `podman-machine-default` (Fedora 43); `ygg` and the scripts run in another distro (Ubuntu). All of
  them share the WSL2 kernel `6.18.54.1-microsoft-standard-WSL2` and one network namespace.

  ```text
  $ scripts/ygg-engine.sh run -- podman version --format '{{.Server.Version}} {{.Client.Version}}'
  5.7.1 5.8.3
  $ scripts/ygg-engine.sh run -- podman info --format 'netBackend={{.Host.NetworkBackend}} rootless={{.Host.Security.Rootless}} pasta/slirp={{.Host.RootlessNetworkCmd}} os={{.Host.Distribution.Distribution}}'
  netBackend=netavark rootless=true pasta/slirp=pasta os=fedora
  ```

- The GPU is an RTX 4090 (24,564 MiB). Before the spike, 1,737 MiB was in use (Windows' share). The
  driver reports `NVIDIA-SMI 610.57.01`, KMD 610.88, CUDA UMD 13.3.
- Every engine command went through `scripts/ygg-engine.sh run`. Its check refused the shell's
  `XDG_RUNTIME_DIR` (`/run/user/<uid>` did not exist), so the spike used the folder the script's own
  message names, `/tmp/ygg-xdg-<uid>`. The engine was shared with another session's live runs; the
  spike named everything it made `lmspike-` and touched nothing else.

## Item 1: CUDA in rootless Podman through CDI

**Result: differed from the spec; confirmed once founder step 1 was done again inside the Podman machine (below).**

The founder installed the NVIDIA container toolkit (1.19.0) in the Ubuntu distro and ran `sudo nvidia-ctk
cdi generate --output=/etc/cdi/nvidia.yaml`. The founder reported these lines of its output (not seen by
the spike): `libnvidia-sandboxutils.so.1: not found` (ignored), `Auto-detected mode as 'wsl'`, and `Found
multiple driver store paths: [/usr/lib/wsl/drivers/nvrfi.inf_amd64_..., /usr/lib/wsl/drivers/u0199522.inf_amd64_...]`
(both were used).

The spec is there, in the Ubuntu distro:

```text
$ nvidia-ctk cdi list
level=info msg="Found 1 CDI devices"
nvidia.com/gpu=all
```

The CUDA image, pulled through the engine:

```text
$ scripts/ygg-engine.sh run -- podman pull docker.io/nvidia/cuda:12.9.1-base-ubuntu22.04
$ scripts/ygg-engine.sh run -- podman image inspect docker.io/nvidia/cuda:12.9.1-base-ubuntu22.04 --format '{{.Id}} {{.Digest}}'
2e1e354f0a7e32186e843c1cacda3fd1932f3c04da790c5fd50dc6af8bd7a1fb sha256:59436e8ac61921052d8f420be8b8cb8b117f1d7cc643397a289e37aaa0b83ea1
```

The run fails:

```text
$ scripts/ygg-engine.sh run -- podman run --rm --name lmspike-cuda --device nvidia.com/gpu=all --pull=never \
    docker.io/nvidia/cuda@sha256:59436e8ac61921052d8f420be8b8cb8b117f1d7cc643397a289e37aaa0b83ea1 nvidia-smi
Error: preparing container 602c01a4…e6a9 for attach: setting up CDI devices: unresolvable CDI devices nvidia.com/gpu=all
exit=126
```

The engine's distro has no CDI spec and no toolkit, but it does see the GPU's device and driver files:

```text
$ wsl.exe -d podman-machine-default -u root -- sh -c 'ls -la /etc/cdi /var/run/cdi; command -v nvidia-ctk || echo "no nvidia-ctk"'
ls: cannot access '/etc/cdi': No such file or directory
ls: cannot access '/var/run/cdi': No such file or directory
no nvidia-ctk
$ wsl.exe -d podman-machine-default -u root -- sh -c 'ls -d /usr/lib/wsl/drivers/nvrfi.inf_amd64_* /usr/lib/wsl/drivers/u0199522.inf_amd64_*; ls -la /dev/dxg; command -v nvidia-cdi-hook || echo "no nvidia-cdi-hook"'
/usr/lib/wsl/drivers/nvrfi.inf_amd64_87b4cb6242e17d7d
/usr/lib/wsl/drivers/u0199522.inf_amd64_4460110b5e6a33d3
crw-rw-rw- 1 root root 10, 258 Oct 24 21:29 /dev/dxg
no nvidia-cdi-hook
```

The generated spec names `/dev/dxg`, files under `/usr/lib/wsl/drivers/nvrfi.inf_amd64_87b4cb6242e17d7d/`, and
the hook `/usr/bin/nvidia-cdi-hook` (`create-symlinks`, `update-ldcache`).

[ANALYSIS] CDI devices are resolved by the engine (the Podman service), not by the client that sends the
request. With a Podman machine, the engine is the machine's distro, so the spec and the
`nvidia-cdi-hook` binary it names must be in that distro. The device node and the driver store are
already visible there, so the toolkit installed in the machine should be enough. Copying the Ubuntu
distro's YAML alone would not work, because the hook binary is missing in the machine.

[ANALYSIS] The machine's distro is managed by Podman: re-creating the machine (`podman machine rm` and
`init`, or a reset) loses the toolkit and the spec, and a driver update changes the driver store's path
(`nvrfi.inf_amd64_<hash>`), so the spec must then be generated again.

**Founder step (pending), from the Ubuntu distro (or with `podman machine ssh` from Windows):**

```sh
wsl.exe -d podman-machine-default -u root -- sh -c '
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
    -o /etc/yum.repos.d/nvidia-container-toolkit.repo &&
  dnf install -y nvidia-container-toolkit &&
  nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml &&
  nvidia-ctk cdi list'
```

**The check to run after it** (the image is pulled again by digest; the spike removed its copy):

```sh
scripts/ygg-engine.sh run -- podman run --rm --device nvidia.com/gpu=all \
  docker.io/nvidia/cuda@sha256:59436e8ac61921052d8f420be8b8cb8b117f1d7cc643397a289e37aaa0b83ea1 nvidia-smi
```

Expected: the table lists `NVIDIA GeForce RTX 4090`.

**Done (2026-10-25).** The founder ran the step above. The machine then had `nvidia-container-toolkit-1.20.1-1`, and
the check passed:

```text
$ scripts/ygg-engine.sh run -- podman run --rm --device nvidia.com/gpu=all \
    docker.io/nvidia/cuda@sha256:59436e8ac61921052d8f420be8b8cb8b117f1d7cc643397a289e37aaa0b83ea1 \
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
name, memory.total [MiB], driver_version
NVIDIA GeForce RTX 4090, 24564 MiB, 610.88
```

The machine's PID 1 is WSL's init, not systemd, so the toolkit's `nvidia-cdi-refresh.path` and
`nvidia-cdi-refresh.service` units never run. The spec names one driver store folder
(`/usr/lib/wsl/drivers/nvrfi.inf_amd64_87b4cb6242e17d7d`); a driver update renames it.

[ANALYSIS] The setup must be repeatable by a script: the spec's `scripts/ygg-gpu.sh` (task LM-T15) installs what is
missing and finds a stale spec by checking that every driver store folder it names exists.

**Amendments proposed.**

- Spec §3.4, third bullet. Now: "`scripts/ygg-models.sh` starts it with the GPU (`--device
  nvidia.com/gpu=all`), the two read-only mounts, the network, and the published port on
  `127.0.0.1:<host_port>`." Proposed: "`scripts/ygg-models.sh` starts it with the GPU (`--device
  nvidia.com/gpu=all`), the two read-only mounts, the network, and the published port on
  `127.0.0.1:<host_port>`. The engine resolves the CDI device, so the NVIDIA container toolkit and
  its spec (`nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`) are installed where the engine runs:
  on a Podman machine under WSL2, inside the machine's distro (`podman-machine-default`), not in the
  distro that runs `ygg`. A driver update or a new machine needs the spec generated again. When the
  engine answers `unresolvable CDI devices`, `start` says so and names this step."
- Spec §9, item 1. Proposed: "Rootless Podman under WSL2 runs a CUDA container with `--device
  nvidia.com/gpu=all` after the toolkit is installed and `nvidia-ctk cdi generate` is run in the Podman
  machine's distro (§3.4)."

## Item 2: a published port from an internal network

**Result: confirmed.** A container on an internal network alone answers on its published port on
`127.0.0.1`, and still has no route out. The server needs no second network.

```text
$ scripts/ygg-engine.sh run -- podman network create --internal lmspike-int
lmspike-int
$ scripts/ygg-engine.sh run -- podman network inspect lmspike-int --format '{{.Internal}} {{.DNSEnabled}} {{range .Subnets}}{{.Subnet}} gw={{.Gateway}}{{end}}'
true true 10.89.13.0/24 gw=10.89.13.1
$ scripts/ygg-engine.sh run -- podman run -d --name lmspike-web --network lmspike-int -p 127.0.0.1:18088:80 --pull=never \
    30ecbe150909 sh -c 'echo lmspike-ok > /tmp/index.html; httpd -f -p 80 -h /tmp'
$ scripts/ygg-engine.sh run -- podman ps --filter name=lmspike- --format '{{.Names}} {{.Status}} {{.Ports}}'
lmspike-web Up 2 seconds 127.0.0.1:18088->80/tcp
$ curl -s -m 5 -w ' [%{http_code}]\n' http://127.0.0.1:18088/      # from the Ubuntu distro
lmspike-ok
 [200]
$ scripts/ygg-engine.sh run -- podman exec lmspike-web sh -c 'ip route; wget -T 4 -q -O /dev/null http://1.1.1.1/; echo "exit=$?"; nslookup -timeout=3 example.com'
10.89.13.0/24 dev eth0 scope link  src 10.89.13.2
wget: can't connect to remote host (1.1.1.1): Network is unreachable
exit=1
** server can't find example.com: NXDOMAIN
```

The image `30ecbe150909` is `docker.io/library/busybox@sha256:66a6306db78bf2dbf3487f293aa8d6990d8e506fdffab9cc43fe422becf886e4`.

[ANALYSIS] The published port is bound in the engine's network namespace. Under WSL2 every distro shares
that namespace, so `127.0.0.1` in the distro that runs `ygg` reaches it. This holds for a Podman machine
on WSL2; another platform (a VM-based machine) forwards the port its own way and would need its own check.

**Amendment proposed.** Spec §6, the bullet "No route out", last sentence. Now: "Whether the server needs a
second network for the published host port is a spike result (§9); a second network gives the server, not
the sandboxes, a route." Proposed: "The server sits on the internal network alone: a container on an
internal network publishes its port on `127.0.0.1` of the host and keeps no route out (spike, item 2)."
And §9 item 2 drops "If not, …".

## Item 3: the router's endpoints and the preset's format

**Result: confirmed, with details the spec must add.**

The server is the founder's host build, `llama-server` at llama.cpp `4c3c581` (its answers carry
`"system_fingerprint":"b50-4c3c581"`), started in router mode (no `-m`), in a scratch folder as its
working directory:

```sh
llama-server --models-preset preset.ini --models-max 1 --host 127.0.0.1 --port 18190
```

The preset had two sections naming the same weights (`$HOME/.local/share/qwen-local/models/model.gguf`):

```ini
version = 1

[qwen-a]
model = $HOME/.local/share/qwen-local/models/model.gguf   ; written as an absolute path
ctx-size = 8192
n-gpu-layers = 999
flash-attn = on
jinja = true
cache-type-k = q8_0
cache-type-v = q8_0
reasoning-effort = low
spec-type = draft-mtp
model-draft = $HOME/.local/share/qwen-local/models/mtp.gguf
n-gpu-layers-draft = all
parallel = 1

[qwen-b]
model = ../../<…>/models/model.gguf   ; relative to the server's working directory
c = 8192
ngl = 999
fa = on
LLAMA_ARG_CACHE_RAM = 0
```

### The preset's key format

Each probe started the router on a preset and read `GET /models`, whose `status.args` shows the command
line the router will give the model (it does not load it). The probe file was `version = 1`, a section
`[qwen-b]`, `model = <absolute path>`, and the line under test.

| Line under test | Result |
| --- | --- |
| `jinja` (bare key, no `=`) | the server stops: `failed to initialize router models: failed to parse server config file: <file>` |
| `no-mmap` (bare key) | the same |
| `jinja = true`, `jinja = on`, `jinja = 1` | `--jinja` |
| `jinja = false` | `--no-jinja` |
| `swa-full = true` / `swa-full = false` | `--swa-full` / left out |
| `no-warmup = true` | stored as `warmup = false`; `--no-warmup` |
| `warmup = false` | `--no-warmup` |
| `no-mmap = true` | the server stops: `option 'no-mmap' not recognized in preset 'qwen-b'` (this build has `--load-mode` in its place) |
| `foo-bar = 1` | the server stops: `option 'foo-bar' not recognized in preset 'qwen-b'` |
| `c = 8192`, `ngl = 999`, `fa = on` | `--ctx-size 8192`, `--n-gpu-layers 999`, `--flash-attn on` |
| `LLAMA_ARG_CACHE_RAM = 0` | `--cache-ram 0` |
| `alias = other` | `"aliases":["other"]`; the command line keeps `--alias qwen-b` (the section's name) |
| `port = 9999`, `host = 0.0.0.0` | dropped; the router sets `--host 127.0.0.1 --port 0` (then a free port) |
| `model = ../../<…>/model.gguf` | passed as written, `--model ../../<…>/model.gguf`; it loaded, because the router's working directory made it valid |
| `chat-template-file = rel/tpl.jinja` | passed as written, `--chat-template-file rel/tpl.jinja` |

The router adds `--log-colors off`, `--alias <section>`, and `--host 127.0.0.1 --port <free port>` to every
model's command line. The source confirms the host: `tools/server/server-models.cpp:60` has
`#define CHILD_ADDR "127.0.0.1"`, and `:524` sets `LLAMA_ARG_HOST` to it.

[ANALYSIS] So the format is: long option names without `--` (short names and `LLAMA_ARG_*` names are
accepted and rewritten to long names), `key = value`, and a flag with no value written `key = true`
(`false` writes its `--no-` form, or nothing for a flag without one). A key with no `=` or a key the build
does not know stops the whole router at start, so a bad `args` entry in the model list takes the server
down, not just its model. Relative paths are not resolved by the preset; they are resolved by the model's
process against the router's working directory. The spec's absolute `/models/...` paths avoid that.
Every model process listens on `127.0.0.1` of the server container only, so the router's port (8080) and
the gate's port are the container's only listeners.

### The endpoints

```text
$ curl -s http://127.0.0.1:18190/health
{"status":"ok"} [200]                                   # router mode, no model loaded
$ curl -s http://127.0.0.1:18190/models                 # GET /v1/models answers the same list
{"data":[{"id":"qwen-a","aliases":[],"tags":[],"object":"model","owned_by":"llamacpp","created":…,
  "status":{"value":"unloaded","args":[…],"preset":"[qwen-a]\n…"}, …},
 {"id":"qwen-b", …,"status":{"value":"unloaded", …}}]}
```

- **List and status:** `GET /models`. A model is `data[].id`; its status is `data[].status.value`. Values
  seen: `unloaded`, `loading`, `loaded`. The README of this build also documents `sleeping`,
  `downloading`, `incomplete`, and a failed load as `"value":"unloaded"` with `"failed":true` and
  `"exit_code"` (not seen in the spike). The `status.preset` string holds raw newlines, so a strict JSON
  parser refuses the body (Python's `json.loads` failed with `Invalid control character`; it read with
  `strict=False`).
- **Load:** `POST /models/load` with the body `{"model":"qwen-a"}` and `Content-Type: application/json`. It
  answers at once, before the model is loaded:

  ```text
  {"success":true} [200]
  ```

  Loading is done when `GET /models` shows `"value":"loaded"` for the model. Polled every 2 seconds, the
  first load showed `qwen-a=loading` 37 times, then `qwen-a=loaded`; a later load of `qwen-a` (below) took
  80 seconds by the clock. `qwen-a` loads the MTP draft too; `qwen-b`, without it, took 37 seconds.
  The stream `GET /models/sse` also reports it, as `data:` lines such as
  `{"model":"qwen-b","event":"status_change","data":{"status":"loading","progress":{"stages":["text_model"],"current":"text_model","value":0.10918386280536652}}}`.
- **Load of a model that is already running:**

  ```text
  {"error":{"code":400,"message":"model is already running","type":"invalid_request_error"}} [400]
  ```

- **Unload:** `POST /models/unload` with `{"model":"qwen-a"}` answers `{"success":true} [200]`; five seconds
  later both models were `unloaded` and the GPU held 1,697 MiB.

### What a request for the other model does

With `qwen-a` loaded (the GPU at 19,088 MiB):

```text
$ curl -s -d '{"model":"qwen-a","messages":[{"role":"user","content":"Say OK."}],"max_tokens":200}' …/v1/chat/completions
{"choices":[{"finish_reason":"stop",…,"message":{"role":"assistant","content":"OK.",…}}],"model":"qwen-a",…} [200]   # 1.2 s
$ curl -s -d '{"model":"nope",…}' …/v1/chat/completions
{"error":{"code":400,"message":"model 'nope' not found","type":"invalid_request_error"}} [400]
$ curl -s -d '{"model":"qwen-b",…}' '…/v1/chat/completions?autoload=false'
{"error":{"code":400,"message":"model is not loaded","type":"invalid_request_error"}} [400]
$ curl -s -d '{"model":"qwen-b","messages":[{"role":"user","content":"Say OK."}],"max_tokens":200}' …/v1/chat/completions
{"choices":[{…"message":{"role":"assistant","content":"OK",…}}],"model":"qwen-b",…} [200]   # 37.2 s
$ curl -s …/models    →  qwen-a=unloaded qwen-b=loaded       (GPU 18,081 MiB)
```

It swaps. The router's log:

```text
1.32.589.740 I srv          tick: evicting idle LRU name=qwen-a for a queued request
1.32.589.764 I srv  ensure_model: waiting until model name=qwen-b is fully loaded...
1.33.491.522 I srv           run: instance name=qwen-a exited with status 0
1.33.491.541 I srv  ensure_model: slot available, loading queued model name=qwen-b
```

An explicit load swaps too. With `qwen-b` loaded, `POST /models/load {"model":"qwen-a"}` answered
`{"success":true} [200]`, and `qwen-a` was loaded 80 seconds later:

```text
2.31.551.859 I srv    unload_lru: models_max limit reached, removing LRU name=qwen-b
2.32.484.489 I srv           run: instance name=qwen-b exited with status 0
```

The old model exits before the new one starts, so `--models-max 1` never holds two models on the GPU.
The router warns at start: `security: router mode enabled - do not expose to untrusted environments` and
`security: no API key is set and CORS allows all origins`.

After the router stopped:

```text
$ pgrep -a llama-server || echo "no llama-server running"
no llama-server running
$ nvidia-smi --query-gpu=memory.used,memory.total --format=csv
1697 MiB, 24564 MiB
```

[ANALYSIS] With autoload on (the default), a chat request for an unloaded model loads it, after evicting
the loaded one. Through the gate only the allowed model can be named, so a sandbox can at most reload the
run's own model; that is the same as today's design. A chat request that triggers a load blocks for the
whole load (37 to 80 seconds here), so a session's first request after an eviction is slow, not failed.

**Amendments proposed.**

- Spec §3.3, last sentence. Now: "The key format is confirmed by the spike (§9)." Proposed: "The file
  starts with `version = 1`. Keys are llama-server's long option names without `--`, written `key = value`;
  a flag with no value is written `key = true` (`false` gives its `--no-` form). A key without `=`, or a
  key this build does not know, stops the router at start. Paths are absolute: the preset does not resolve
  a relative path."
- Spec §3.2, the `args` bullets: add "A flag with no value is given as `"true"` or `"false"`. Keys are long
  names: `ParseModels` refuses a key that starts with `-` and a value that is empty." [ANALYSIS] `ygg` cannot
  know every option of the pinned build, so an unknown key is found when the server starts; `ygg-models.sh
  start` should print the end of the server's log when it exits at start.
- Spec §3.9, the `Ready` bullet. Now: "…writes the allow file, asks the server to load the model, and waits up
  to 300 seconds until it is loaded." Proposed: "…writes the allow file, asks the server to load the model
  (`POST /models/load` with `{"model":"<name>"}`; it answers 200 `{"success":true}` before the load is done,
  and 400 `model is already running` when the model is loaded, which Ready takes as success), and polls
  `GET /models` until the model's `status.value` is `loaded`, up to 300 seconds. A status with `"failed":
  true` ends the wait with an error that names `exit_code`. The list's JSON holds raw newlines in
  `status.preset`, so the client decodes it leniently or ignores that field." [ANALYSIS] Go's
  `encoding/json` also refuses a raw control character in a string; the client should decode only the
  fields it needs from a body with the control characters escaped, or test against a recorded body.
- Spec §3.5 (the gate): add "A request with a query string is refused (403)." [ANALYSIS] The router reads
  `?autoload=` from the query; refusing any query keeps the gate's contract to the method, the path and
  the body.

## Item 4: OpenCode and `@ai-sdk/openai-compatible`

**Result: confirmed.** At the version gleipnir pins, OpenCode uses the package without fetching it: with no
network, it fails on the connection to the provider's URL.

Gleipnir pins `OpenCode = "1.18.32"` (`sandbox/images.go:31`, at gleipnir `97f2aba`). The newest work images
hold that version:

```text
$ scripts/ygg-engine.sh run -- podman run --rm --network none --pull=never localhost/ygg-work:d5026c3ba0ed opencode --version
1.18.32
```

`localhost/ygg-work:bc6f2a499939` and `localhost/ygg-work:2fa0d45b58aa` also answered `1.18.32`. The run used
`localhost/ygg-work:d5026c3ba0ed` (image `b93d9c7c51e6`, Ubuntu 24.04), with no network, as the operator's
user, with the environment the adapter's `Run` sets (`opencode/opencode.go`):

```sh
echo "Say OK." | scripts/ygg-engine.sh run -- podman run --rm -i --name lmspike-oc --network none \
  --user 1000:1000 --userns keep-id --cap-drop ALL --pull=never \
  -e OPENCODE_CONFIG_CONTENT="$(cat oc-config.json)" -e OPENCODE_DISABLE_PROJECT_CONFIG=1 \
  -e OPENCODE_DISABLE_CLAUDE_CODE=1 -e OPENCODE_DISABLE_EXTERNAL_SKILLS=1 -e OPENCODE_DISABLE_AUTOUPDATE=true \
  -e OPENCODE_DISABLE_SHARE=true -e OPENCODE_DISABLE_MODELS_FETCH=true -w /tmp \
  localhost/ygg-work:d5026c3ba0ed opencode run --format json --print-logs --log-level DEBUG -m local/qwen-test
```

`oc-config.json`:

```json
{"$schema":"https://opencode.ai/config.json","autoupdate":false,"share":"disabled",
 "provider":{"local":{"npm":"@ai-sdk/openai-compatible","name":"local",
   "options":{"baseURL":"http://lmspike-unreachable:8089/v1"},
   "models":{"qwen-test":{"name":"qwen-test","tool_call":true,"reasoning":true,"limit":{"context":102400,"output":32768}}}}},
 "small_model":"local/qwen-test"}
```

The output (44 lines, exit 1). No line names npm, bun or an install (`grep -c -i "npm\|bun add\|install"` gives
0). The relevant lines:

```text
level=DEBUG message="loaded custom config from OPENCODE_CONFIG_CONTENT"
level=INFO message=created id=ses_… version=1.18.32 projectID=global directory=/tmp …
level=INFO message="llm runtime selected" llm.runtime=ai-sdk llm.provider=local llm.model=qwen-test
level=ERROR message="stream error" providerID=local modelID=qwen-test … error.error="AI_APICallError: Cannot connect to API: Was there a typo in the url or port? …"
level=ERROR message="stream error" … small=true agent=title … error.error="AI_RetryError: Failed after 3 attempts. Last error: Cannot connect to API: Unable to con…"
{"type":"error",…,"error":{"name":"APIError","data":{"message":"Cannot connect to API: Unable to connect. Is the computer able to access the url?","isRetryable":true,"metadata":{"url":"http://lmspike-unreachable:8089/v1/chat/completions"}}}}
```

The image holds no copy of the package on disk, and the home folder is empty:

```text
$ scripts/ygg-engine.sh run -- podman run --rm --network none --pull=never localhost/ygg-work:d5026c3ba0ed \
    sh -c 'ls -A /home/ygg; find / -xdev -type d -name "openai-compatible" -path "*@ai-sdk*"'
(no output)
```

[ANALYSIS] The provider package is bundled in the `opencode` binary. The session retried the build agent's
request six times, from 22:22:07 to 22:23:11 (64 seconds), before it ended with exit 1. A session whose
model server is down therefore fails after about a minute, not at once; `Ready` checking the server before
any sandbox starts (§3.9) stays the place that fails fast.

**Amendment proposed:** none.

## Item 5: the firewall sidecar resolves the server's name

**Result: confirmed.** A firewall sidecar on a non-internal network and on an internal network resolves a
container that is only on the internal network, through the resolver its `egress.sh` takes (the first
`nameserver`), and the work container reaches it by name.

The setup, like gleipnir's compose file (`sandbox/config.go`: the firewall on `default` and the services
network): the firewall image `02a9befb3993` (`localhost/ygg-fw:ff37f2323321`), gleipnir's
`sandbox/assets/egress.sh` (last changed in `f003f21`), a hosts file with `openrouter.ai`, and a services file
with `lmspike-web 80`. `lmspike-web` is the item 2 container, on `lmspike-int` alone.

```sh
scripts/ygg-engine.sh run -- podman network create lmspike-def
scripts/ygg-engine.sh run -- podman create --name lmspike-fw --network lmspike-def,lmspike-int \
  --user 0:0 --userns keep-id --cap-add NET_ADMIN --pull=never 02a9befb3993 \
  sh /etc/ygg-fw/egress.sh /etc/ygg-fw/hosts /etc/ygg-fw/services
scripts/ygg-engine.sh run -- podman cp fw lmspike-fw:/etc/ygg-fw      # egress.sh, hosts, services
scripts/ygg-engine.sh run -- podman start lmspike-fw
```

In the sidecar:

```text
resolv.conf:
search dns.podman dns.podman
nameserver 10.89.14.1          # lmspike-def's gateway: the one egress.sh uses
nameserver 10.89.13.1          # lmspike-int's gateway
dnsmasq.conf (the services line):
server=/lmspike-web/10.89.14.1
iptables -S (the rules the script made):
-A YGG_HOSTS_A -d 104.18.2.115/32 -p tcp -m tcp --dport 443 -j ACCEPT
-A YGG_HOSTS_A -d 104.18.3.115/32 -p tcp -m tcp --dport 443 -j ACCEPT
-A YGG_HOSTS_A -d 10.89.13.2/32 -p tcp -m tcp --dport 80 -j ACCEPT
$ getent ahostsv4 lmspike-web
10.89.13.2      STREAM lmspike-web.dns.podman
```

From a work container in the sidecar's network namespace (the work image, the operator's user, no
capabilities):

```text
$ scripts/ygg-engine.sh run -- podman run --rm --name lmspike-work --network container:lmspike-fw \
    --user 1000:1000 --userns keep-id --cap-drop ALL --security-opt no-new-privileges:true --pull=never \
    localhost/ygg-work:d5026c3ba0ed sh -c '…'
uid=1000
getent hosts lmspike-web:
10.89.13.2      lmspike-web
exit=0
node fetch http://lmspike-web/:
status ok: lmspike-ok
getent hosts example.com:
exit=2
```

With busybox in the same namespace, `wget -T 4 http://10.89.13.2:81/` (a port the services file does not list)
timed out, and `nslookup example.com` got `REFUSED` from dnsmasq. `nslookup lmspike-web` asked first for
`lmspike-web.dns.podman`, which dnsmasq refuses (`REFUSED`), while `nslookup lmspike-web.` answered
`10.89.13.2`; glibc's resolver, which `getent` and Node use, falls through to the bare name.

The network check §3.7 needs:

```text
$ scripts/ygg-engine.sh run -- podman network inspect lmspike-int --format '{{.Internal}}'
true
```

[ANALYSIS] The resolver of the first network (`lmspike-def`) answered for a container that is on another
network (`lmspike-int`) only: aardvark-dns, netavark's DNS server, answers for the containers on every network the asking
container shares. So the order of the sidecar's networks does not matter. The spike joined the networks
with `podman run --network a,b`, not with compose's `external: true`; podman-compose turns that into the same
join, and spec §5.3's integration tests run the compose path.

**Amendment proposed:** none. [ANALYSIS] Spec §3.7 could name the check: "`Up` refuses the sandbox when
`podman network inspect --format '{{.Internal}}' <Network>` does not print `true`."

## What the spike made and removed

All made with the prefix `lmspike-` and removed through `scripts/ygg-engine.sh run`:

- Containers: `lmspike-web` and `lmspike-fw`, removed with `podman rm -f`. `lmspike-cuda`, `lmspike-oc`,
  `lmspike-work`, `lmspike-ver` and `lmspike-ls` ran with `--rm`.
- Networks: `lmspike-int` and `lmspike-def`, removed with `podman network rm`.
- The image `docker.io/nvidia/cuda:12.9.1-base-ubuntu22.04` (`2e1e354f0a7e`), pulled by the spike, removed with
  `podman rmi`.
- The host `llama-server` (router and its model processes) was stopped; no `llama-server` runs and the GPU is
  back to 1,697 MiB.

Afterwards no container, network or image named `lmspike-` was left. The weights were read in place, never
copied or moved.
