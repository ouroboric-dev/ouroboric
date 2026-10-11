---
date: 2026-10-11
tags: [docs, diagrams, security, tooling]
status: resolved
post-candidate: yes
evidence: [../4-ways-of-working/diagrams.md, ../assets/diagrams/ouroboric-map.d2]
---
## Challenge
The documents were long and textual. Reviewers needed pictures, but there was no docs build yet to
render diagrams.

## Context
marola renders Mermaid, D2 and other diagram fences at build time through a self-hosted Kroki.

## Options
Hand-drawn images now and redrawn later; or diagram sources now, rendered locally, with the build
taking over later.

## Decision
Sources as code in `docs/assets/diagrams/`, rendered by a local Kroki through a script, embedded as
SVG under a marker comment that names the source. When the build lands, a mechanical swap turns each
marker into a fence and the committed SVGs go away. Twelve diagrams, including a map of the whole
company.

## Result
All twelve render and pass the freshness check. Two findings along the way:
- **The container engine is rootful.** Podman on this machine talks to a Podman Desktop VM through its
  root socket, while the design assumed rootless. This is now a spike item.
- **A work credential helper fired on a public image pull.** The script now pulls with an empty,
  isolated auth file, so public pulls never carry the host's registry credentials.

## Lessons
- Verify renders the way readers will see them. A PNG converter showed empty boxes because it drops
  Mermaid's HTML labels; a real browser showed them. The fix (SVG text labels) also makes diagrams
  safe for GitHub and previewers.
- Small tooling tasks surface real environment facts. Neither the rootful socket nor the credential
  helper would have shown up in a design review.
