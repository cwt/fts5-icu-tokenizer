---
type: lessons_learned
title: "Investigated and ruled out (not bugs)"
description: "Concerns checked during audits and confirmed not to be issues."
status: stable
sources:
  - src/fts5_icu.zig
  - src/tokenizer.zig
verified: human-reviewed
tags: [bugs, audit, false-positive]
timestamp: 2026-09-12T19:06:49Z
---

# Investigated and ruled out (not bugs)

Checked during the audits and confirmed **not** to be issues, so excluded
from the [bug tracker](index.md).

| Concern | Result |
|---------|--------|
| Entrypoint naming mismatch (`libfts5_icu_ja` vs `sqlite3_ftsicu_ja_init`) | **Not a bug.** Verified: `.load ./zig-out/lib/libfts5_icu_ja` succeeds; SQLite resolves the `ftsicu_ja` stem. Forcing the "expected" `sqlite3_fts5_icu_ja_init` fails (symbol not found), confirming the real entrypoints are correct. |
| Duplicate `sqlite3_api` symbol (declared in `fts5_icu.zig` and emitted by translate-c from `SQLITE_EXTENSION_INIT1`) | **Not a bug.** `nm` shows a single `B _sqlite3_api` definition; translate-c did not emit a conflicting global. |
| `api.iVersion < 3` check too strict | **Not a bug.** `sqlite3.h` comments state v2 APIs are available only if `iVersion >= 3` (currently always 3). |
| Memory leaks in `tokenizeText` | **Not a bug.** All `heap_*` buffers and `realloc` results are freed via `defer`; `dynBreak`/`dynTrans`/`ubrk_clone` results are all closed. Allocator unit tests pass. |
| `fts5_api` struct layout / field types | **Correct.** Matches `sqlite3.h` exactly, including `xFindTokenizer_v2` (`fts5_tokenizer_v2 **`) and `xFindTokenizer` (`fts5_tokenizer *`). |
| Malformed UTF-8 / emoji handling | **Safe.** No OOB or crash; unit tests `tokenizeText malformed UTF-8 and emoji safety` pass. |
