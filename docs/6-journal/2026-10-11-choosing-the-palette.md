---
date: 2026-10-11
tags: [brand, design, accessibility]
status: resolved
post-candidate: yes
evidence: [../7-branding/identity/README.md]
---
## Challenge

Define the palette: the colours every doc, diagram and product built by Ouroboric will share, dark
mode first.

## Context

An informal palette was already in use: Midnight with International Orange. The theme is Nordic, so
a blue might have fitted better. A logo concept arrived halfway through: an ouroboros snake over a
ring of orange blocks.

## Options

Four rounds on an interactive page with live WCAG checks:

1. Five complete palettes: Midnight Ember, Fjord (glacier blue), Aurora (green and violet), Frost and
   Iron (ice blue), Asgard Gold.
2. Neutrals fixed; accent candidates on the logo concept, recoloured in the browser.
3. A dark-mode logo with the snake kept Midnight, betting the orange outline would be enough.
4. Vivid accents only, and a contour around the snake in dark mode.

## Decision

Midnight neutrals with International Orange (`#FF4F00`), the original palette.

## Result

Design tokens in `7-branding/identity/`, every pair passing WCAG AA, and the diagrams fixed to use
Midnight labels on orange. Still open: the final logo artwork, the dark-mode logo contour, the favicon
and typography.

## Lessons

- Exploration can confirm the first instinct, and still pay for itself: it produced the rules.
- Bright accents need separate shades by role: a fill for shapes, a text shade for links, and a label
  colour on top. Neon yellow, green and cyan can't carry text on white at all.
- White on International Orange is 3.3:1 and fails accessibility; Midnight on it is 5.9:1. The
  diagrams had been using the failing pair.
- Muted, "tasteful" palettes didn't fit this brand. It wanted a strong colour.
- A dark logo on a dark background needs a contour. Betting on the accent outline alone failed.
