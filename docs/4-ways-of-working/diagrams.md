---
title: Diagrams
status: draft
date: 2026-10-11
related: [docs-standard.md, writing-styles.md]
style: guide
---

# Diagrams

Diagrams are written as code, kept next to the docs, and rendered to SVG through a **local**
[Kroki](https://kroki.io). The pattern follows marola's
[DIAGRAMS.md](https://github.com/marola-dev/marola/blob/main/docs/3-Ways-of-working/DIAGRAMS.md).
Until the docs build exists, a script renders the SVGs and the docs embed them as images; when the
build lands, it renders the same sources itself.

## 1. Which dialect

| Picture | Dialect | File extension |
|---|---|---|
| flow, decision tree, pipeline, lifecycle, sequence, state, ER, gantt | Mermaid | `.mmd` |
| layered or zoned architecture, module maps, trust boundaries | D2 | `.d2` |
| people and systems (C4 context or container) | C4-PlantUML | `.puml` |
| a database schema | DBML | `.dbml` |
| a chart from numbers (benchmarks, metrics) | Vega-Lite | `.vl.json` |
| a sketch or wireframe, only when hand-drawn is genuinely clearer | Excalidraw | `.excalidraw` |

## 2. Rules

- **The prose is the source of truth.** Draw only what the text beside the diagram says, and keep the
  text. A diagram that disagrees with its page is a bug in the diagram.
- **Keep diagrams under about 15 nodes.** Split a diagram rather than grow it.
- **Labels are short and plain.** Use the words the page uses.
- **Colour has one meaning.** International Orange (#FF4F00) marks human approval points, hard stops,
  and trust boundaries. Everything else is neutral: the render script injects a Midnight (#0B0D12) on
  white palette into Mermaid, and D2 sources use D2's neutral grey theme (`theme-id: 1`) with orange set
  inline on the elements that need it.
- **Every image has alt text** that states what the diagram shows, for readers who can't see it.
- **Mermaid labels are plain SVG text.** The render script sets `htmlLabels: false`, because GitHub and
  some Markdown previewers drop the HTML labels Mermaid uses by default, leaving empty boxes.
- **Check renders in a browser.** Tools such as `rsvg-convert` also drop HTML labels and give a false
  alarm; open the SVG in a browser, or screenshot it with headless Chrome.
- **Excalidraw needs an extra 612 MB container.** Use it only where a sketch earns it.

## 3. Where files live

```
docs/assets/diagrams/
  <name>.mmd | .d2 | .puml | .dbml | .vl.json | .excalidraw    the source (edit this)
  rendered/<name>.svg                                          generated; never edit by hand
  rendered/manifest.tsv                                        source hashes, for the freshness check
```

A page embeds a diagram with a marker comment naming its source, then the rendered image:

```markdown
<!-- diagram: assets/diagrams/architecture.d2 -->
![Yggdrasil architecture: the ygg CLI drives Odin, which uses Gleipnir, Jormungandr and the realms](../assets/diagrams/rendered/architecture.svg)
```

The marker path is relative to `docs/`; the image path is relative to the page.

## 4. Render locally

The script is `scripts/diagrams.sh` in the `ouroboric` repository.

1. Start Kroki: `scripts/diagrams.sh up` (Kroki core and its Mermaid companion, pinned to
   0.32.1, in a Podman pod bound to `127.0.0.1:8000`).
2. Render a repository's diagrams: `scripts/diagrams.sh render ../yggdrasil`.
3. Check freshness: `scripts/diagrams.sh check ../yggdrasil`. The check fails when a source changed
   without re-rendering, or a marker names a missing source.
4. Stop Kroki: `scripts/diagrams.sh down`.

**Kroki stays local.** The script refuses any non-local Kroki URL unless you set
`DIAGRAMS_ALLOW_REMOTE=1`. Diagram sources describe architecture and security controls; sending a
private product's diagrams to a public rendering service would publish them.

## 5. When the docs build lands

The docs build (Zensical with a Kroki plugin, iteration 2) renders diagrams itself. Then:

1. A script replaces each marker and image pair with a fence that loads the same source, for example
   a `d2` fence containing `@from_file:assets/diagrams/architecture.d2`.
2. `rendered/` is deleted and ignored.
3. The freshness check is replaced by the build's own failure on a broken diagram.
4. Diagrams used outside the docs site keep a committed SVG: the organisation profile
   (`.github/profile/README.md`) links `ouroboric-map.svg` directly, so that file stays rendered and
   committed.

The sources don't change, which is why they live in their own files today.
