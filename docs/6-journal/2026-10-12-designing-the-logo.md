---
date: 2026-10-12
tags: [brand, design, logo, accessibility]
status: resolved
post-candidate: yes
evidence: [../7-branding/identity/logo/README.md, ../7-branding/identity/logo/concepts/README.md]
---
## Challenge

Turn the founder's raster logo proposals into a vector logo, a wordmark and a favicon that work from a
banner down to a 16 px browser tab, in both colour modes.

## Context

The founder made three proposals as JPEGs, each with a light and a dark version, and later a favicon
drawing. The typography was already decided: the wordmark had to be Cinzel. The dark versions had
switched to a light snake, which settled the open question of a contour for dark mode.

## Options

- **Logo:** carved knot, smooth scales, or a ring of blocks. All three were traced with potrace,
  recoloured to the palette and compared large, at favicon sizes and next to the wordmark.
- **Favicon:** nine explorations. Geometric rings read as loading spinners. Carved versions came
  next, then a version whose head, eye and tail were measured from the logo, then the founder's own
  drawing tuned for 16 px.

## Decision

The carved knot, for its Nordic character. A favicon that combines the measured head and body with
the founder's tail, which carries a gate. The wordmark is Cinzel 800 converted to outlines. All three
proposals and the favicon explorations stay in the repo as concepts.

## Result

Icon, wordmark and horizontal logo in light and dark, `favicon.svg` that switches with the browser's
colour scheme, `favicon.ico` with 16, 32 and 48 px layers, and 180, 192 and 512 px app icons. The logo
files are under the trademark policy instead of CC BY. RB-21 is met.

## Lessons

- Measure before simplifying. The founder pointed out that the favicon's head sat at 12 o'clock while
  the logo's sits to the right. Measuring the logo's polar profile gave the exact angles and sizes for
  the head, eye and tail.
- A favicon is judged at 16 px, and a vector preview hides it. Rendering 16 px and enlarging the
  pixels showed that gaps of 1% of the width turn into grey specks.
- Widening every gap of an interwoven design breaks it into fragments. Closing the thin gaps and
  keeping only a few wide cuts kept its character.
- Colour separates shapes too. The gap between the black head and the orange tail could be narrower
  than the gaps between black scales, which kept the tail inside the mouth.
- A logo needs a licence decision before it lands in a docs folder. Under the docs' default CC BY,
  anyone could have copied and adapted it.
- AI-generated sources and Windows download markers (`Zone.Identifier` files) stay out of the repo;
  only the final vectors and exports are published.
