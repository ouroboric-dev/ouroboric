---
date: 2026-10-11
tags: [product, benchmark, security]
status: open
post-candidate: yes
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/1-product/design/2026-10-11-yggdrasil-v0-design.md#4-the-demonstration-product-client-gallery-lite]
---
## Challenge
Pick the first product the factory builds and is benchmarked on.

## Context
The first proposal was a team task tracker. The operator chose something closer to a real product:
a Pixieset Client Gallery–style SaaS.

## Options
Task tracker; client gallery lite; client gallery with watermarks or payments; a smaller cut.

## Decision
Client gallery lite: photographer uploads and galleries with password and PIN, client viewing,
favourites and downloads, and a dashboard of favourites and download activity.

## Result
Pending.

## Lessons
A realistic product is a better benchmark because it carries real-world traps agents often miss.
For this one they became checks and hidden tests:
- guessable gallery links (`/g/42`) let anyone browse every client's photos;
- a public storage bucket makes private photos indexable by search engines;
- GPS EXIF data in photos can reveal a client's home;
- "decompression bomb" images exhaust memory;
- an unthrottled 4-digit PIN falls in minutes.
