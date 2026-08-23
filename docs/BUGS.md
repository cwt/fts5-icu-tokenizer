# Known Bugs & Code-Quality Findings

This document records the results of a source-level audit of the FTS5 ICU
tokenizer (Zig 0.16.0). Each entry lists the severity, the exact location,
the root cause, the impact, and a suggested fix.

Severity legend:

- **HIGH** — correctness/thread-safety defect that can corrupt results or
  crash under realistic conditions.
- **MEDIUM** — correctness defect that silently loses data or produces wrong
  output in non-exotic inputs.
- **LOW** — edge-case correctness issue or dead code / duplication with no
  runtime impact.

---

## Fix status (all 7 resolved)

Every finding below has been fixed and committed separately. Each fix ships
with a dedicated Zig unit test (see `zig build test`).

| Bug | Severity | Status | Fix commit | Zig 0.16 built-in used |
|-----|----------|--------|-----------|------------------------|
| #1 | HIGH | FIXED | 8925a336 | ICU `utrans_clone` (resolver added) |
| #2 | MEDIUM | FIXED | 2e4e44a7 | grow on `U_BUFFER_OVERFLOW_ERROR` |
| #3 | MEDIUM | FIXED | e5d548a2 | grow on `U_BUFFER_OVERFLOW_ERROR` |
| #4 | LOW | FIXED | d14c914a | `std.unicode.utf8ToUtf16Le` |
| #5 | LOW | FIXED | 34113613 | — (dead code removed) |
| #6 | LOW/style | FIXED | c9ac710e | `comptime` code generation |
| #7 | LOW | FIXED | d48e3e86 | `std.unicode.utf8ToUtf16LeAllocZ` |

---

## 1. [HIGH] Transliterator is shared across threads (incomplete thread-safety fix) [FIXED: 8925a336]

**File:** `src/tokenizer.zig`
**Lines:** 210-211 (shared handle), 246 (break iterator cloned), 303 (transliterator used)

### Description

`tokenizeText` clones only the break iterator for per-call thread safety, but
reuses the **single shared** transliterator owned by the `IcuTokenizer`:

```zig
var baseBreakIterator = tokenizer.pBreakIterator.?;   // line 210
var pTransliterator    = tokenizer.pTransliterator.?; // line 211  <-- shared!
...
const pBreakIterator = icu.ubrk_clone(baseBreakIterator, &clone_status); // line 246 (cloned)
...
icu.utrans_transUChars(pTransliterator, transBuf.ptr, &outLen, @intCast(transBuf.len), 0, &limit, &status); // line 303 (shared)
```

`IcuTokenizer.create` (`src/tokenizer.zig:55`) opens one `UTransliterator` and
stores it in `pTransliterator`. That same handle is then passed to
`utrans_transUChars` from every `tokenizeText` call. ICU's `UTransliterator`
(and the C++ `Transliterator` it wraps) is **not thread-safe** — concurrent
`utrans_transUChars` calls on one object are a data race. SQLite's own
reference ICU tokenizer mitigates this by opening a *fresh* transliterator per
tokenization.

**Zig 0.16 built-in alternative:** none — this is an ICU threading contract,
not a Zig concern. The correct *built-in primitive* is ICU's `utrans_clone`
(verified present in `unicode/utrans.h` and the translate-c output), cloned
per `tokenizeText` call (add a `utrans_clone` resolver to `src/c_icu.zig`
mirroring the other `ubrk_*`/`utrans_*` resolvers, and close it in the same
`defer` as the break iterator).

The commit `b603813 "fix: resolve thread concurrency race … Clone UBreakIterator …
for multi-threaded safety"` fixed only the break iterator, leaving the
transliterator shared. The extension therefore still exhibits a latent
concurrency bug whenever a single tokenizer object is used from more than one
thread/connection simultaneously (the `concurrent multi-threaded tokenizeText`
unit test passes only by luck — thread-safety races are heisenbugs and do not
reliably fail under test).

### Impact

- Intermittent token corruption or crashes under concurrent indexing/querying
  with a shared tokenizer. Silent and hard to reproduce.

### Suggested fix

Clone (or re-open) the transliterator per `tokenizeText` call, mirroring the
existing break-iterator clone, and close it in the same `defer` block:

```zig
var trans_status: c.UErrorCode = c.U_ZERO_ERROR;
const pTransliterator = icu.utrans_clone(tokenizer.pTransliterator.?, &trans_status);
if (c.U_FAILURE(trans_status) or pTransliterator == null) return c.SQLITE_ERROR;
defer icu.utrans_close(pTransliterator);
```

(If `utrans_clone` is unavailable in the linked ICU build, open a fresh
`utrans_openU` from the same rules string instead.) The same applies to the
`override_locale` path, which currently also uses a shared/default
transliterator across threads.

---

## 2. [MEDIUM] Silent token drop on transliteration buffer overflow

**File:** `src/tokenizer.zig`
**Lines:** 284-291 (size guess), 303-305 (overflow → skip token)

### Description

`transBuf` is sized with a fixed heuristic before translation and is never
grown to the *actual* expansion:

```zig
const reqBufSize = nSrc * 6 + 2048;                 // line 284
if (transBuf.len < reqBufSize) { ... realloc ... }  // lines 285-291
...
icu.utrans_transUChars(pTransliterator, transBuf.ptr, &outLen, @intCast(transBuf.len), 0, &limit, &status); // line 303
if (c.U_FAILURE(status)) {                           // line 304
    token_start = token_end;
    continue;                                        // <-- token silently dropped
}
```

If a token's transliteration expands beyond `nSrc*6 + 2048` UTF-16 units
(e.g. long combining-mark sequences, or rules that expand a code point into
many characters), `utrans_transUChars` returns `U_BUFFER_OVERFLOW_ERROR`,
`U_FAILURE` is true, and the token is skipped with `continue` — no error is
returned to SQLite and the word is simply absent from the index.

**Zig 0.16 built-in alternative:** the *final* UTF-16 → UTF-8 decode of each
token could use `std.unicode.utf16LeToUtf8` (verified in 0.16.0 std), but the
actual overflow bug is in the raw `transBuf` intermediate passed straight to
ICU's `utrans_transUChars`, which has no std replacement — the fix is still the
algorithmic grow-on-`U_BUFFER_OVERFLOW_ERROR` above. Note: there is **no** std
SBO type in 0.16.0 (`std.BoundedArray` does not exist), so the custom
stack/heap buffers must stay (or become `std.ArrayList`, forfeiting SBO).

### Impact

- Words that expand significantly under transliteration are missing from
  search results, with no diagnostic. Affects real queries, not just tests.

### Suggested fix

On overflow, grow `transBuf` to the required length and retry, exactly like
the `destBuf` grow logic below (lines ~330-345):

```zig
if (status == c.U_BUFFER_OVERFLOW_ERROR) {
    const need = @as(usize, @intCast(outLen)) + 64;
    if (heap_trans) |ht| {
        heap_trans = try allocator.realloc(ht, need);
        transBuf = heap_trans.?;
    } else {
        heap_trans = try allocator.alloc(c.UChar, need);
        transBuf = heap_trans.?;
    }
    outLen = @intCast(copyLen);
    limit = outLen;
    status = c.U_ZERO_ERROR;
    icu.utrans_transUChars(pTransliterator, transBuf.ptr, &outLen, @intCast(transBuf.len), 0, &limit, &status);
}
if (c.U_FAILURE(status)) { token_start = token_end; continue; }
```

---

## 3. [MEDIUM] `transliterateString` returns error instead of growing on overflow

**File:** `src/tokenizer.zig`
**Lines:** 91 (fixed capacity), 100-101 (overflow → error)

### Description

```zig
const capacity = input_u16.len * 3 + 64;                                  // line 91
...
icu.utrans_transUChars(transliterator, output_u16.ptr, &out_len, @intCast(capacity), 0, &limit, &status); // line 100
if (c.U_FAILURE(status)) {                                                // line 101
    return error.TransliterateFailed;                                     // <-- fails on overflow
}
```

