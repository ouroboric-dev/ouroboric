---
title: Name checks
status: accepted
date: 2026-10-12
related: [../7-branding/story/naming-and-mythology.md, ../1-company/readiness/2026-10-11-ready-to-build.md]
style: research
---

# Name checks

Checks for readiness item RB-06, run on 2026-10-12: the domain, package registries, GitHub, and a
trademark screening for "Ouroboric", "Yggdrasil", "Asgard", the `ygg` CLI and the module names. The
trademark part is a web screening, **not a clearance search**.

## Domain

`ouroboric.dev` was registered on 2026-10-10 through Porkbun LLC, expires on 2031-10-10, and carries
the client transfer and delete locks (source: the `.dev` registry's RDAP service,
`pubapi.registry.google`). The founder confirmed it is theirs. Its nameservers are Porkbun's; no
website or certificate is set up yet, and `.dev` requires HTTPS.

## Registries and GitHub

Each registry's public API, queried on 2026-10-12. "Taken" means the name exists there.

| Name | npm | PyPI | crates.io | Docker Hub | Homebrew core | GitHub account |
| --- | --- | --- | --- | --- | --- | --- |
| `ouroboric` | free | free | free | taken (see the note below) | free | taken (organisation "Ouroboric", created 2018, no public repos) |
| `yggdrasil` | taken | taken | taken | taken | free | taken |
| `asgard` | taken | taken | taken | redirect (unclear) | free | taken |
| `ygg` | taken | taken | taken | free | free | taken |
| `odin` | taken | taken | taken | taken | taken | taken |
| `gleipnir`, `jormungandr`, `gungnir`, `norns` | taken | taken | free | taken | free | taken |
| `havamal` | free | free | free | taken | free | taken |
| `ginnungagap` | taken | free | free | taken | free | taken |
| `ratatoskr`, `mimir`, `bragi` | taken | taken | taken | taken | free | taken |

Method notes: Docker Hub's `namespaces/<name>/repositories` endpoint answers for any name, so the
`users/<name>` endpoint decided the Docker column. The GitHub column used the public `users` API.

**Correction, 2026-10-12:** the `users` endpoint does not see organisations or reserved names. When
the founder tried to claim `ouroboric` on Docker Hub, it was already in use, although the lookup had
reported it free. Treat the Docker column's "free" results as unconfirmed. Docker namespaces also
allow only lowercase letters and digits, so `ouroboric.dev` and `ouroboric-dev` are not possible.

## Trademarks

Web searches on 2026-10-12 found:

- **Ouroboric:** no mark. The nearest is **OROBOROUS**, US serial 87605000, owned by Talon Code
  Mapper LLC, for online programming software (source: Justia's trademark index). Its current status
  could not be confirmed from public pages.
- **Asgard:** a UK application, **Asgard Analytics** (UK00004230292), published in July 2025, covering
  software in classes 9 and 42, with classes 35 and 41 (source: UK IPO Trade Mark Journal 2025/029).
  A US **ASGARD SOFTWARE** registration (1901503, class 9) is cancelled (source: Justia). An Australian
  **Asgard Capital Management** mark covers financial software in class 9 (source: IP Australia).
- **Yggdrasil:** no software mark found. The **Yggdrasil Network**, an open-source mesh network
  written in Go, is a prominent name collision (already in the naming rules).

## Analysis

[ANALYSIS] Only "Ouroboric" is distinctive and free almost everywhere (Docker Hub is the exception), so it is the name worth
protecting. "Yggdrasil", "Asgard" and the module names are common Norse words used by many projects.
They work as product names under the Ouroboric umbrella ("Ouroboric Yggdrasil"), and the factory
needs none of the taken registry names: it ships as Go modules under `github.com/ouroboric-dev/...`
and binaries on GitHub releases, with an own Homebrew tap.

[ANALYSIS] An unclaimed `ouroboric` on a package registry lets anyone publish a package by that
name. People looking for the official one could install it, so a fake package is a ready-made
malware channel. Claiming the names closes it.

[ANALYSIS] "OROBOROUS" sounds close to "Ouroboric" and covers programming software. If it is live, it
could matter for a commercial launch. It does not affect building or learning in public.

## Decisions

- **Decided 2026-10-12:** RB-06 is met for building. A formal trademark search for "Ouroboric" in
  the official registers (USPTO, EUIPO through TMview), including OROBOROUS, happens before any
  public launch or commercial use (Asgard checklist RL-08).
- **Decided 2026-10-12:** the founder claims `ouroboric` on npm (organisation and scope
  `@ouroboric`) and PyPI. PyPI needs a minimal, honest package rather than an empty placeholder,
  because its policy allows reclaiming names without a real project; the package lives in
  [ouroboric-packages](https://github.com/ouroboric-dev/ouroboric-packages).
- **Decided 2026-10-12:** crates.io is skipped. Ouroboric has no Rust code planned, so a look-alike
  crate would reach few people, and the official channels in `ouroboric-packages` say any
  `ouroboric` crate is not ours. If Ouroboric ever ships Rust, the crate may need another name.
- **Decided 2026-10-12:** official container images live on GitHub Container Registry under the org
  we own, `ghcr.io/ouroboric-dev/...`. Ouroboric has no Docker Hub namespace, and documentation
  names GHCR as the only official source, so a look-alike on Docker Hub can't pass as ours.
