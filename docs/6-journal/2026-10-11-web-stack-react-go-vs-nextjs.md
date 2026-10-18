---
date: 2026-10-11
tags: [stack, web, security, benchmark]
status: open
post-candidate: yes
evidence: [https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/5-research/research-web-stack.md, https://github.com/ouroboric-dev/yggdrasil/blob/main/docs/2-engineering/specs/2026-10-11-yggdrasil-v0-spec.md#92-stack]
---
## Challenge

Which stack should factory-built web SaaS use? Next.js is popular, and the operator wanted something
modern that agent-driven development commonly uses.

## Context

First we cleared up a misunderstanding: the stack question was about the *products*, not the
factory. Then came research on what AI app builders generate, how well agents know each stack, and
security history.

## Options

Next.js full-stack; Next.js + Go API; React + Vite + Go API; TanStack Start; SvelteKit; Rails or
Laravel; Supabase as the back end.

## Decision

React + Vite + TypeScript + Tailwind + shadcn/ui + TanStack, with a Go API. Almost every AI builder
generates the React + TS + Tailwind + shadcn layer, so agents know it well; this option drops the
server-rendering layer with the worst recent security record and plays to Go. Next.js full-stack
becomes a comparison realm on the same brief later.

## Result

Pending: the Next.js vs React + Go benchmark, which turns "which stack does the factory build better
with?" into a measured result instead of an opinion.

## Lessons

For an autonomous factory, a framework's security history is a scaling factor: a pinned vulnerable
version is copied into every product. Next.js's middleware bypass (CVE-2025-29927) would have let one
curl command skip every middleware-based password check. One advisory means N emergency rebuilds,
which is why version bumps roll to one canary product first.