Any input whose transliteration needs more than `3× + 64` UTF-16 units causes
`utrans_transUChars` to overflow the buffer, and the function returns an error
rather than growing the buffer. This is the same class of bug as #2, but on the
standalone `transliterateString` helper used by the `test_transliterator`,
`locale_specific_tests`, and `test_locale_tokenizer` executables (not the FTS5
query path). Expanding rules (e.g. heavy `NFKD` decompositions) would yield
wrong/empty output.

### Impact

- Incorrect output / hard failure for transliterations that expand beyond the
  fixed heuristic. Not on the live FTS5 path, but a real logic bug for any
  caller of the helper.

**Zig 0.16 built-in alternative:** `u_strToUTF8` can be replaced by
`std.unicode.utf16LeToUtf8` / `utf16LeToUtf8Alloc` (verified in 0.16.0 std), but
the overflow itself is in ICU's `utrans_transUChars` output buffer
(`output_u16`), which has no std equivalent — the fix is still the
loop-and-grow on `U_BUFFER_OVERFLOW_ERROR`.

### Suggested fix

Loop-and-grow on `U_BUFFER_OVERFLOW_ERROR`, using `out_len` (the length ICU
reports as needed) to size the next attempt, mirroring the `destBuf` logic in
`tokenizeText`.

---

## 4. [LOW] Edge-case UTF-16 truncation of the final character (hand-rolled conversion reinvents `std.unicode.utf8ToUtf16Le`)

**File:** `src/tokenizer.zig`
**Lines:** ~165-180 (manual UTF-8 → UTF-16 conversion loop)

### Description

`tokenizeText` converts the input to UTF-16 with a hand-rolled loop. It only
uses Zig std for the *decoding* half (`std.unicode.utf8ByteSequenceLength` /
`std.unicode.utf8Decode`) and then manually performs the UTF-16 *encoding*
(surrogate-pair bit math). Zig 0.16.0 already ships a correct, vectorized,
well-tested converter — `std.unicode.utf8ToUtf16Le(utf16le: []u16, utf8: []const u8) error{InvalidUtf8}!usize`
(verified present in the 0.16.0 std lib) — so this loop reinvents existing std
functionality, and the bug lives in the reinvented part. The reverse direction
is also covered: `std.unicode.utf16LeToUtf8` (verified) converts UTF-16 → UTF-8.

The loop sizes `utf16_text_buffer` to `text.len + 1` and drops a 4-byte
(surrogate-pair) code point when only one UChar slot remains:

```zig
if (cp > 0xFFFF) {
    if (utf16_pos + 2 > utf16_text_buffer.len) break;   // drops trailing surrogate pair
    ...
}
```

UTF-16 can be up to 2× the UTF-8 byte length, so `text.len + 1` is usually
enough, but the trailing character is dropped in the rare case where the total
UTF-16 length exactly equals `text.len` **and** the final code point is a
surrogate pair. That can leave `byte_offset_map` / the final token byte range
slightly off for the dropped character.

### Impact

- Extremely rare off-by-one in byte offset mapping for a trailing emoji/surrogate
  pair under a tight buffer. No crash, minimal real-world effect.

### Suggested fix

**Preferred:** replace the hand-rolled loop with `std.unicode.utf8ToUtf16Le`.
This removes the bug class entirely (no manual surrogate math, no truncation
branch) and uses battle-tested std code. Required adjustments:

1. **Buffer size:** `utf8ToUtf16Le` documents *"Assumes there is enough space
   for the output"* — it does **not** return an overflow error, it writes
   unconditionally. Size `utf16_text_buffer` to `2 * text.len + 1`
   (`[]c.UChar` == `[]u16`); UTF-16 is at most 2 units per UTF-8 byte, which
   guarantees a fit.
2. **`byte_offset_map` is not built by std:** build it in a separate, simple
   pass that walks the UTF-8 codepoints (`std.unicode.utf8Decode`) and records
   the UTF-8 start offset at each UTF-16 index (units per codepoint = `1` if
   `cp <= 0xFFFF` else `2`). Size the map to `2 * text.len + 1` as well.
3. **Endianness:** only the `Le` variant exists in 0.16.0. It writes
   little-endian UTF-16, which matches ICU's native-endian `UChar` on the
   supported little-endian targets (x86_64 / ARM64, macOS & Linux).
4. **Tolerance caveat:** `utf8ToUtf16Le` returns `error{InvalidUtf8}` on any
   malformed byte — it does **not** substitute `U+FFFD`. The current loop uses
   `... catch 0xFFFD` and the unit test `tokenizeText malformed UTF-8 and emoji
   safety` expects `SQLITE_OK`. To keep that tolerance, either (a) run a
   pre-validation / substitution pass before `utf8ToUtf16Le`, or (b) if
   tolerance can be dropped, let the error surface as `SQLITE_ERROR`.

**Minimal fix (preserves current behavior exactly):** keep the manual decode
loop but size both `utf16_text_buffer` and `byte_offset_map` to
`2 * text.len + 1` and delete the `if (utf16_pos + 2 > ...) break;` truncation
branch (it becomes unreachable because the buffer is now large enough).

---

## 5. [LOW] Dead code: `getSuffixForLocale` / `LocaleInfo.suffix`

**File:** `src/rules.zig`
**Lines:** 26-35 (field set), 42-43 (`getSuffixForLocale`), 57 (only reader is a unit test)

### Description

`LocaleInfo.suffix` is populated for every locale but is never read by any
production code path — library file names are produced in `build.zig` via
`b.fmt("fts5_icu_{s}", .{locale})`, not from this field. `getSuffixForLocale`
is only ever called from the `rules.zig` unit test (`test "rules mapping"`).

### Impact

- None at runtime; pure maintenance noise.

### Suggested fix

Remove `suffix` from `LocaleInfo`, remove `getSuffixForLocale`, and drop the
corresponding assertion from the unit test.

---

## 6. [LOW/style] Duplication

**Files:** `src/fts5_icu.zig`, `src/c_icu.zig`

### Description

- `initExtensionForLocaleV1` and `initExtensionForLocaleV2` are ~90% identical
  (the only differences are the `iVersion < 3` guard and which
  `xCreateTokenizer(_v2)` is called). They could be merged behind a version
  parameter.
- The 18 `sqlite3_ftsicu*[_legacy]_init` entrypoint functions are mechanical
  repetitions (required by SQLite's per-library entrypoint naming, but very
 verbose). Pairs like `sqlite3_ftsicuja_init` / `sqlite3_ftsicu_ja_init` are
  pure aliases.
- In `src/c_icu.zig`, every resolver ends with `else @field(c, "ubrk_open")`.
  This branch is unreachable: if neither `ubrk_open` nor `ubrk_open_77` exists,
  `@field(c, "ubrk_open")` is a compile-time error, so the `else` can never
  execute.

### Impact

- No runtime effect; increases review surface and the chance of future drift
  between the V1/V2 init paths.

### Suggested fix

- Merge the two `initExtensionForLocale*` functions.
- Optionally reduce the entrypoint boilerplate with a code-generation step, or
  at minimum keep the alias pairs consistent.
- Replace the unreachable `else @field(...)` with a `@compileError` or simply
  drop the branch.

**Zig 0.16 built-in alternative:** the 18 near-identical entrypoints can be
emitted by a `comptime` loop (a Zig language built-in), and the V1/V2 init
functions merged behind a `version` parameter — eliminating the duplication
without a runtime cost.

---

## 7. [LOW] `utf8ToUtf16Alloc` reinvents UTF-8 → UTF-16 via ICU `u_strFromUTF8` (use `std.unicode.utf8ToUtf16LeAllocZ`)

