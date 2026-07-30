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
- **Zig Solution**: A single, clean Zig codebase (`src/fts5_icu.zig`) exports both v2 and legacy v1 extension entrypoints natively, controlled cleanly via `build.zig` build options.

### 5. Pure Zig C-Interop — No C Wrappers Needed
- **Old C Problem**: Calling ICU functions from C required a separate `icu_helper.c` file with thin wrapper functions to avoid symbol conflicts.
- **Zig Solution**: Zig's `addTranslateC` (`build.zig`) directly translates ICU and SQLite C headers into Zig `extern` declarations at build time. The Zig code calls ICU functions directly (`c.ubrk_open`, `c.utrans_openU`, `c.u_strToUTF8WithSub`) via the `c` module — no intermediate C wrapper file, no `@cImport`. The entire codebase is pure Zig.

### 6. Comptime Entry Point Generation — No More Repetitive Boilerplate
- **Old C Problem**: Each locale required a separate C file or a fragile macro (`PASTE_IMPL` `PASTE`) to produce the unique `sqlite3_ftsicuXX_init` symbol that SQLite's `.load` command resolves. Supporting 8 locales × 2 API versions meant 16 near-identical function definitions — easy to miss one, easy to get a name wrong.
- **Zig Solution**: A single `comptime` block generates all 35 entry points from one declarative table. The Zig compiler evaluates the loop at build time, producing the correct exported symbols automatically. Adding a new locale is a one-line addition to the table, not a copy-paste of an entire function. Each build exports only the entry points relevant to its locale — the universal library keeps the 3 non-locale-specific ones (`sqlite3_ftsicu_init`, `sqlite3_ftsicu_legacy_init`, `sqlite3_ftsiculegacy_init`) and each locale-specific library keeps its own 4 — so there is no redundant symbol bloat across the per-locale `.so` files.

### 7. Null-Safety Built Into the Type System
- **Old C Problem**: A `NULL` pointer in a C extension causes a silent crash. SQLite's entry point can receive `NULL` for `db` or `pApi` (e.g., from a malformed `.load` command), but the compiler won't warn you if you forget to check.
- **Zig Solution**: Pointers that can be null are marked explicitly with `?` (e.g., `?*c.sqlite3`). The compiler forces a null check before the pointer can be used as non-null, making it impossible to forget. Every entry point in this project validates both `db` and `pApi` at the top — enforced by the language, not by convention.

### 8. Thread Safety by Design — Clone per Call
- **Old C Problem**: ICU handles (`UBreakIterator`, `UTransliterator`) are not thread-safe. Sharing them across FTS5 queries required either global locks or careful per-thread management, both easy to get wrong under load.
- **Zig Solution**: Every `tokenizeText()` call isolates ICU handles before use. On ICU >= 69 the fast `ubrk_clone` path copies the handle; on older ICU (e.g. EL9 / ICU 67) a fresh `ubrk_open` is used as a fallback. There is no shared mutable state — each thread gets its own isolated copy. This makes the extension safe for concurrent FTS5 queries without locks, waits, or subtle data-race bugs. The pattern is verified by multi-threaded unit tests.

### 9. Stack-Buffer Optimization for Small Inputs
- **Old C Problem**: Every tokenization request, even for short strings, triggered heap allocation for UTF-16 conversion buffers, byte-offset maps, and transliteration scratch space. This added malloc/free overhead to every `MATCH` operation.
- **Zig Solution**: The tokenizer uses fixed-size stack buffers (512 elements) for the common case. If the input fits, zero heap allocations occur — the entire conversion and transliteration pipeline runs on the stack. Heap allocation is only used when the input exceeds the stack capacity. Small inputs (most real-world tokens) are processed with deterministic, allocation-free performance.

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

