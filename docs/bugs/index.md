---
type: index
title: "Bug Tracker — fts5-icu-tokenizer"
description: "One file per bug (#1–#25, all fixed), plus ruled-out concerns, verification, and notes."
status: stable
sources:
  - docs/bugs/
verified: human-reviewed
tags: [bugs, tracker, index, issues]
timestamp: 2026-09-12T19:06:49Z
---

# Bugs — fts5-icu-tokenizer

Source-level audit findings for the FTS5 ICU tokenizer (Zig 0.16.0), filed
across three passes. Every entry is fixed and committed separately, each
with a dedicated regression test (`zig build test`).

- [Ruled out (not bugs)](ruled-out.md)
- [Verification history](verification.md)
- [Minor notes (style/hardening, unnumbered)](minor-notes.md)

## Severity legend

- **HIGH** — correctness/thread-safety defect that can corrupt results or
  crash under realistic conditions.
- **MEDIUM** — correctness defect that silently loses data or produces
  wrong output in non-exotic inputs.
- **LOW** — edge-case correctness issue or dead code / duplication with no
  runtime impact.

## Status by pass

| Pass | Bugs | Status |
|------|------|--------|
| First audit | #1–#7 | All FIXED |
| Second audit (2026) | #8–#13 | All FIXED |
| Second pass, probe-driven (ICU 78 + 67.1.0) | #14–#18 | All FIXED |
| Third pass, probe-driven (ICU 78) | #19–#25 | All FIXED |

| Severity | Count |
|---|---:|
| HIGH | 4 |
| MEDIUM | 5 |
| LOW | 16 |
| **Total** | **25** |

## All Bugs

| # | Title | Severity | Status |
|---|---|---|---|
| [1](001.md) | Transliterator shared across threads | HIGH | Fixed |
| [2](002.md) | Silent token drop on transliteration buffer overflow | MEDIUM | Fixed |
| [3](003.md) | transliterateString errors instead of growing on overflow | MEDIUM | Fixed |
| [4](004.md) | Edge-case UTF-16 truncation of the final character | LOW | Fixed |
| [5](005.md) | Dead code: getSuffixForLocale / LocaleInfo.suffix | LOW | Fixed |
| [6](006.md) | Duplicated init paths, entrypoints, resolver fallbacks | LOW | Fixed |
| [7](007.md) | utf8ToUtf16Alloc reinvented UTF-8 to UTF-16 via ICU | LOW | Fixed |
| [8](008.md) | Double-free in transliterateString on OOM during growth | MEDIUM | Fixed |
| [9](009.md) | Tokenizer name passed as locale override | MEDIUM | Fixed |
| [10](010.md) | u_strToUTF8 buffer one byte too small (heap overflow) | LOW | Fixed |
| [11](011.md) | Dead resolver: icu.ubrk_clone never called | LOW | Fixed |
| [12](012.md) | Dead code: u_strFromUTF8 resolver and icu_funcs entry | LOW | Fixed |
| [13](013.md) | All 35 entrypoints compiled into every locale library | LOW | Fixed |
| [14](014.md) | Cyrillic-Latin collapses distinct letters; й maps to i | HIGH | Fixed |
| [15](015.md) | Whole-string proportional position map skews offsets | HIGH | Fixed |
| [16](016.md) | Invalid locale silently accepted via root fallback | LOW | Fixed |
| [17](017.md) | ICU < 69 fallback ignored the per-call override locale | LOW | Fixed |
| [18](018.md) | Arabic/Hebrew tokens retain non-ASCII modifier letters | LOW | Fixed |
| [19](019.md) | NFKD ligature expansion corrupts the token stream | HIGH | Fixed |
| [20](020.md) | Query-time override_locale bypassed locale validation | MEDIUM | Fixed |
| [21](021.md) | getLocaleInfo matching case-sensitive and unanchored | LOW | Fixed |
| [22](022.md) | Pre-ICU-69 builds impossible although the fallback exists | LOW | Fixed |
| [23](023.md) | Dead build_options import in tokenizer.zig | LOW | Fixed |
| [24](024.md) | build.zig duplicate artifacts with -Dlocale | LOW | Fixed |
| [25](025.md) | Unit tests ran under ReleaseFast | LOW | Fixed |
