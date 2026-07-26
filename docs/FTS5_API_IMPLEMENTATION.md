# FTS5 ICU Tokenizer for SQLite - FTS5 API Implementation (Zig 0.16.0)

This project provides FTS5 tokenizer extensions for SQLite implemented in **Zig 0.16.0**. It supports both the primary **FTS5 v2 API** (`fts5_tokenizer_v2`) and the legacy **FTS5 v1 API** (`fts5_tokenizer`) using the International Components for Unicode (ICU) library.

---

## FTS5 API v2 vs v1 Overview

### FTS5 v2 API
The FTS5 v2 API (`fts5_tokenizer_v2`) is the default interface in SQLite 3.20.0+. Key features:
- **`iVersion`**: Set to `2` for explicit version tracking.
- **Locale Support**: `xTokenize` includes `pLocale` and `nLocale` parameters (`const char *pLocale, int nLocale`), enabling per-query locale-aware tokenization.
- **`xCreateTokenizer_v2`**: Registered via the `xCreateTokenizer_v2` method on the `fts5_api` structure.

### FTS5 v1 API (Legacy)
The FTS5 v1 API (`fts5_tokenizer`) is maintained for compatibility with older SQLite builds and enterprise distributions (e.g. RHEL 7/8).
- `xTokenize` does not accept locale parameters.
- Registered via the `xCreateTokenizer` method on the `fts5_api` structure.

---

## Zig Struct Definitions ([src/fts5_icu.zig](file:///Users/cwt/Projects/fts5-icu-tokenizer/src/fts5_icu.zig))

In Zig, the C FTS5 structures are represented using `extern struct`:

```zig
const Fts5Tokenizer = opaque {};

// FTS5 API v1 structure
const fts5_tokenizer = extern struct {
    xCreate: ?*const fn (?*anyopaque, [*c][*c]const u8, c_int, [*c]?*Fts5Tokenizer) callconv(.c) c_int,
    xDelete: ?*const fn (?*Fts5Tokenizer) callconv(.c) void,
    xTokenize: ?*const fn (?*Fts5Tokenizer, ?*anyopaque, c_int, [*c]const u8, c_int, ?*const fn (?*anyopaque, c_int, [*c]const u8, c_int, c_int, c_int) callconv(.c) c_int) callconv(.c) c_int,
};

// FTS5 API v2 structure
const fts5_tokenizer_v2 = extern struct {
    iVersion: c_int,
    xCreate: ?*const fn (?*anyopaque, [*c][*c]const u8, c_int, [*c]?*Fts5Tokenizer) callconv(.c) c_int,
    xDelete: ?*const fn (?*Fts5Tokenizer) callconv(.c) void,
    xTokenize: ?*const fn (?*Fts5Tokenizer, ?*anyopaque, c_int, [*c]const u8, c_int, [*c]const u8, c_int, ?*const fn (?*anyopaque, c_int, [*c]const u8, c_int, c_int, c_int) callconv(.c) c_int) callconv(.c) c_int,
};
```

---

## Tokenizer Functions

### 1. `icuCreate`
Initializes the tokenizer instance, parsing optional locale arguments or transliteration rules specified in the `CREATE VIRTUAL TABLE ... USING fts5(...)` statement.

```zig
fn icuCreate(
    pCtx: ?*anyopaque,
    azArg: [*c][*c]const u8,
    nArg: c_int,
    ppOut: [*c]?*Fts5Tokenizer,
) callconv(.c) c_int
```

### 2. `icuTokenize` (v2 API)
Performs text tokenization using ICU word boundary iteration (`ubrk_open`, `ubrk_next`) and transliteration (`utrans_openU`, `utrans_transUChars`). Supports query-time locale overrides via `pLocale`.

```zig
fn icuTokenize(
    pTok: ?*Fts5Tokenizer,
    pCtx: ?*anyopaque,
    flags: c_int,
    pText: [*c]const u8,
    nText: c_int,
    pLocale: [*c]const u8,
    nLocale: c_int,
    xToken: ?*const fn (?*anyopaque, c_int, [*c]const u8, c_int, c_int, c_int) callconv(.c) c_int,
) callconv(.c) c_int
```

### 3. `icuDelete`
Frees memory allocated for the tokenizer instance using Zig's allocator (`std.heap.c_allocator`).

```zig
fn icuDelete(pTok: ?*Fts5Tokenizer) callconv(.c) void
```

---

## Registration & Extension Entrypoint

The SQLite extension entrypoint is exported as a C function. The build system controls whether v2 or v1 registration is selected based on build options:

```zig
pub export fn sqlite3_fts5icu_init(
    db: ?*c.sqlite3,
    pzErrMsg: [*c][*c]const u8,
    pApi: [*c]const c.sqlite3_api_routines,
) callconv(.c) c_int {
    // Save SQLite API routines pointer
    sqlite3_api = pApi;
    
    // Retrieve FTS5 API pointer
    // Register tokenizer using xCreateTokenizer_v2 (API v2) or xCreateTokenizer (API v1)
    // Register helper SQL functions like fts5_icu_version()
}
```

---

## Building and Testing

### Building with Zig
```bash
# Build universal and all locale tokenizers (v2 API)
zig build

# Build specific locale
zig build -Dlocale=ja

# Build legacy v1 API version
zig build -Dapi_version=v1
```

### Running Tests
```bash
# Run SQLite test suite
./scripts/test_all.sh

# Run Zig unit and integration tests
zig build test
zig build run-transliterator
zig build run-locale-tests
```