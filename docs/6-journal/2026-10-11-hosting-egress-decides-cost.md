---
date: 2026-10-11
tags: [infra, cost, security]
status: open
post-candidate: yes
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/5-research/research-hosting.md, https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#93-infrastructure-target]
---
## Challenge

A Postgres server seemed expensive for a product with one user at first. What is cost-friendly?

## Context

In development everything runs in containers for free; the question is hosting for real users.

## Options

Researched databases, object storage and compute free tiers. Three best-value setups:

- small VPS + Go + SQLite (Litestream backups) + Cloudflare R2: about $8.50/month for one
  photographer;
- Cloud Run + Neon + R2: about $1.50/month, if the API never passes photo bytes through;
- VPS + Backblaze B2.

## Decision

The operator chose Vercel (the product isn't commercial yet, and moving later is acceptable). That
led to: Neon Postgres (no persistent disk for SQLite on Vercel), R2 for photos, thumbnails and zips
built in the browser, and photo bytes never passing through Vercel.

## Result

Pending: deployment is outside v0.

## Lessons

- For a photo product the database is not the cost: **egress** is. One full-gallery download costs
  about $1–2 on classic S3 pricing, every time, and $0 on R2.
- An assistant correction worth keeping: "Postgres is needed for concurrent uploads" was overstated;
  uploads and zips go straight to storage, so the database barely works.
- Preview deployments can bypass every approval point: if previews share production secrets, an
  unreviewed agent branch's migration runs on the production database. Previews get their own
  database branch and bucket.
