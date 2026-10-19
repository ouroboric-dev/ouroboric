#!/usr/bin/env bash
# Run OpenCode against the local Qwen 3.8 27B server, and nothing else
# (docs/5-research/2026-10-19-local-qwen-design.md). Start the server first: qwen-local.sh start.
#   qwen-opencode.sh [OPENCODE ARGS...]     for example: qwen-opencode.sh, or qwen-opencode.sh run "..."
# The configuration goes in through OPENCODE_CONFIG_CONTENT, with the running server's port and
# context. Only the local provider is enabled, and the cloud credentials of the caller's shell are
# removed. OpenCode does not read ~/.claude (the work account's Claude Code config) or outside
# skills, and does not update, share sessions or fetch the models.dev catalogue. The project's own
# OpenCode config still applies. QWEN_OPENCODE_BIN overrides the binary (opencode).
# OpenCode 2 runs sessions in a background service that keeps the config and environment it started
# with, so this script always passes --standalone (after `run`, or first for the interactive session):
# a private server that gets exactly this config.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=qwen-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/qwen-lib.sh"
qwen_require_server

# OpenCode 2 still reads these keys (provider, enabled_providers, small_model, autoupdate), though its
# schema marks them deprecated. Gleipnir's adapter uses the same ones.
# shellcheck disable=SC2016  # "$schema" is a JSON key, not a variable
conf="$(printf '{"$schema":"https://opencode.ai/config.json","autoupdate":false,"share":"disabled","enabled_providers":["qwen-local"],"provider":{"qwen-local":{"npm":"@ai-sdk/openai-compatible","name":"Qwen local","options":{"baseURL":"%s/v1"},"models":{"%s":{"name":"Qwen 3.8 27B (local)","tool_call":true,"reasoning":true,"limit":{"context":%s,"output":32768}}}}},"model":"qwen-local/%s","small_model":"qwen-local/%s"}' \
  "$(qwen_url)" "$QWEN_ALIAS" "$QWEN_CTX" "$QWEN_ALIAS" "$QWEN_ALIAS")"

if [ "${1:-}" = run ]; then shift; set -- run --standalone "$@"; else set -- --standalone "$@"; fi
exec env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_OAUTH_TOKEN -u OPENROUTER_API_KEY \
  OPENCODE_CONFIG_CONTENT="$conf" \
  OPENCODE_DISABLE_CLAUDE_CODE=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1 \
  OPENCODE_DISABLE_AUTOUPDATE=true OPENCODE_DISABLE_SHARE=true OPENCODE_DISABLE_MODELS_FETCH=true \
  "${QWEN_OPENCODE_BIN:-opencode}" "$@"
