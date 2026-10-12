---
title: Diagrams
status: accepted
date: 2026-10-12
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
- **Diagrams follow the [identity](../7-branding/identity/README.md).** The render script reads the
  palette from `tokens.json` and sets every diagram in **Inter**, the interface face. Each diagram is
  rendered twice: `<name>.svg` in the light palette and `<name>.dark.svg` in the dark palette.
- **Colour has one meaning.** International Orange marks human approval points, hard stops and trust
  boundaries. Everything else is neutral: text, muted lines and outlines, surface-coloured groups.
  Text on orange is Midnight, never white.
- **Sources never contain colour codes.** A colour written into a source would be right in one mode
  and wrong in the other. Use the names the script provides instead:
  - **D2:** `${accent}`, `${muted}`, `${surface}`, `${border}`, `${text}`, `${bg}` and `${on-accent}`
    in styles, for example `style.stroke: ${accent}`. Don't add a `vars.d2-config` block; the script
    sets the theme.
  - **Mermaid:** the classes `gate` (an orange approval point), `cond` (a dashed orange outline, for a
    conditional step) and `inverse` (text-coloured fill, for emphasis), for example
    `class GD gate`. Don't write `classDef` lines; the script adds them for each mode.
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
  rendered/<name>.svg, rendered/<name>.dark.svg               generated; never edit by hand
  rendered/manifest.tsv                                        source hashes, for the freshness check
```

A page embeds a diagram with a marker comment naming its source, then a `<picture>` that shows the
dark render in dark mode and the light render otherwise:

```markdown
<!-- diagram: assets/diagrams/architecture.d2 -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/diagrams/rendered/architecture.dark.svg">
  <img alt="Yggdrasil architecture: the ygg CLI drives Odin, which uses Gleipnir, Jormungandr and the realms" src="../assets/diagrams/rendered/architecture.svg">
</picture>
```

The marker path is relative to `docs/`; the image paths are relative to the page. GitHub shows the
render that matches the reader's GitHub theme. The `alt` text is the same for both.

## 4. Render locally

The script is `scripts/diagrams.sh` in the `ouroboric` repository.

1. Start Kroki: `scripts/diagrams.sh up` (Kroki core and its Mermaid companion, pinned to
   0.32.1, in a Podman pod bound to `127.0.0.1:8000`). The first run downloads Inter 4.1 from its
   official release, checks it against a pinned SHA-256, caches it in `~/.cache/ouroboric/fonts/` and
   copies it into the pod.
2. Render a repository's diagrams: `scripts/diagrams.sh render ../yggdrasil`.
3. Check freshness: `scripts/diagrams.sh check ../yggdrasil`. The check fails when a source changed
   without re-rendering, or a marker names a missing source.
4. Stop Kroki: `scripts/diagrams.sh down`.

**How the font gets into the SVG.** An SVG shown as an image can't load web fonts, so each SVG carries
its own copy of the glyphs it uses. D2 runs as a CLI inside the pod, because only the CLI accepts
custom fonts, and it embeds them itself. For Mermaid, the script installs Inter in the Mermaid
container so labels are measured with Inter, then embeds the used glyphs with fonttools (pinned, run
through `uv`). The script needs `podman`, `curl`, `unzip`, `python3` and `uv`.

**Freshness covers the theme.** The manifest records each source's hash and a hash of the render
setup (the script and `tokens.json`). Changing the palette or the script marks every diagram stale.

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

The build must apply the same theme: the token palette, Inter, and both light and dark renders. Until
a plugin can, the script stays the renderer. The sources don't change, which is why they live in their
own files today.
