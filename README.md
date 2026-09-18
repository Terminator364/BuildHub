# BuildHub

BuildHub is a **generic, public build-orchestration and recovery engine** designed to provide reproducible builds, explicit evidence, robust recovery, and safe publication on constrained Windows PCs and GitHub Actions.

## Scope

This repository contains only generic BuildHub infrastructure.

It must **not** contain:
- private product source code (including PhoneMouse, P2PCR95, ChatGPT-PC, or other private products);
- secrets, tokens, signing keys, credentials, personal data, or private build payloads;
- product-specific business logic.

## Design goals

- Public GitHub Actions as a zero-cost CI laboratory where supported.
- Local Windows operation remains autonomous: GitHub is an accelerator, not a single point of failure.
- Cache-first / offline-friendly execution.
- One heavy build at a time by default on constrained machines.
- Bounded workers; no unbounded process or memory fan-out.
- Idempotent operations and resumable recovery.
- Atomic publication: artifacts are publishable only after build, verification, hash, and readback all pass.
- Human- and machine-readable heartbeat, receipts, and recovery state.

## Evidence rule

A job is **not COMMITTED** merely because a command returned success. COMMITTED requires verified output identity, SHA-256, and post-write/readback evidence.

## Project memory

Known historical failure mechanisms are converted into permanent regression tests and recorded in `.project-memory/ERROR_LEDGER.jsonl`.

## Status

Phase 1 — public BuildHub initialization.