**File:** `src/tokenizer.zig`
**Lines:** ~58-88 (`utf8ToUtf16Alloc`)

### Description

`utf8ToUtf16Alloc` converts a UTF-8 slice into a null-terminated `[:0]c.UChar`
(UTF-16) buffer using a **two-pass manual probe** through ICU's `u_strFromUTF8`:
call once with a zero-length destination to learn the required length, then
`allocSentinel` and call again to fill it. Zig 0.16 std already provides this as
a single call:

```zig
pub fn utf8ToUtf16LeAllocZ(allocator: Allocator, utf8: []const u8) error{ InvalidUtf8, OutOfMemory }![:0]u16
```

`[:0]u16` is the same type as `[:0]c.UChar` (ICU `UChar` is `u16`), so every
caller — `utrans_openU(rules_u16.ptr, -1, ...)` in `IcuTokenizer.create` and in
`transliterateString` — is unchanged. The hand-rolled probe is avoidable code
that also pulls in an extra ICU dependency for something the standard library
does natively. (The symmetric `u_strToUTF8` / `u_strToUTF8WithSub` calls in
`transliterateString` and `tokenizeText` have the same std equivalent,
`std.unicode.utf16LeToUtf8` / `utf16LeToUtf8Alloc` — see bugs #2/#3.)

### Impact

- No correctness defect today, but avoidable complexity and an extra ICU call
  path. Behavior diverges on malformed input: ICU's `u_strFromUTF8` substitutes
  `U+FFFD` for invalid sequences by default, whereas `utf8ToUtf16LeAllocZ`
  returns `error{InvalidUtf8}`. For the rule/locale strings (always valid UTF-8)
  this is moot; for `transliterateString`'s arbitrary input it would turn a
  tolerant substitution into a hard error.

### Suggested fix

Replace the body of `utf8ToUtf16Alloc` with a one-liner (keep the same
signature so all callers are untouched):

```zig
pub fn utf8ToUtf16Alloc(allocator: std.mem.Allocator, text: []const u8) ![:0]c.UChar {
    // std.unicode.utf8ToUtf16LeAllocZ returns [:0]u16, identical to [:0]c.UChar
    return std.unicode.utf8ToUtf16LeAllocZ(allocator, text);
}
```

Endianness note (same as #4): only the `Le` variant exists in 0.16.0; it writes
little-endian UTF-16 which matches ICU's native-endian `UChar` on the supported
little-endian targets (x86_64 / ARM64, macOS & Linux). If tolerance for
malformed input must be preserved, run a pre-validation / substitution pass
(e.g. walk the bytes and replace invalid runs with `U+FFFD`) before calling
`utf8ToUtf16LeAllocZ`.

---

## Post-fix status (all resolved)

| Bug | Hand-rolled / external | Zig 0.16 (or ICU) built-in | Applies to | Status |
|-----|------------------------|----------------------------|-----------|--------|
| #1 | shared `UTransliterator` across threads | ICU `utrans_clone` (verified) — clone per call | the fix | FIXED (8925a336) |
| #2 | token dropped on ICU `transBuf` overflow | none for the ICU buffer; `std.unicode.utf16LeToUtf8` for the final UTF-16→UTF-8 step | partial | FIXED (2e4e44a7) |
| #3 | `transliterateString` errors on ICU overflow | none for the ICU buffer; `std.unicode.utf16LeToUtf8` / `utf16LeToUtf8Alloc` for UTF-16→UTF-8 | partial | FIXED (e5d548a2) |
| #4 | manual UTF-8→UTF-16 encoder | `std.unicode.utf8ToUtf16Le` | yes (preferred fix) | FIXED (d14c914a) |
| #5 | dead code | n/a | — | FIXED (34113613) |
| #6 | 18 duplicated entrypoints / V1+V2 dup | Zig `comptime` loop + version param | yes (refactor) | FIXED (c9ac710e) |
| #7 | ICU `u_strFromUTF8` two-pass probe | `std.unicode.utf8ToUtf16LeAllocZ` | yes (replace) | FIXED (d48e3e86) |

## Zig 0.16 built-in alternatives — summary

For each bug, whether Zig 0.16 (or the linked ICU) provides a built-in that
removes the hand-rolled / external logic:

| Bug | Hand-rolled / external | Zig 0.16 (or ICU) built-in | Applies to |
|-----|------------------------|----------------------------|-----------|
| #1 | shared `UTransliterator` across threads | ICU `utrans_clone` (verified) — clone per call | the fix |
| #2 | token dropped on ICU `transBuf` overflow | none for the ICU buffer; `std.unicode.utf16LeToUtf8` for the final UTF-16→UTF-8 step | partial |
| #3 | `transliterateString` errors on ICU overflow | none for the ICU buffer; `std.unicode.utf16LeToUtf8` / `utf16LeToUtf8Alloc` for UTF-16→UTF-8 | partial |
| #4 | manual UTF-8→UTF-16 encoder | `std.unicode.utf8ToUtf16Le` | yes (preferred fix) |
| #5 | dead code | n/a | — |
| #6 | 18 duplicated entrypoints / V1+V2 dup | Zig `comptime` loop + version param | yes (refactor) |
| #7 | ICU `u_strFromUTF8` two-pass probe | `std.unicode.utf8ToUtf16LeAllocZ` | yes (replace) |

Notes:
- `std.BoundedArray` does **not** exist in 0.16.0, so the custom SBO buffers in
  `tokenizeText` have no std equivalent (use `std.ArrayList` only if dropping
  SBO is acceptable).
- `utf8ToUtf16Le` / `utf16LeToUtf8` write assuming sufficient space (no overflow
  error) — size UTF-16 buffers to `2 * text.len + 1` and UTF-8 buffers to
  `3 * utf16_units + 1`.
- All `*Le` converters are little-endian; they match ICU `UChar` on the
  supported little-endian targets.

---

## Appendix: Investigated and ruled out (not bugs)

These were checked during the audit and confirmed **not** to be issues, so they
are excluded from the bug list above.

| Concern | Result |
|---------|--------|
| Entrypoint naming mismatch (`libfts5_icu_ja` vs `sqlite3_ftsicu_ja_init`) | **Not a bug.** Verified: `.load ./zig-out/lib/libfts5_icu_ja` succeeds; SQLite resolves the `ftsicu_ja` stem. Forcing the "expected" `sqlite3_fts5_icu_ja_init` fails (symbol not found), confirming the real entrypoints are correct. |
| Duplicate `sqlite3_api` symbol (declared in `fts5_icu.zig` and emitted by translate-c from `SQLITE_EXTENSION_INIT1`) | **Not a bug.** `nm` shows a single `B _sqlite3_api` definition; translate-c did not emit a conflicting global. |
| `api.iVersion < 3` check too strict | **Not a bug.** `sqlite3.h` comments state v2 APIs are available only if `iVersion >= 3` (currently always 3). |
| Memory leaks in `tokenizeText` | **Not a bug.** All `heap_*` buffers and `realloc` results are freed via `defer`; `dynBreak`/`dynTrans`/`ubrk_clone` results are all closed. Allocator unit tests pass. |
| `fts5_api` struct layout / field types | **Correct.** Matches `sqlite3.h` exactly, including `xFindTokenizer_v2` (`fts5_tokenizer_v2 **`) and `xFindTokenizer` (`fts5_tokenizer *`). |
| Malformed UTF-8 / emoji handling | **Safe.** No OOB or crash; unit tests `tokenizeText malformed UTF-8 and emoji safety` pass. |

---

## Verification

- `zig build` — passes.
- `zig build test` — passes (**15/15** unit tests; each bug fix added a
  dedicated regression/behavior test).
- `.load ./zig-out/lib/libfts5_icu` and `libfts5_icu_ja` — succeed against
  Homebrew SQLite 3.53.4; the universal, per-locale, and `_legacy` entry
  points all tokenize correctly.
- `nm` inspection of `libfts5_icu.dylib` — single `sqlite3_api` definition,
  and exactly **35** `sqlite3_ftsicu*` entry-point symbols, identical to the
  hand-written set that existed before the comptime refactor of bug #6.

> All seven findings documented above are now resolved and committed
> separately (commits 8925a336, 2e4e44a7, e5d548a2, d14c914a, 34113613,
> c9ac710e, d48e3e86 on the `zig.git` bookmark).

---

## New Findings (2026 audit)

These bugs were discovered during a subsequent source-level audit. They have all
been **fixed and committed separately** (each with a dedicated Zig unit test that
guards the regression), verified with `zig build test` (22/22 passing) and the
full `zig build`.

| Bug | Severity | Status | Fix commit |
|-----|----------|--------|-----------
| #8 | MEDIUM | FIXED | 52d1e944 |
| #9 | MEDIUM | FIXED | 23310bf6 |
| #10 | LOW | FIXED | 8126fd33 |
| #11 | LOW | FIXED | 4e980f79 |
| #12 | LOW | FIXED | d22f41c6 |
| #13 | LOW | FIXED | 27e7cbf4 |

> **Note on #10:** its diagnosis in the original audit draft was wrong — it
> claimed the `u_strToUTF8` preflight length included the NUL and proposed
> `destCapacity = utf8_len` as the fix. An empirical probe proved the preflight
> returns the content length *without* the NUL, so the real bug is a 1-byte heap
> overflow (NUL written past the `utf8_len`-byte buffer). The correct fix is
> `allocate utf8_len + 1 / destCapacity = utf8_len + 1`. The diagnosis and fix
> were corrected in commit 88a31797 before the code fix.

### Verification highlights

- **#8** (double free on OOM): fixed by allocating the replacement buffer into a
  temporary before freeing the old one.
- **#9** (tokenizer name treated as locale): `icuCreate` now ignores `azArg[0]`
  (the FTS5 tokenizer name) and reads an optional locale override from
  `azArg[1]`, matching SQLite's own `fts5_icu.c` (`nArg > 1 -> azArg[1]`).
- **#10** (1-byte heap overflow): fixed; the testing allocator's canary check
  caught the original overflow during development.
- **#11** (dead `ubrk_clone` resolver): there was in fact *no* such resolver in
  the current code; `tokenizeText` referenced `c.ubrk_clone` directly. Added a
  resolver for consistency with every other ICU call and switched to it.
- **#12** (dead `u_strFromUTF8`): resolver and `icu_funcs` entry removed.
- **#13** (all 35 entrypoints exported in every library): the comptime `@export`
  loop is now filtered by `build_options.locale`. Verified against the original C
  version (`main.git`), where each `.so` is compiled once per locale and the
  entry-point name is pasted from the locale suffix — so the universal build
  exports ONLY the non-locale-specific entry points. The three universal-named
  entry points carry `locale = ""` (always non-locale-specific), so `nm` confirms
  the universal lib exports exactly 3 and each locale lib (ja, zh, …) exactly 4.

---

## 8. [MEDIUM] Double-free in `transliterateString` when OOM hits during buffer growth

**File:** `src/tokenizer.zig`
**Lines:** 93–108 (`output_u16` allocation, defer, and overflow retry)

### Description

When ICU `utrans_transUChars` returns `U_BUFFER_OVERFLOW_ERROR`, the function
frees the old buffer and reallocates a larger one:

```zig
var output_u16 = try allocator.alloc(c.UChar, capacity);   // line 93
defer allocator.free(output_u16);                           // line 94
...
icu.utrans_transUChars(transliterator, output_u16.ptr, &out_len, @intCast(capacity), 0, &limit, &status);
if (status == c.U_BUFFER_OVERFLOW_ERROR) {
    const need: usize = @as(usize, @intCast(out_len)) + 64;
    allocator.free(output_u16);                             // line ~103  ← frees first alloc
    output_u16 = try allocator.alloc(c.UChar, need);        // line ~104  ← if this fails…
    ...
}
```

In Zig, `defer` captures variables by reference — they are evaluated at scope
exit, not at the point of declaration. So if line 104 fails (e.g.
`error.OutOfMemory`), `output_u16` still holds the pointer freed at line 103.
The function returns the error, and the `defer` at line 94 fires:
`allocator.free(output_u16)` is called on the **already-freed** pointer →
**double free, heap corruption** (CWE-415).

This is a classical error-handling gap in a free-then-retry pattern. It only
triggers when transliteration expansion exceeds `3× + 64` UTF-16 units **and**
the system is under memory pressure, so it is rare but real.

### Impact

- Heap corruption on an OOM path. Unlikely in normal operation, but once
  triggered the allocator state is undefined and any subsequent allocation
  or free can crash or silently corrupt data.

### Suggested fix

Allocate the replacement buffer into a temporary first, then swap:

```zig
if (status == c.U_BUFFER_OVERFLOW_ERROR) {
    const need: usize = @as(usize, @intCast(out_len)) + 64;
    const new_u16 = try allocator.alloc(c.UChar, need);  // allocate first
    allocator.free(output_u16);                            // then free the old one
    output_u16 = new_u16;                                  // point to new buffer
    @memcpy(output_u16[0..input_u16.len], input_u16);
    out_len = @intCast(input_u16.len);
    limit = out_len;
    status = c.U_ZERO_ERROR;
    icu.utrans_transUChars(transliterator, output_u16.ptr, &out_len, @intCast(need), 0, &limit, &status);
}
```

This way, if `alloc` fails, `output_u16` still points to the original (valid)
buffer and the `defer` at line 94 correctly frees it.

---

## 9. [MEDIUM] Tokenizer name passed as locale override — all locale-specific libraries use wrong word-breaking & transliteration rules

**File:** `src/fts5_icu.zig`
**Lines:** 63–68 (`icuCreate`)

### Description

SQLite FTS5's `xCreate` callback receives `azArg[0]` = the **tokenizer name**
(e.g. `"icu_ja"`), not a locale identifier. The callback unconditionally treats
`azArg[0]` as a locale override:

```zig
fn icuCreate(
    pCtx: ?*anyopaque,
    azArg: [*c][*c]const u8,
    nArg: c_int,
    ppOut: [*c]?*Fts5Tokenizer,
) callconv(.c) c_int {
    _ = pCtx;
    var locale: []const u8 = build_options.locale;                // e.g. "ja"
    if (nArg > 0 and azArg != null and azArg[0] != null and azArg[0][0] != 0) {
        locale = std.mem.span(azArg[0]);                          // "icu_ja" OVERWRITES "ja"!
    }
    ...
}
```

This means for the ja-specific library (`build_options.locale = "ja"`), when a
user writes `tokenize='icu_ja'` (the only possible value since that's the
registered name), the code sets `locale = "icu_ja"`:

- `getRulesForLocale("icu_ja")` → prefix `"ic"` matches no locale → falls back
  to `ICU_RULE_DEFAULT` (missing the `Katakana-Hiragana` rule that the `ICU_RULE_JA`
  rule set provides).
- `ubrk_open(UBRK_WORD, "icu_ja", ...)` receives an invalid ICU locale ID →
  ICU likely falls back silently to the root/default locale → word boundaries
  use Unicode default rules, not Japanese-specific boundaries. CJK text is
  split into individual ideographs instead of proper Japanese words.

**The tests don't catch this** because FTS5 phrase queries like
`MATCH '日本語'` still succeed with character-by-character tokenization — each
character is a separate token, and the query becomes a positional phrase match
over three consecutive tokens (`日` `本` `語`). The tests validate the query
*results*, not the tokenization *method*.

The same defect affects all locale-specific libraries (`icu_ar`, `icu_zh`,
`icu_th`, `icu_ko`, `icu_ru`, `icu_he`, `icu_el`).

### Impact

- **Wrong word boundaries** for all locale-specific libraries — CJK text is
  broken into individual characters, Arabic/Hebrew/Thai use default rather than
  locale-tuned dictionary-based break iterators.
- **Wrong transliteration** — locale-specific transform chains (e.g.
  Katakana→Hiragana for Japanese, Arabic→Latin for Arabic) are never applied;
  only the universal rule set runs.
- Search quality is silently degraded for all locale-specific deployments.

### Suggested fix

The baked-in `build_options.locale` is ALREADY the correct locale. `azArg[0]`
is the tokenizer name and should not be treated as a locale. The correct
override mechanism reads from the **second** tokenizer argument:

```zig
var locale: []const u8 = build_options.locale;
// Override only if a SECOND argument is supplied (e.g. tokenize='icu ja')
if (nArg > 1 and azArg != null and azArg[1] != null and azArg[1][0] != 0) {
    locale = std.mem.span(azArg[1]);
}
```

Additionally, the existing `override_locale` mechanism in `icuTokenizeV2`
(which receives `pLocale`/`nLocale` from the V2 API) already supports per-query
locale overrides and does not have this confusion.

---

## 10. [LOW] `u_strToUTF8` buffer one byte too small — 1-byte heap overflow (`transliterateString`)

**File:** `src/tokenizer.zig`
**Lines:** ~137–142 (`u_strToUTF8` call after probe)

### Description

```zig
var utf8_len: i32 = 0;
status = c.U_ZERO_ERROR;
_ = icu.u_strToUTF8(null, 0, &utf8_len, output_u16.ptr, limit, &status);  // probe
...
const utf8_output = try allocator.alloc(u8, @intCast(utf8_len));            // utf8_len EXCLUDES NUL
errdefer allocator.free(utf8_output);

_ = icu.u_strToUTF8(utf8_output.ptr, utf8_len + 1, null, ...);  // ← destCapacity = utf8_len + 1
```

ICU's `u_strToUTF8` preflight (null destination, `destCapacity = 0`) returns
`utf8_len` = the **number of UTF-8 content bytes, NOT counting the NUL
terminator**. This is per `unicode/ustring.h`: *"pDestLength … is always set to
the number of output units corresponding to the transformation of all the input
units"*, and *"the result will be zero-terminated if the buffer is large
enough"*. It was **verified empirically**: the preflight for `"abc"` returns `3`
(not `4`) and for two `é` (U+00E9, 2 UTF-8 bytes each) returns `4` (not `5`).

Because `utf8_len` excludes the NUL, the buffer is allocated with `utf8_len`
bytes — **one byte too small** to also hold the terminator. But the real call
passes `destCapacity = utf8_len + 1`, so ICU concludes there is room for
content + NUL (`utf8_len + 1` bytes) and writes the NUL at index `utf8_len`,
**one byte past the end of the `utf8_len`-byte allocation** — a genuine 1-byte
heap buffer overflow on every successful conversion (CWE-787).

### Impact

- **1-byte out-of-bounds write** of the NUL terminator on every
  `transliterateString` call that converts valid input. Silent today (no crash
  under the default testing allocator, which does not detect OOB writes), but
  undefined behavior: it can corrupt the adjacent heap chunk's metadata/next
  pointer and trigger a later crash or memory corruption, especially under a
  debug/safe allocator or ASan.

### Suggested fix

Allocate room for the terminator and report the true capacity. Standard ICU
preflight usage is `destCapacity = length + 1`, which requires a buffer of
`length + 1`:

```zig
const utf8_output = try allocator.alloc(u8, @intCast(utf8_len) + 1);  // +1 for NUL
errdefer allocator.free(utf8_output);

_ = icu.u_strToUTF8(utf8_output.ptr, @intCast(utf8_len) + 1, null, output_u16.ptr, limit, &status);
if (c.U_FAILURE(status)) {
    return error.Utf8ConvertFailed;
}
return utf8_output[0..@intCast(utf8_len)];  // content length, NUL excluded
```

> **Correction:** an earlier draft of this finding claimed the preflight length
> *included* the NUL and that `destCapacity = utf8_len + 1` was merely a
> contract violation, proposing `destCapacity = utf8_len` as the fix. That is
> **wrong** — verified by the probe above. Passing `destCapacity = utf8_len`
> leaves no room for the NUL, so ICU returns `U_BUFFER_OVERFLOW_ERROR` and the
> surrounding code returns `error.Utf8ConvertFailed`, breaking
> `transliterateString`. The buffer must be grown to `utf8_len + 1`; do not
> just reduce the capacity value.
---

## 11. [LOW] Dead resolver: `icu.ubrk_clone` never called

**File:** `src/c_icu.zig`
**Lines:** ~59–66 (`ubrk_clone` resolver)

### Description

The `icu.ubrk_clone` resolver (which checks for versioned and unversioned ICU
symbols at compile time) exists but is never invoked. `tokenizeText` uses
`c.ubrk_clone` directly at line ~249, bypassing the resolver entirely:

```zig
const pBreakIterator = if (build_options.has_ubrk_clone)
    c.ubrk_clone(baseBreakIterator, &clone_status)    // ← uses c.* directly
else ...;
```

The actual versioned-symbol resolution for `ubrk_clone` is handled by the
assembly alias generated in `build.zig` (`icu_aliases.s`), not by this
resolver. Contrast with `icu.utrans_clone` which IS invoked through the
resolver path at line ~268 of `tokenizeText`.

### Impact

- No runtime effect. The resolver is dead code; the linker alias in build.zig
  provides the correct symbol.

### Suggested fix

Either:
- Use `icu.ubrk_clone` in `tokenizeText` instead of `c.ubrk_clone` (preferred,
  for consistency with every other ICU call), or
- Remove the `ubrk_clone` resolver from `c_icu.zig`.

---

## 12. [LOW] Dead code: `u_strFromUTF8` resolver and `icu_funcs` entry

**Files:** `src/c_icu.zig` (~46–53), `build.zig` (~line 7)

### Description

After bug #7 was fixed (replacing the ICU two-pass `u_strFromUTF8` probe in
`utf8ToUtf16Alloc` with `std.unicode.utf8ToUtf16LeAllocZ`), the `u_strFromUTF8`
function is never called anywhere in the codebase. Both its resolver in
`c_icu.zig` and its entry in the `icu_funcs` list in `build.zig` are dead.

Note: `u_strToUTF8` and `u_strToUTF8WithSub` are **still actively used** (in
`transliterateString` and `tokenizeText` respectively) — only `u_strFromUTF8`
is dead.

### Impact

- No runtime effect. Adds a few lines of dead code and an unnecessary assembly
  alias to every build artifact.

### Suggested fix

Remove the `u_strFromUTF8` resolver from `c_icu.zig` and drop `"u_strFromUTF8"`
from the `icu_funcs` array in `build.zig`.

---

## 13. [LOW] All 35 entrypoints compiled into every locale-specific library

**File:** `src/fts5_icu.zig`
**Lines:** entrypoints table and `comptime` export block (~210–290)

### Description

The `entrypoints` comptime table in `fts5_icu.zig` lists all 35 exported
entrypoint symbols (universal + 8 locales × 4 variants each). The `comptime`
block unconditionally emits all of them via `@export`. Since `fts5_icu.zig` is
the root source for every library, each locale-specific `.so` (e.g.
`libfts5_icu_ja.so`) exports ALL entrypoints — including `sqlite3_ftsicuzh_init`,
`sqlite3_ftsicuar_init`, etc. — not just the entrypoints for its target locale.

SQLite only invokes the entrypoint that matches the library's loaded stem name
(e.g. `.load .../libfts5_icu_ja` → `sqlite3_ftsicuja_init`), so the other 34
symbols in a locale binary are unreachable dead exports. The universal
`libfts5_icu.so` had the same problem — it exported all 35 too, including every
locale-specific name, instead of just its 3 non-locale-specific entry points.
That contradicts the original C version (`main.git`), where the universal build
never emits the locale-specific names.

### Impact

- Unnecessary binary bloat (~34 extra exported symbols per library). No
  runtime correctness impact; SQLite ignores the extra entrypoints.

### Suggested fix

Filter the entrypoints table at comptime with `build_options.locale` so each
library only exports its own symbols. The universal library (`locale = ""`)
exports only the 3 non-locale-specific entry points (`sqlite3_ftsicu_init`,
`sqlite3_ftsicu_legacy_init`, `sqlite3_ftsiculegacy_init`); each locale-specific
library exports only its 4 entry points. This matches the original C version
(`main.git`), where the universal build never emits the locale-specific names.

---

## New Findings (2026 audit, second pass)

A second audit pass, driven by an empirical probe harness running against
Homebrew ICU 78 and an AlmaLinux 9 container (ICU 67.1.0), found two HIGH
correctness bugs and three LOW issues. All five are described below with their
verified behavior, implemented and committed with regression tests, verified
with `zig build test` (30/30 on ICU 78; 29/30 on ICU 67.1.0 — one pre-existing
skip, the bug #11 clone-path test, which requires ICU ≥ 69), plus the full
`zig build` and the v1/v2 SQLite test suites.

| Bug | Severity | Status | Fix commit |
|-----|----------|--------|-----------
| #14 | HIGH | FIXED | 05c52e983470 |
| #15 | HIGH | FIXED | 05c52e983470 |
| #16 | LOW | FIXED | 6d623ecfe43e |
| #17 | LOW | FIXED | 05c52e983470 |
| #18 | LOW | FIXED | 6d623ecfe43e |

> **Note:** a stale untracked backup `src/tokenizer.zig.orig` (left over from an
> earlier draft) was deleted during this pass.

---

## 14. [HIGH] Cyrillic-Latin transliteration collapses distinct letters; й maps to 'i'

**File:** `src/rules.zig`
**Lines:** 9–13 (`ICU_RULE_RU`, `ICU_RULE_DEFAULT`)

### Description

`Cyrillic-Latin` maps щ, ш and с to `s`, and ж and з to `z` (its output for
щ/ж/з carries a combining mark that the following `Latin-ASCII` step strips).
The net effect is that **distinct Russian words collapse to identical tokens**:
борщ/борс → `bors`, щи/си → `si`, шар/сар → `sar`, жар/зар → `zar`. On top of
that, ICU's `Russian-Latin/BGN` (the standard's sanctioned replacement) maps й
(U+0439) to `i` — while the published BGN/PCGN romanization maps й to `y` — so
мой and мои collapse to `moi` and русский becomes `russkii`.

Verified with probes on both ICU 78 and ICU 67.1.0 (identical behavior):
борщ→borshch, щи→shchi, шар→shar, сар→sar, жар→zhar, зар→zar, чашка→chashka,
щека→shcheka, я→ya, ю→yu, хлеб→khleb, цвет→tsvet, ещё→yeshche, мой/мои→moi
(collision), русский→russkii, мышь→mysh', ильин→il'in, объём→ob"yem.

### Impact

- Russian full-text search is unreliable: unrelated words (борщ vs борс, жар
  vs зар) share a token, and distinct inflected forms (мой vs мои) become
  indistinguishable.
- Search terms and documents no longer agree on token spelling after a
  software update (behavior change vs the previous Cyrillic-Latin output).

### Suggested fix (implemented)

- Switch `ICU_RULE_RU` and the Cyrillic leg of `ICU_RULE_DEFAULT` to
  `Russian-Latin/BGN` (`NFKD; Russian-Latin/BGN; Latin-ASCII; Lower; NFKC`).
  Plain `Russian-Latin` does not exist as an ID on ICU 67 (`utrans_openU`
  returns U_INVALID_ID); the `/BGN` variant is available on both 67 and 78.
- Pre-map Cyrillic й/Й (U+0439/U+0419) to `y` in the UTF-16 domain before
  transliteration (1:1 units, so the position map stays exact). This runs in
  both `tokenizeText` and `transliterateString`, gated on the rule string
  containing `Russian-Latin/BGN`. Inline transliterator pre-rules are not an
  option: `utrans_openU` parses only registered compound IDs — every rule
  string (e.g. `[\u0439] > y`) fails with U_INVALID_ID, confirmed against the
  ICU 78 sources (`translit.cpp`, `transreg.cpp`).

Rejected alternatives (verified): `Cyrillic-Latin/BGN` and `/UNGEGN` still
emit diacritics (борщ→borŝ); `NFD; remove-marks` still collapses борщ/борс;
per-token transliteration is wrong (UBRK splits はー before transliteration).

---

## 15. [HIGH] Whole-string proportional position map skews offsets and drops tokens

**File:** `src/tokenizer.zig`
**Lines:** ~320–375 (position map), ~400–411 (offset derivation)

### Description

The position map (normalized UTF-16 position → original UTF-16 position) used
whole-string proportional scaling: `pm[i] = min(utf16_pos-1, i * utf16_pos /
norm_len)`. That is only exact when the transliteration is 1:1 in UTF-16 units
(NFKC, Lower, Hiragana-Katakana). Any expansion (ﬁ→fi: 1→2 units, щ→shch:
1→5, ё→ye, BGN s->shch) compresses **every** later position, so every token
after an expansion reports a wrong byte range, and adjacent mapped positions
can collide — `nTokenByte <= 0` then silently drops the token.

Empirically: tokenizing `a ﬁ b` with the default rules yielded `fi` at [1,5)
instead of [2,5), and the `a` token was dropped entirely (its mapped end
position collided with its start).

### Impact

- FTS5 snippet/highlight offsets are wrong for any text containing a
  transliteration expansion before the match.
- Documents silently lose searchable tokens, changing query results.

### Suggested fix (implemented)

Anchor the map at whitespace: every rule chain preserves whitespace 1:1
(probes: NFKD maps NBSP U+00A0, U+2000..U+200A, U+202F, U+205F, U+3000 to
U+0020; ZWSP U+200B, LS U+2028, PS U+2029 and U+1680 do not decompose and are
never anchors). Whitespace positions in the normalized text are matched to
whitespace positions in the original and set exactly; within each
space-delimited segment the map is proportional with round-half-up rounding
(a 1:1 segment stays exact). Verified exact for `a ﬁ b` (a→[0,1), fi→[2,5),
b→[6,7)) and `борщ вкусный` (borshch→[0,8), vkusnyy→[9,23) — the latter with
the BGN rules of bug #14, including the 1→5 щ expansion).

---

## 16. [LOW] Invalid locale silently accepted (fallback warning not treated as error)

**File:** `src/tokenizer.zig`
**Lines:** ~38–41 (`IcuTokenizer.create`), `isValidLocaleLanguage`

### Description

`ubrk_open` returns `U_USING_FALLBACK_WARNING` (−127) for a locale it cannot
resolve (e.g. `"xx_YY"`), and the code checks only `U_FAILURE(status)`, which
does not include warnings. The tokenizer is created successfully with root
rules, and `tokenizeText` then silently produces unexpected tokens.

**Verified (probes on ICU 78 and 67.1.0, identical):** the fallback warning
fires for **every non-empty locale** — `ja`, `ru_RU`, `en_US`, `xx_YY`,
`jp`, `C` all return −127, because word-break data lives in root. Only the
empty string returns status 0. The status code therefore *cannot* distinguish
a typo'd locale from a valid one, and rejecting `U_USING_FALLBACK_WARNING`
outright would break every locale-specific build.

### Impact

- Typos in the locale argument of `CREATE VIRTUAL TABLE` (e.g. `icu_ru_` or
  `icu_enu`) silently fall back to root segmentation instead of failing, so
  the failure mode is a hard-to-debug wrong-result rather than an error.

### Suggested fix (implemented)

Validate the locale **string** at create time (`isValidLocaleLanguage`):
accept the empty locale (universal tokenizer), `"C"`/`"POSIX"` (legitimate
system locales that resolve to root), any language prefix mapped by
`rules.zig getLocaleInfo` (ja/jp, zh/cn, th, ko/kr, ar, ru, he/iw, el/gr —
the aliases are not ICU language codes), or a language present in
`uloc_getAvailable` (scanned via `uloc_countAvailable`, `uloc_getAvailable`).
Anything else fails `IcuTokenizer.create` with `error.IcuInvalidLocale`
(→ `SQLITE_ERROR` from `icuCreate`), covering both the baked
`build_options.locale` and the per-table FTS5 argument. `uloc_getLanguage`
is used to extract the language (so `en_US.UTF-8` → `en` is accepted).
Regression tests: `xx`/`xx_YY`/`xyz` rejected; `jp`/`cn`/`kr`/
`en_US.UTF-8`/`C`/`POSIX` accepted.

---

## 17. [LOW] ICU < 69 break-iterator fallback ignores the per-call override locale

**File:** `src/tokenizer.zig`
**Lines:** ~293–296 (fallback branch of the clone)

### Description

On platforms without `ubrk_clone` (ICU < 69 and non-Darwin), `tokenizeText`
re-opens a break iterator with `tokenizer.locale_slice`, ignoring the
per-call `override_locale`. With an override in effect (e.g. `icu` tokenizer
called with `"ja"`), the transliterator and the *cloned* break iterator
(newer ICU) use the override locale, but the fallback iterator uses the
tokenizer's own locale — inconsistent segmentation per platform.

### Impact

- Locale-override calls segment differently on ICU < 69 vs ≥ 69.

### Suggested fix (implemented)

Use the effective locale (non-empty override wins, else the tokenizer's own)
in the fallback branch, matching the override logic already used for the
transliterator.

---

## 18. [LOW] Arabic/Hebrew tokens retain non-ASCII modifier letters (ʿ, ʻ)

**File:** `src/tokenizer.zig`
**Lines:** `stripTranslitMarks`, token UTF-8 stage, `transliterateString`

### Description

`Arabic-Latin` emits U+02BF (ʿ) and `Hebrew-Latin` can emit U+02BB (ʻ) and
U+2019 (ʼ). `Latin-ASCII` only maps letters, digits and basic punctuation,
so the modifiers survive the pipeline.

**Verified (probes on ICU 78 and 67.1.0, identical):** Arabic keeps U+02BF —
العربية → `alʿrbyt` (bytes CA BF), عربية → `ʿrbyt`; hamza-on-alef words lose
the hamza entirely (قرآن → `qran`, سؤال → `swal`). Hebrew-Latin output is
already pure ASCII on both versions (אמונה → `'mwnh'`), but U+02BB/U+2019
are stripped anyway to cover older builds.

### Impact

- Tokens for Arabic are not pure ASCII, so case-insensitive ASCII searches
  and URL-safe token handling behave inconsistently; the modifiers must be
  typed exactly to match.

### Suggested fix (implemented)

Post-map U+02BF, U+02BB and U+2019 to nothing in the UTF-8 domain
(`stripTranslitMarks`), applied to the token text in `tokenizeText` and to
the result of `transliterateString`, gated on the rule string containing
`Arabic-Latin`/`Hebrew-Latin`. Only the token *text* is compacted — the
reported byte range still points at the original word and whitespace is
untouched, so the position map (bug #15) holds exactly. Regression tests:
Arabic tokenizeText produces pure-ASCII `alrbyt`/`rbyt`/`qran`/`swal`, and
`transliterateString` returns pure ASCII for both ar and he rules.

---

## New Findings (2026 audit, third pass)

A third audit pass, again probe-driven against Homebrew ICU 78 (macOS),
found one HIGH correctness bug, one MEDIUM consistency gap and five LOW
issues. None are fixed yet. The #19 finding was reproduced with an
instrumented position-map dump; #20 with a query-time override probe;
#24/#25 by build inspection.

| Bug | Severity | Status |
|-----|----------|--------|
| #19 | HIGH | OPEN |
| #20 | MEDIUM | OPEN |
| #21 | LOW | OPEN |
| #22 | LOW | OPEN |
| #23 | LOW | OPEN |
| #24 | LOW | OPEN |
| #25 | LOW | OPEN |

---

## 19. [HIGH] NFKD ligature expansion corrupts the token stream — wrong byte ranges + silent token loss

**File:** `src/tokenizer.zig`
**Lines:** ~233 (`isSpaceLikeU16`), ~487–524 (whitespace-anchor position
map), ~557 (`nTokenByte <= 0` drop guard)

### Description

The bug #15 fix anchors the normalized→original position map at whitespace,
under the stated invariant that every rule chain preserves whitespace **1:1
and in order**. That invariant is false for compatibility characters whose
NFKD decomposition *inserts* spaces that do not exist in the source text.
The prime example is U+FDFA (ﷺ, ARABIC LIGATURE SALLALLAHOU ALAYHE
WASALLAM): `NFKD(U+FDFA)` expands 1 UTF-16 unit into 19 units containing
**three real U+0020 characters**. (U+FDFD has no decomposition mapping and
is harmless; U+FDFA is reachable through the universal, ar, ru, he and el
chains alike because they all start with `NFKD;`.)

The anchor loop then mis-associates:

1. The first phantom space consumes the input's only real space as its
   "original" counterpart.
2. Every later phantom space scans forward for a real space that does not
   exist, hits end-of-text and breaks out of the loop.
3. The trailing segment is scaled onto a **zero-length** original span
   (`seg_orig_len == utf16_pos - seg_orig_start == 0`), so all remaining
   positions collapse onto one original offset.

Verified with an instrumented probe (position-map dump) on ICU 78, input
`xﷺy z` (7 bytes), universal tokenizer:

```
norm = 'xsly allh ʿlyh wsllmy z'   pm[10..13] = 4, pm[14..22] = 5 (collapsed)
emitted tokens:
  token='xsly' [0,5)    ← franken-token: ligature letters glued onto 'x'
  token='lyh'  [6,7)    ← index claims bytes [6,7)="lyh"; source bytes are "z"
```

`allh`, `ʿlyh`, `wsllmy`, the real `y` and the real `z` are silently
dropped by the `nTokenByte <= 0` guard.

### Impact

- FTS5 offsets drive snippets, highlighting and phrase queries: the index
  asserts document content that does not exist (`lyh` where the document
  says `z`) and loses existing words entirely.
- Silent data loss / index corruption on any text containing a
  decompose-into-whitespace ligature. No error is surfaced.

### Suggested fix

Before building the anchor map, count space-like units in both texts. If
the normalized count exceeds the original count (phantom whitespace),
fall back to an ordinal-matching strategy: pair the first *k* normalized
spaces with the *k* original spaces in order, treat surplus normalized
spaces as ordinary characters, and always anchor segment ends at
end-of-text so no segment can scale onto a zero-length span. A regression
test should tokenize `xﷺy z` and assert every emitted range satisfies
`iStart < iEnd` and that the token text at `[iStart,iEnd)` in the source
round-trips (no franken-tokens, nothing dropped beyond known symbol drops).

---

## 20. [MEDIUM] Query-time `override_locale` bypasses locale validation (bug #16 fixed create-time only)

**File:** `src/tokenizer.zig`
**Lines:** ~39 (create-time validation), ~370–392 (`tokenizeText`
override path opens `ubrk_open`/`utrans_openU` unvalidated)

### Description

Bug #16 added `isValidLocaleLanguage` to `IcuTokenizer.create`, so
`CREATE VIRTUAL TABLE … tokenize='icu xx_NOPE'` fails fast. But the v2
per-call override path feeds whatever `pLocale` SQLite hands over straight
into `ubrk_open`/`utrans_openU` without validation. Verified by probe: a
query-time override of `"xx_NOPE"` returns `SQLITE_OK` and tokenizes with
the universal chain, while the identical string is rejected at create time.
The two entry points have contradictory contracts for the same input.

(Practical segmentation impact on modern ICU is small — dictionary-based
breaking is script-driven, verified identical tokens for `ja`/`jp`/
`xx_NOPE`/`JA`/`en_US`/`th` on Thai text — but rule-chain selection does
diverge and, more importantly, typos stay silent instead of failing like
they do at CREATE time.)

### Impact

- Typo'd row/query-time locales are silently accepted; behavior differs
  from the documented, validated create-time path. Hard-to-debug
  wrong-results instead of an error.

### Suggested fix

Run the existing `isValidLocaleLanguage` on the effective override before
opening the dynamic break iterator/transliterator and return
`c.SQLITE_ERROR` when it rejects the locale. Reuse — do not duplicate —
the validator.

---

## 21. [LOW] `getLocaleInfo` language matching is case-sensitive and unanchored

**File:** `src/rules.zig`
**Lines:** 23–33 (`getLocaleInfo` prefix table)

### Description

Two defects in one matcher:

1. **Case-sensitive:** `"JA"`, `"Ja"` etc. miss the alias table and fall to
   the DEFAULT chain + tokenizer name `"icu"`, while `isValidLocaleLanguage`
   accepts them as Japanese because `uloc_getLanguage` lowercases. ICU
   itself treats locale IDs case-insensitively.
2. **Unanchored:** the raw 2-byte prefix matches unrelated languages:
   `kok` (Konkani) → ko rules, `arn` (Mapudungun) / `arp` (Arapaho) → ar
   rules, `jam` (Jamaican Creole) → ja rules.

Today the practical blast radius is small only because `ICU_RULE_DEFAULT`
happens to be a superset of every per-locale chain — but that coupling is
incidental, not designed, and `getTokenizerNameForLocale("JA_JP")`
returning `"icu"` is already observable.

### Impact

- Inconsistent rule selection between identically-meaning locale spellings;
  wrong tokenizer name reported for uppercase locales; latent breakage if
  per-locale chains ever diverge from the DEFAULT superset.

### Suggested fix

Extract the language subtag up to the first `-`/`_`/`@` (or end of
string), compare case-insensitively (`std.ascii.eqlIgnoreCase`), and keep
the alias list. Extend the `rules mapping` unit test with `"JA_JP"`,
`"kok"`, `"arn"` cases.

---

## 22. [LOW] Pre-ICU-69 builds impossible although their runtime fallback exists

**Files:** `src/c_icu.zig` lines 56–62 (`ubrk_clone` resolver),
`src/tokenizer.zig` line 8 vs `src/c_icu.zig` line 6

### Description

The `ubrk_clone` resolver hard-errors via `@compileError` when the
translate-C header does not declare `ubrk_clone` (headers older than the
ICU version that introduced it). Yet `tokenizeText` carries the
non-clone `ubrk_open` fallback branch written precisely *for* those old
ICU versions (bug #17). On such systems the project cannot even compile,
so the graceful-degradation code is dead by construction and the two
version gates contradict each other.

Additionally `has_ubrk_clone` is defined twice with different expressions
(`builtin.os.tag.isDarwin() or ver >= 69` vs `icu_ver == 0 or >= 69`) —
equivalent today but drift-prone; a single shared definition should own it.

### Impact

- No effect on supported platforms today; blocks any future build against
  genuinely old ICU and invites gate drift.

### Suggested fix

Make the resolver optional: expose `pub const has_ubrk_clone` (or an
optional function pointer) from `c_icu.zig`, derive it once from
`@hasDecl(c, "ubrk_clone")` plus the version macro, use it in both places,
and let `tokenizeText` take the fallback branch when absent instead of
failing compilation.

---

## 23. [LOW] Dead `build_options` import in `tokenizer.zig` is a latent build breaker

**File:** `src/tokenizer.zig` line 6; `build.zig` lines ~206–269

### Description

`const build_options = @import("build_options");` is never referenced. It
compiles only because Zig analyzes imports lazily. The three test
executables (`test_transliterator`, `locale_specific_tests`,
`test_locale_tokenizer`) import `tokenizer.zig` through module graphs that
do **not** provide a `build_options` import — verified working today purely
due to laziness. The first real use of the constant inside `tokenizer.zig`
will fail those three build steps with a missing-module error.

### Impact

- None now; a confusing delayed compile error later.

### Suggested fix

Delete the import (preferred), or add `.name = "build_options"` to the
three test-executable modules in `build.zig`.

---

## 24. [LOW] `build.zig`: duplicate artifact names/paths when `-Dlocale` names a loop locale

**File:** `build.zig`
**Lines:** 105–111 & 131–137 (top-level conditional libs) vs 141–193
(unconditional per-locale loop)

### Description

With `-Dlocale=ja` (any of the eight loop locales), the top-level
conditional libraries are named `fts5_icu_ja` / `fts5_icu_ja_legacy` —
exactly what the unconditional loop also builds and installs. Verified:
`zig build -Dlocale=ja` succeeds but compiles each colliding artifact
twice and installs both to the same `zig-out/lib` path (last install
wins). Today the duplicates are byte-equivalent builds; if the two option
sets ever diverge (e.g. different `api_version` defaults), the silent
overwrite picks whichever installs last.

### Impact

- Wasted double compilation; silent overwrite hazard on future divergence.

### Suggested fix

Skip the loop entries equal to `-Dlocale` (or skip the top-level
conditional libs when `locale` is empty and rely on the loop), so each
artifact name is produced exactly once.

---

## 25. [LOW] Unit tests run under ReleaseFast — safety-checked UB untested

**File:** `build.zig` line 6 (optimize default) and lines 196–203 (test step)

### Description

`optimize` defaults to `.ReleaseFast` and `addTest` inherits the root
module's optimize mode, so `zig build test` executes the suite without
safety checks: integer overflow, OOB slice indexing and other
panic-checked UB classes are compiled out precisely where this project's
regression suite should catch them. Leak detection (testing allocator)
still works, but e.g. a reintroduced off-by-one heap overflow of the bug
#10 class would no longer trap in tests.

### Impact

- Weakened regression protection; bugs of the class previously fixed (#2,
  #8, #10) would pass the suite silently if reintroduced.

### Suggested fix

Build the test module with Debug explicitly (separate options module or
`.optimize = .Debug` on a dedicated test root module), keeping ReleaseFast
as the default only for shipped libraries.

---

## Third-pass minor notes (style/hardening, unnumbered)

- Rule-string substring sniffing is duplicated and fragile:
  `"Russian-Latin/BGN"` probed 3× (`transliterateString` incl. its retry
  branch, plus `tokenizeText`) and Arabic/Hebrew probed 2×
  (`src/tokenizer.zig` ~92, ~115, ~153, ~356–358). Should be boolean flags
  on `LocaleInfo` computed once, instead of re-scanning rule text per call.
- `transliterateString` returns `allocator.dupe(u8, …)` of an internal
  buffer (~line 160) — one avoidable allocation+copy per call; allocate the
  final buffer directly.
- `scripts/test_all.sh:116` pipes sqlite3 through `sed`, so `$?` belongs to
  `sed`; that test can never fail. No `tests/*.sql` sets `.bail on` (works
  on modern CLIs which exit non-zero on SQL errors, fragile on older ones).
- Verified sound during this pass (no findings): all stack/heap SBO
  switching and grow-on-overflow retry paths (bug #8 pattern replicated
  correctly; no leak/UAF/double-free found under the testing allocator);
  byte-offset-map completeness for valid and malformed UTF-8; position-map
  monotonicity for well-formed inputs; entrypoint export filtering (bug
  #13); `fts5_api` struct layout; `jp`/`cn`/`kr` alias resolution (ICU
  canonicalizes them); `create`/`destroy` errdefer ordering.
