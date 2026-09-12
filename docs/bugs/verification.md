---
type: attested_computation
title: "Verification history"
description: "Build, test, and SQLite verification runs recorded per audit pass."
status: stable
sources:
  - build.zig
verified: human-reviewed
tags: [bugs, verification, testing]
timestamp: 2026-09-12T19:06:49Z
---

# Verification history

Recorded per audit pass for the [bug tracker](index.md). Re-run
`zig build`, `zig build test`, and `scripts/test_all.sh` after any change
to these areas.

## First pass (bugs #1–#7)

- `zig build` — passes.
- `zig build test` — passes (**15/15** unit tests; each fix added a
  dedicated regression/behavior test).
- `.load ./zig-out/lib/libfts5_icu` and `libfts5_icu_ja` — succeed against
  Homebrew SQLite 3.53.4; universal, per-locale, and `_legacy` entry points
  all tokenize correctly.
- `nm` inspection of `libfts5_icu.dylib` — single `sqlite3_api` definition,
  and exactly **35** `sqlite3_ftsicu*` entry-point symbols, identical to the
  hand-written set before the comptime refactor of [Bug 6](006.md).

## Second pass (bugs #8–#13)

- `zig build test` — 22/22 passing; full `zig build` passes.
- Bug #10 diagnosis was corrected before the fix (see [010.md](010.md)):
  the preflight length excludes the NUL, so the fix grows the buffer rather
  than shrinking the capacity.

## Probe-driven passes (bugs #14–#25)

- Empirical probes against Homebrew ICU 78 (macOS) and an AlmaLinux 9
  container (ICU 67.1.0).
- `zig build test` — 30/30 on ICU 78 (29/30 on ICU 67.1.0 — one
  pre-existing skip, the bug #11 clone-path test requiring ICU ≥ 69), plus
  the full `zig build` and the v1/v2 SQLite test suites.
- `zig build test` runs the suite (34 tests) in Debug with safety checks
  enabled (see [Bug 25](025.md)).
