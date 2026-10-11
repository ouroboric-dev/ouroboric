---
title: Identity
status: accepted
date: 2026-10-11
related: [tokens.css, tokens.json, ../story/naming-and-mythology.md, ../prompts/nano-banana-logo-prompts.md]
style: guide
---

# Identity

The Ouroboric design language. Dark mode comes first; light mode is equally supported.

## Palette

**Decided 2026-10-11:** Midnight neutrals with **International Orange** (`#FF4F00`) as the single
accent.

| Token | Dark (default) | Light | Use |
|---|---|---|---|
| `bg` | `#0B0D12` | `#FFFFFF` | page background |
| `surface` | `#14171F` | `#F4F5F7` | panels, code, sidebars |
| `border` | `#2A303C` | `#D8DCE3` | dividers and outlines (decorative) |
| `text` | `#EDEFF3` | `#0B0D12` | body text |
| `muted` | `#9AA3B2` | `#4F5868` | secondary text |
| `accent` | `#FF4F00` | `#FF4F00` | brand colour: logo, buttons, approval points, highlights |
| `accent-text` | `#FF4F00` | `#B83A00` | accent used as text, such as links |
| `on-accent` | `#0B0D12` | `#0B0D12` | text and icons on an accent fill |
| `ok` | `#3FB950` | `#1A7F37` | passed status |
| `warn` | `#D29922` | `#9A6700` | warning status |
| `crit` | `#F85149` | `#CF222E` | failed status |

The tokens are machine-readable in [`tokens.css`](tokens.css) and [`tokens.json`](tokens.json).
Docs themes, diagrams and realm templates take their colours from these files.

## Rules

1. **Text on orange is Midnight, never white.** Midnight on International Orange is 5.9:1 and passes
   WCAG AA; white on it is 3.3:1 and fails. This applies to buttons, approval points in diagrams, and
   the logo.
2. **Orange text on white uses `accent-text`.** `#FF4F00` on white is 3.3:1, enough for shapes but not
   for text; `#B83A00` is 5.8:1. On the dark background, `#FF4F00` passes as text (5.9:1).
3. **Orange means "brand" and "a human decides here".** It marks the logo, primary actions and
   approval points. Don't use it for errors; failed states use `crit`.
4. **Status colours stay separate** from the accent: passed, warning and failed use `ok`, `warn` and
   `crit`.

## Contrast

All pairs in the table pass WCAG AA for their use, in both modes: text pairs at 4.5:1 or more, the
accent as a shape at 3:1 or more.

| Pair | Dark | Light |
|---|---|---|
| text on bg | 16.9:1 | 19.4:1 |
| muted on bg | 7.6:1 | 7.2:1 |
| accent-text on bg | 5.9:1 | 5.8:1 |
| on-accent on accent | 5.9:1 | 5.9:1 |
| accent (shape) on bg | 5.9:1 | 3.3:1 |

## Still open

- **Logo:** the concept (an ouroboros snake over a ring of orange blocks, with the `OUROBORIC.DEV`
  wordmark and `.DEV` in orange) needs final vector artwork.
- **Dark-mode logo:** the Midnight snake merges with the dark background. A contour, light or accent,
  is needed; to be decided with the vector artwork.
- **Favicon:** in progress. Below 32 px the icon's fine details disappear; the ring of orange blocks
  is the most recognisable part at 16 px.
- **Typography:** to be chosen, from fonts under the SIL Open Font License.
