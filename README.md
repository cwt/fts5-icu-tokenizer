# FTS5 ICU Tokenizer for SQLite (Zig 0.16.0 Edition)

Version **6.0.3**

This project provides custom FTS5 tokenizers for SQLite implemented in **Zig 0.16.0** using the International Components for Unicode (ICU) library to provide robust word segmentation and text normalization across multiple languages.

---

## Why Migrate to Zig 0.16.0?

This project was originally written in C with CMake. The rewrite to **Zig 0.16.0** resolves several fundamental issues inherent to C extension development:

### 1. Guaranteed Memory Safety & Zero Leaks
- **Old C Problem**: Error handling across temporary text buffers and ICU handles required fragile `goto cleanup;` branches. Missing a `free()` or `ubrk_close()` call on an error path caused memory leaks during high-throughput SQLite FTS indexing sessions.
- **Zig Solution**: First-class `defer` and `errdefer` semantics guarantee that every heap allocation (`allocator.alloc`, `allocator.create`) and ICU handle (`ubrk_close`, `utrans_close`) is deterministically cleaned up, even when errors occur mid-tokenization.

### 2. Elimination of Build System & Toolchain Fragility
- **Old C Problem**: Building cross-platform C extensions required complex CMake files, platform-specific Homebrew path workarounds (`brew --prefix icu4c`), Windows MSVC compiler flags (`/utf-8`), and external generators (`make`, `ninja`, Visual Studio).
- **Zig Solution**: `zig build` replaces CMake and custom shell build scripts entirely. Zig operates as a unified compiler and build driver (`zig cc` / `b.addTranslateC`), handling C header translation, compilation, and cross-compilation out of the box with zero external build tool dependencies.

### 3. Safe UTF-8 / UTF-16 Conversion & Bounds Checking
- **Old C Problem**: Manual UTF-8 to UTF-16 buffer sizing in C risked integer overflow (`nText > INT32_MAX / 2`) and undefined behavior when encountering invalid Unicode byte sequences.
- **Zig Solution**: Native standard library `std.unicode` provides safe UTF-8 decoding and codepoint iteration. Slice indexing in Zig is bounds-checked at runtime by default, preventing out-of-bounds buffer overflows.