| Platform | Dependencies | Notes |
|----------|--------------|-------|
| macOS | `brew install zig sqlite icu4c` | |
| Fedora 44+ | `dnf install sqlite-devel libicu-devel gcc zig` | Zig 0.16.0 in repos, no extra download |
| Debian 13 (stable) | `apt install libsqlite3-dev sqlite3 libicu-dev gcc wget xz-utils` + [Zig 0.16.0](https://ziglang.org/download/) | ICU 76, SQLite 3.46.1 (FTS5 API v1 only; v2 requires SQLite >= 3.47) |
| Ubuntu 26.04 LTS | `apt install libsqlite3-dev sqlite3 libicu-dev gcc wget xz-utils` + [Zig 0.16.0](https://ziglang.org/download/) | ICU 78, SQLite 3.46.1 (FTS5 API v1 only; v2 requires SQLite >= 3.47); repo zig is 0.14.1 — too old |
| AlmaLinux 10 (RHEL 10) | `dnf install sqlite-devel libicu-devel gcc wget xz` + [Zig 0.16.0](https://ziglang.org/download/) | ICU 74, SQLite 3.46.1 (FTS5 API v1 only; v2 requires SQLite >= 3.47) |
| AlmaLinux 9 (RHEL 9) | `dnf install sqlite-devel libicu-devel gcc wget xz` + [Zig 0.16.0](https://ziglang.org/download/) | ICU 67 (`ubrk_clone` missing; uses `ubrk_open` fallback), SQLite 3.34.1 (FTS5 API v1 only) |

---

## Building & Testing

### 1. Build All Tokenizer Libraries
```bash
zig build
```
This produces shared dynamic libraries in `zig-out/lib/`:
- `libfts5_icu.so` (or `.dylib`) — Universal multi-language tokenizer (v2 & legacy v1 entrypoints)
- `libfts5_icu_ja.so` — Japanese (`icu_ja`)
- `libfts5_icu_zh.so` — Chinese (`icu_zh`)
- `libfts5_icu_th.so` — Thai (`icu_th`)
- `libfts5_icu_ko.so` — Korean (`icu_ko`)
- `libfts5_icu_ar.so` — Arabic (`icu_ar`)
- `libfts5_icu_ru.so` — Russian (`icu_ru`)
- `libfts5_icu_he.so` — Hebrew (`icu_he`)
- `libfts5_icu_el.so` — Greek (`icu_el`)

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

### Containerized Builds

Pre-built container images for CI or offline builds:

```bash
# Fedora 44 (Zig 0.16.0 from repos)
podman build -f .container/Containerfile -t fts5-icu:f44 .

# Debian 13 (stable)
podman build -f .container/Containerfile.debian -t fts5-icu:debian .

# Ubuntu 26.04 LTS
podman build -f .container/Containerfile.ubuntu -t fts5-icu:ubuntu .

# AlmaLinux 10 (RHEL 10 compatible)
podman build -f .container/Containerfile.el10 -t fts5-icu:el10 .

# AlmaLinux 9 (RHEL 9 compatible)
podman build -f .container/Containerfile.el9 -t fts5-icu:el9 .

# Build inside container
podman run --rm -v "$PWD:/workspace:Z" fts5-icu:f44 zig build
```

### Running Tests Inside Containers

Once an image is built, mount the project and run the full test suite:

```bash
# Fedora 44 — zig from dnf, no extra download needed
podman run --rm -v "$PWD:/workspace:Z" fts5-icu:f44 \
    bash -c "zig build && bash scripts/test_all_legacy.sh"

# Other images — zig is already pre-downloaded inside the image
podman run --rm -v "$PWD:/workspace:Z" fts5-icu:debian \
    bash -c "zig build && bash scripts/test_all_legacy.sh"
podman run --rm -v "$PWD:/workspace:Z" fts5-icu:ubuntu \
    bash -c "zig build && bash scripts/test_all_legacy.sh"
podman run --rm -v "$PWD:/workspace:Z" fts5-icu:el10 \
    bash -c "zig build && bash scripts/test_all_legacy.sh"
podman run --rm -v "$PWD:/workspace:Z" fts5-icu:el9 \
    bash -c "zig build && bash scripts/test_all_legacy.sh"
```

Each container rebuilds the project from scratch and runs every locale-specific
tokenizer test against a real SQLite instance loaded via `.load`.  The `:Z`
volume flag is required on SELinux-enabled hosts (Fedora, RHEL, AlmaLinux).

A one-liner to build and test across all five distros:

```bash
for img in f44 debian ubuntu el10 el9; do
    echo "=== fts5-icu:$img ==="
    podman run --rm -v "$PWD:/workspace:Z" fts5-icu:$img \
        bash -c "zig build 2>&1 | tail -1 && bash scripts/test_all_legacy.sh 2>&1 | grep -E 'SUCCESS|ERROR'"
    echo
done
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

### Locale Override on the Universal Tokenizer
As an alternative to loading a per-locale library, the universal tokenizer
accepts the locale inline as a second FTS5 tokenizer argument — the token after
the space selects the locale rule set (e.g. `'icu th'` uses Thai word-breaking and
transliteration):

```sql
.load ./zig-out/lib/libfts5_icu

CREATE VIRTUAL TABLE documents_th2 USING fts5(content, tokenize = 'icu th');
SELECT * FROM documents_th2 WHERE documents_th2 MATCH 'ภาษา';
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
| `ja` | `icu_ja` | `NFKD; Hiragana-Katakana; Lower; NFKC` |
| `zh` | `icu_zh` | `NFKD; Traditional-Simplified; Lower; NFKC` |
| `th` | `icu_th` | `NFKD; Lower; NFKC` |
| `ko` | `icu_ko` | `NFKD; Lower; NFKC` |
| `ar` | `icu_ar` | `NFKD; Arabic-Latin; Latin-ASCII; Lower; NFKC` |
| `ru` | `icu_ru` | `NFKD; Cyrillic-Latin; Latin-ASCII; Lower; NFKC` |
| `he` | `icu_he` | `NFKD; Hebrew-Latin; Latin-ASCII; Lower; NFKC` |
| `el` | `icu_el` | `NFKD; Greek-Latin; Latin-ASCII; Lower; NFKC` |
| — | `icu` (Universal) | `NFKD; Arabic-Latin; Cyrillic-Latin; Hebrew-Latin; Greek-Latin; Latin-ASCII; Lower; NFKC; Traditional-Simplified; Hiragana-Katakana` |

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