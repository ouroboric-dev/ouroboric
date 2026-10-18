---
date: 2026-10-10
tags: [stack, cloud, architecture]
status: open
post-candidate: yes
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/5-research/research-stack.md, https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#2-architecture]
---
## Challenge

Which language and runtime for the factory itself?

## Context

The first proposal was TypeScript, for a weak reason: the existing projects used it. The operator
pushed back, preferring Go but open to Akka/Pekko on the JVM for its actor model.

## Options

Researched six: Go, TypeScript, Python, Rust, Elixir/BEAM, and Java 21 + Pekko (plus "Go + Temporal").

- Most orchestrators that drive agent CLIs are written in Go (Gas Town, Beads, Claude Squad, Crush,
  Dagger, container-use).
- Pekko has the most mature event sourcing and supervision, but the heaviest distribution and the
  most ceremony. Akka itself still needs a commercial licence in production; Pekko is the Apache fork.

## Decision

Go. Follow-up question: would running in the cloud later favour Pekko? No. The slow, expensive part
is the agent sessions, not orchestrator throughput; in the cloud the platform (Kubernetes Jobs,
hosted sandboxes) schedules the heavy work; and cloud tooling is largely Go. Cloud readiness comes
from three swappable interfaces: agent adapter, sandbox driver and state store.

## Result

Pending.

## Lessons

Question the defaults an assistant proposes. "Your projects use it" is not an architecture reason.
Ask what the program mostly does (here: launch and supervise processes, write logs) and pick for that.
