---
date: 2026-10-11
tags: [brand, diagrams, accessibility, tooling]
status: resolved
post-candidate: yes
evidence: [../4-ways-of-working/diagrams.md, ../../scripts/diagrams.sh]
---
## Challenge
Make the diagrams follow the design language: the token palette, the Inter typeface, and dark mode
first.

## Context
The diagrams used a hand-written light palette with two off-palette greys, Open Sans in Mermaid and
Source Sans Pro in D2. There was no dark version. The Mermaid SVGs had a transparent background and
Midnight text, so on GitHub in dark mode their labels were nearly invisible.

## Options
1. One dark render for every page: on-brand, but a dark block on every light page.
2. A light and a dark render of each diagram, chosen by the reader's colour scheme.
3. One SVG that switches palette inside itself with a CSS media query: D2 supports it, Mermaid
   doesn't, and an SVG shown as an image follows the operating system, not the GitHub theme.

## Decision
Option 2. The render script reads `tokens.json` and renders `<name>.svg` and `<name>.dark.svg`. Pages
embed both through `<picture>`. Sources name colours (`${accent}`, the `gate` class) instead of
writing colour codes.

## Result
All 13 diagrams in the token palette and Inter, in both modes, with the font embedded in each SVG.
The freshness check now also fails when the palette or the script changes.

## Lessons
- An SVG shown as an image can't load web fonts. To show a brand font everywhere, embed the glyphs in
  the SVG itself.
- Text is measured when the diagram is laid out, so the renderer needs the font too. A font that is
  only embedded afterwards makes labels overflow their boxes.
- D2's theme colour codes don't work inside styles, but its variables do, so the script injects the
  palette as variables.
- A transparent background with dark text works on exactly one page colour.
- A clean-up command buried in a long shell chain was stopped before it ran: `rm` with a variable path
  could have deleted far more than intended. Temporary output now goes to a fresh directory instead.
