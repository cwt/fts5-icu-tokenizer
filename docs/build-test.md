---
type: runbook
title: "Build and test"
description: "Supported locales, build/test scripts, aliases, entrypoint names, and code-quality scripts."
status: stable
sources:
  - scripts/
  - build.zig
verified: human-reviewed
tags: [build, test, locales, runbook]
timestamp: 2026-10-16T23:22:29+07:00
stale_after: 2027-03-12T00:00:00Z
---


# FTS5 ICU Tokenizer - Build and Test Scripts

This directory contains scripts to build and test the FTS5 ICU tokenizer for all supported locales.

## Supported Locales

The tokenizer supports the following locales:
- **ar** - Arabic
- **el** - Greek
- **he** - Hebrew (also accepts `iw` as an alias)
- **ja** - Japanese (also accepts `jp` as an alias)
- **ko** - Korean (also accepts `kr` as an alias)
- **ru** - Russian
- **th** - Thai
- **zh** - Chinese (also accepts `cn` as an alias)
- **Universal** - A generic tokenizer for mixed or unknown locales

## Build Scripts

### `build.sh`
Builds all supported locale-specific tokenizers and the universal tokenizer (both API v1 and API v2).
Supports **Zig 0.16.0, 0.17.0, and 0.17.1**.

Options:
- (no option) — clean build of all tokenizers (clears cache and `zig-out` first)
- `--rebuild` — reuses compiler cache and previous `zig-out` for faster iterative builds

Environment Variables:
- `ZIG` — path to the Zig compiler binary (default: `"zig"`).
  Example: `ZIG=/path/to/zig-0.17.1/zig ./scripts/build.sh`

All libraries are placed in `zig-out/lib/` and symlinked to `./build`.

#### Library Naming Convention

| Library Pattern | FTS5 API | Target Environment |
| :--- | :--- | :--- |
| `libfts5_icu*.so` | **API v2** (`fts5_tokenizer_v2`) | Modern SQLite ≥ 3.47.0 (locale-aware) |
| `libfts5_icu*_legacy.so` | **API v1** (`fts5_tokenizer`) | SQLite < 3.47.0 & LTS distros (EL8/EL9, Ubuntu 22.04/24.04, Debian 11/12) |

Usage:
```bash
# Clean build of all tokenizers (API v1 + v2, default)
./scripts/build.sh

# Quick rebuild without clearing the cache
./scripts/build.sh --rebuild

# Build using a specific Zig compiler version
ZIG=/path/to/zig-0.17.1/zig ./scripts/build.sh
```

### Building Individual Locales
You can build individual locales using `zig build` or `scripts/build.sh`:

```bash
# Build for a specific locale (e.g., Japanese)
zig build -Dlocale=ja

# The resulting library will be in zig-out/lib/ (and symlinked in ./build)
```

## Test Scripts

### `test.sh`
Builds (fresh by default) and tests the universal and Japanese tokenizers (API v2).
Supports `--rebuild` to skip clearing cache.

```bash
# Clean build + test
./scripts/test.sh

# Rebuild (cached) + test
./scripts/test.sh --rebuild
```

### `test_legacy.sh`
Builds (fresh by default) and tests the universal and Japanese tokenizers using API v1 (legacy).
Supports `--rebuild` to skip clearing cache.

```bash
# Clean build + test legacy
./scripts/test_legacy.sh

# Rebuild (cached) + test legacy
./scripts/test_legacy.sh --rebuild
```

### `test_all.sh`
Tests all built API v2 libraries with appropriate sample text.

Usage:
```bash
./scripts/test_all.sh
```

### `test_all_legacy.sh`
Tests all built API v1 (legacy) libraries with appropriate sample text.

Usage:
```bash
./scripts/test_all_legacy.sh
```

### Testing Individual Locales
You can also test individual locales using the specific test scripts:

```bash
# Test Japanese tokenizer
sqlite3 < tests/test_ja_tokenizer.sql

# Test Chinese tokenizer
sqlite3 < tests/test_zh_tokenizer.sql
```

## Locale Aliases

For compatibility, the following locale aliases are supported:
- **cn** → **zh** (Chinese)
- **jp** → **ja** (Japanese)
- **kr** → **ko** (Korean)
- **iw** → **he** (Hebrew)
- **gr** → **el** (Greek)

When using these aliases, the resulting library will use the standard ICU locale code.

## Function Names

Each built library exports a function with a name matching the SQLite FTS5 extension convention:
- For locale `ja`: `sqlite3_ftsicuja_init` (legacy: `sqlite3_ftsicuja_legacy_init`)
- For locale `zh`: `sqlite3_ftsicuzh_init` (legacy: `sqlite3_ftsicuzh_legacy_init`)
- For universal tokenizer: `sqlite3_ftsicu_init` (legacy: `sqlite3_ftsicu_legacy_init`)

This ensures compatibility with SQLite's extension loading mechanism.

## Code Quality Scripts

The project includes scripts for maintaining code quality:

### `code-format.sh`
Formats all Zig source code files using `zig fmt .`. Usage:
```bash
./scripts/code-format.sh
```

### `lint-check.sh`
Performs static AST checks on Zig source files using `zig ast-check`. Usage:
```bash
./scripts/lint-check.sh
```

For more information about the FTS5 v2 API implementation, see [fts5-api-implementation.md](fts5-api-implementation.md).

For a complete reference of all available scripts, see [scripts-reference.md](scripts-reference.md).