### 4. Unified Codebase for FTS5 API v1 and v2
- **Old C Problem**: Supporting legacy FTS5 API v1 (for older RHEL / SQLite installations) alongside API v2 required maintaining duplicated C files (`fts5_icu.c` vs `fts5_icu_legacy.c`) and fragile macro token-pasting (`PASTE_IMPL`).
- **Zig Solution**: A single, clean Zig codebase ([src/fts5_icu.zig](file:///Users/cwt/Projects/fts5-icu-tokenizer/src/fts5_icu.zig)) exports both v2 and legacy v1 extension entrypoints natively, controlled cleanly via `build.zig` build options.

### 5. Pure Zig C-Interop — No C Wrappers Needed
- **Old C Problem**: Calling ICU functions from C required a separate `icu_helper.c` file with thin wrapper functions to avoid symbol conflicts.
- **Zig Solution**: Zig's `addTranslateC` (`build.zig`) directly translates ICU and SQLite C headers into Zig `extern` declarations at build time. The Zig code calls ICU functions directly (`c.ubrk_open`, `c.utrans_openU`, `c.u_strFromUTF8`) via the `c` module — no intermediate C wrapper file, no `@cImport`. The entire codebase is pure Zig.

---

## Key Features

- **Built with Zig 0.16.0**: High-performance, memory-safe, zero-allocation runtime overhead.
- **FTS5 API v1 & v2 Support**: Full support for both current API v2 and legacy API v1 extension entrypoints.
- **ICU Word Segmentation & Transliteration**:
  - Word boundary iteration (`ubrk`)
  - Full script transliteration and text normalization (`utrans`)
- **Universal & Locale-Specific Tokenizers**:
  - `icu` (Universal multi-language rule set)
  - `icu_ja`, `icu_zh`, `icu_th`, `icu_ko`, `icu_ar`, `icu_ru`, `icu_he`, `icu_el` (Optimized locale rule sets)
- **Robust UTF-8 & Memory Handling**: Safe character index mapping and buffer handling.

---

## Quick Start

### Prerequisites
- **Zig** (version `0.16.0` or higher)
- **SQLite3** development libraries
- **ICU** development libraries (`libicu-uc`, `libicu-i18n`)

| Platform | Dependencies |
|----------|--------------|
| macOS | `brew install zig sqlite icu4c` |
| Debian / Ubuntu | `apt install libsqlite3-dev libicu-dev` + Zig 0.16.0 |
| RHEL / Fedora | `dnf install sqlite-devel libicu-devel` + Zig 0.16.0 |

---

## Building & Testing

### 1. Build All Tokenizer Libraries
```bash
zig build
```
This produces shared dynamic libraries in `zig-out/lib/`:
- `libfts5_icu.dylib` (or `.so` / `.dll`) — Universal multi-language tokenizer (v2 & legacy v1 entrypoints)
- `libfts5_icu_ja.dylib` — Japanese (`icu_ja`)
- `libfts5_icu_zh.dylib` — Chinese (`icu_zh`)
- `libfts5_icu_th.dylib` — Thai (`icu_th`)
- `libfts5_icu_ko.dylib` — Korean (`icu_ko`)
- `libfts5_icu_ar.dylib` — Arabic (`icu_ar`)
- `libfts5_icu_ru.dylib` — Russian (`icu_ru`)
- `libfts5_icu_he.dylib` — Hebrew (`icu_he`)
- `libfts5_icu_el.dylib` — Greek (`icu_el`)

### 2. Run Tests
```bash
# Run unit tests
zig build test

# Run ICU transliterator tests
zig build run-transliterator

# Run locale-specific transliterator tests
zig build run-locale-tests

# Run locale tokenizer test
zig build run-tokenizer-test

# Run full SQL test suite
./scripts/test_all.sh
```

---

## Usage Examples

### Loading Universal Tokenizer
```sql
.load ./zig-out/lib/libfts5_icu

CREATE VIRTUAL TABLE documents USING fts5(content, tokenize = 'icu');
INSERT INTO documents(content) VALUES ('甜蜜蜜,你笑得甜蜜蜜-หวานปานน้ำผึ้ง,ยิ้มของคุณช่างหวานปานน้ำผึ้ง');
SELECT * FROM documents WHERE documents MATCH 'หวาน';
```

### Loading Locale-Specific Tokenizer (e.g. Thai)
```sql
.load ./zig-out/lib/libfts5_icu_th

CREATE VIRTUAL TABLE documents_th USING fts5(content, tokenize = 'icu_th');
INSERT INTO documents_th(content) VALUES ('การทดสอบภาษาไทยในระบบค้นหา');
SELECT * FROM documents_th WHERE documents_th MATCH 'ภาษา';
```

### Querying Version
```sql
.load ./zig-out/lib/libfts5_icu
SELECT fts5_icu_version(); -- Returns "6.0.3"
```

---

## Supported Locales & ICU Rules

| Locale | Tokenizer Name | Default Transliteration Rules |
|--------|----------------|-------------------------------|
| `ja` | `icu_ja` | `NFKD; Katakana-Hiragana; Lower; NFKC` |
| `zh` | `icu_zh` | `NFKD; Traditional-Simplified; Lower; NFKC` |
| `th` | `icu_th` | `NFKD; Lower; NFKC` |
| `ko` | `icu_ko` | `NFKD; Lower; NFKC` |
| `ar` | `icu_ar` | `NFKD; Arabic-Latin; Lower; NFKC` |
| `ru` | `icu_ru` | `NFKD; Cyrillic-Latin; Lower; NFKC` |
| `he` | `icu_he` | `NFKD; Hebrew-Latin; Lower; NFKC` |
| `el` | `icu_el` | `NFKD; Greek-Latin; Lower; NFKC` |
| — | `icu` (Universal) | `NFKD; Arabic-Latin; Cyrillic-Latin; Hebrew-Latin; Greek-Latin; Latin-ASCII; Lower; NFKC; Traditional-Simplified; Katakana-Hiragana` |

---

## Project Structure

```
fts5-icu-tokenizer/
├── build.zig                  # Zig 0.16.0 build script
├── build.zig.zon              # Package manifest & fingerprint
├── src/
│   ├── fts5_icu.zig           # SQLite extension exports (v1 & v2 APIs)
│   ├── tokenizer.zig          # ICU tokenization & segmentation logic
│   ├── rules.zig              # Locale rules & suffix mapping
│   ├── c_includes.h           # C header input for translateC (provides ICU + SQLite Zig bindings)
│   ├── c_icu.zig              # Platform-agnostic ICU function name resolution
│   ├── test_transliterator.zig# Test runner
│   ├── locale_specific_tests.zig
│   └── test_locale_tokenizer.zig
└── tests/                     # SQL integration test suite
    └── *.sql
```

---

## Formatting
To format the codebase according to standard Zig style:
```bash
zig fmt .
```