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

These bugs were discovered during a subsequent source-level audit. They are
**not yet fixed.**

| Bug | Severity | Status |
|-----|----------|--------|
| #8 | MEDIUM | OPEN |
| #9 | MEDIUM | OPEN |
| #10 | LOW | OPEN |
| #11 | LOW | OPEN |
| #12 | LOW | OPEN |
| #13 | LOW | OPEN |

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
symbols in the binary are unreachable dead exports.

### Impact

- Unnecessary binary bloat (~34 extra exported symbols per library). No
  runtime correctness impact; SQLite ignores the extra entrypoints.

### Suggested fix

Filter the entrypoints table at comptime with `build_options.locale` so each
library only exports its own symbols. The universal library (`locale = ""`)
would still export all 35 for backward compatibility.
