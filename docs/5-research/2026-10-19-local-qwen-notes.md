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
7. **Set up the local Claude Code config dir.** Run `scripts/qwen-claude.sh init`.

First run (2026-10-20), with a 30-token coding prompt at low effort:

- Decode speed was 98.5 tokens per second.
- MTP accepted 210 of 309 drafted tokens (68%).
- The reasoning was 887 characters long.

`/v1/messages`, the Anthropic Messages API, answered with a `thinking` block and a `text` block.

## Measurements

## Comparison

## Lessons
