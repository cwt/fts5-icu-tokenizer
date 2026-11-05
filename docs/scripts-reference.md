---
type: runbook
title: "Scripts reference"
description: "Every script in scripts/ and its usage: build, test, and code-quality helpers."
status: stable
sources:
  - scripts/
verified: human-reviewed
tags: [scripts, reference, runbook]
timestamp: 2026-10-16T23:22:29+07:00
stale_after: 2027-03-12T00:00:00Z
---


# FTS5 ICU Tokenizer - Scripts Reference

This document provides an overview of all the scripts in the `scripts/` directory and their usage.

## Build Scripts

### `build.sh`
Builds all supported locale-specific tokenizers and the universal tokenizer (API v1 and v2).
Cleans `.cache`, `.zig-cache`, `build`, and `zig-out` first (unless `--rebuild` is
given), then symlinks `./build` to `zig-out/lib`.
Supports **Zig 0.16.0, 0.17.0, and 0.17.1**.

Options:
- (no option) — clean build of all tokenizers (API v1 + v2, default)
- `--rebuild` — reuses the cache and previous `zig-out` instead of clearing them

Environment Variables:
- `ZIG` — path to the Zig compiler binary (default: `"zig"`).
  Example: `ZIG=/path/to/zig-0.17.1/zig ./scripts/build.sh`

Usage:
```bash
# Clean build of all tokenizers (default)
./scripts/build.sh

# Quick rebuild without clearing the cache
./scripts/build.sh --rebuild

# Build using a specific Zig compiler version
ZIG=/path/to/zig-0.17.1/zig ./scripts/build.sh
```

## Test Scripts

### `test.sh`
Builds (fresh by default) and runs tests for the universal tokenizer and Japanese tokenizer (API v2).

Usage:
```bash
# Clean build + test
./scripts/test.sh

# Rebuild (cached) + test
./scripts/test.sh --rebuild
```

### `test_legacy.sh`
Builds (fresh by default) and runs tests for the universal tokenizer and Japanese tokenizer using API v1 (legacy).

Usage:
```bash
# Clean build + test legacy
./scripts/test_legacy.sh

# Rebuild (cached) + test legacy
./scripts/test_legacy.sh --rebuild
```

### `test_all.sh`
Tests all built libraries (API v2 by default) with appropriate sample text.

Usage:
```bash
./scripts/test_all.sh
```

This script:
1. Tests the universal tokenizer with mixed language content
2. Tests each locale-specific tokenizer with sample text in that language
3. Reports success or failure for each test

### `test_all_legacy.sh`
Tests all built libraries using API v1 (legacy) with appropriate sample text.

Usage:
```bash
./scripts/test_all_legacy.sh
```

This script:
1. Tests the universal tokenizer (API v1) with mixed language content
2. Tests each locale-specific tokenizer (API v1) with sample text in that language
3. Reports success or failure for each test

## Code Quality Scripts

### `code-format.sh`
Formats all source code files using `zig fmt .`.

Usage:
```bash
./scripts/code-format.sh
```

### `lint-check.sh`
Performs static AST checks on Zig source files using `zig ast-check`.

Usage:
```bash
./scripts/lint-check.sh
```