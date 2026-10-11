---
date: 2026-10-11
tags: [brand, design, typography, accessibility]
status: resolved
post-candidate: yes
evidence: [../7-branding/identity/README.md]
---
## Challenge
Choose the typography: the fonts every doc, page and product built by Ouroboric will share. The theme
is Nordic. The fonts had to stand out and be remembered, without going over the top or becoming tiring
after a few months.

## Context
The palette was already decided: Midnight with International Orange. Every font had to be free under
the SIL Open Font License. Few open fonts are actually Nordic-made, so the search was for Nordic
character rather than Nordic origin.

## Options
Five rounds on an interactive page, with dark and light previews:
1. Six pairings in the same calm, modern style. All looked alike; Nordic Press (Schibsted Grotesk,
   made for a Norwegian media group) became the baseline.
2. Five Nordic directions: Runecarver (Chakra Petch), Saga (Cinzel), Insular (Uncial Antiqua),
   Scandi Modern (Jost) and Nordic Noir (Barlow Condensed).
3. A ranking against four criteria (reads Nordic, memorable, restrained, durable), and a view of
   the real places people meet the brand: the GitHub profile, a chat link preview, a docs page, a
   journal entry, a slide cover and a terminal.
4. An explanation of font roles, and a five-second recall test.
5. A picker per role, with more faces of strong character (Tektur, Jacquard 24, Grenze Gotisch,
   New Rocker, Fjalla One) and Elder Futhark runes as a drop cap.

## Decision
A mix per role: Cinzel for the wordmark and drop caps, Fjalla One for display titles, Literata for
headings and body text, Inter for the interface, JetBrains Mono for code, and runes as ornament.

## Result
The typography section and type tokens in `7-branding/identity/`: families, weights, a type scale and
seven rules. Still open: the drop cap style, the final logo artwork, the dark-mode logo contour and
the favicon.

## Lessons
- Thinking in roles made the decision easier. The face you read all day must be quiet. The face people
  see rarely (the wordmark, a title, one initial per article) can be bold without wearing out.
- The chosen system turned out to be a newspaper: masthead, condensed headlines, a reading serif and
  drop caps. That matched the founder's memory of what makes a page memorable.
- Check that a font has bold and italic before choosing it for body text. Fjord One was picked first
  and has a single style; browsers would have faked bold and italic all over the docs.
- Check where a style comes from. Uncial lettering, first offered as "Viking-age", is Irish and
  Anglo-Saxon and reads as Celtic. The label was wrong and was corrected.
- GitHub, chat apps and terminals render text in their own fonts. Outside our own pages, recognition
  comes from images of the wordmark, the colour and the name.
