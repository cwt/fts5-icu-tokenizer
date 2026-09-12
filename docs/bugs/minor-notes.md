---
type: lessons_learned
title: "Minor notes (style/hardening, unnumbered)"
description: "Third-pass observations that did not warrant numbered bug entries."
status: stable
sources:
  - src/tokenizer.zig
  - scripts/test_all.sh
verified: human-reviewed
tags: [bugs, style, hardening]
timestamp: 2026-09-12T19:06:49Z
---

# Minor notes (style/hardening, unnumbered)

Third-pass observations, kept alongside the [bug tracker](index.md) but
not numbered as bugs.

- Rule-string substring sniffing is duplicated and fragile:
  `"Russian-Latin/BGN"` probed 3× (`transliterateString` incl. its retry
  branch, plus `tokenizeText`) and Arabic/Hebrew probed 2×. Should be
  boolean flags on `LocaleInfo` computed once, instead of re-scanning rule
  text per call.
- `transliterateString` returns `allocator.dupe(u8, …)` of an internal
  buffer — one avoidable allocation+copy per call; allocate the final
  buffer directly.
- `scripts/test_all.sh` pipes sqlite3 through `sed`, so `$?` belongs to
  `sed`; that test can never fail. No `tests/*.sql` sets `.bail on` (works
  on modern CLIs which exit non-zero on SQL errors, fragile on older ones).
- Verified sound during this pass (no findings): all stack/heap SBO
  switching and grow-on-overflow retry paths (bug #8 pattern replicated
  correctly; no leak/UAF/double-free found under the testing allocator);
  byte-offset-map completeness for valid and malformed UTF-8; position-map
  monotonicity for well-formed inputs; entrypoint export filtering
  ([Bug 13](013.md)); `fts5_api` struct layout; `jp`/`cn`/`kr`
  alias resolution (ICU canonicalizes them); `create`/`destroy` errdefer
  ordering.
