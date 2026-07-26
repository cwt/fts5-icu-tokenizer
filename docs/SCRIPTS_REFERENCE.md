# FTS5 ICU Tokenizer - Scripts Reference

This document provides an overview of all the scripts in the `scripts/` directory and their usage.

## Build Scripts

### `build.sh`
Builds the FTS5 ICU tokenizer for a specific locale or the universal tokenizer.

Usage:
```bash
# Build the universal tokenizer
./scripts/build.sh

# Build for a specific locale (e.g., Japanese)
./scripts/build.sh ja
```

### `build_all.sh`
Builds all supported locale-specific tokenizers and the universal tokenizer using API v2 (current).

Usage:
```bash
./scripts/build_all.sh
```

This script:
1. Builds separate shared libraries for each locale with optimized rules (API v2)
2. Places all libraries in the `build/` directory
3. Shows progress and any warnings during the build process

### `build_legacy.sh`
Builds the FTS5 ICU tokenizer using API v1 (legacy) for a specific locale or the universal tokenizer.

Usage:
```bash
# Build the universal tokenizer (API v1)
./scripts/build_legacy.sh

# Build for a specific locale (e.g., Japanese, API v1)
./scripts/build_legacy.sh ja
```

### `build_all_legacy.sh`
Builds all supported locale-specific tokenizers and the universal tokenizer using API v1 (legacy) only.

Usage:
```bash
./scripts/build_all_legacy.sh
```

This script:
1. Builds separate shared libraries for each locale with optimized rules (API v1 only)
2. Places all libraries in the `build/` directory with appropriate suffixes
3. Shows progress and any warnings during the build process

### `build_all_with_legacy.sh`
Builds all supported locale-specific tokenizers and the universal tokenizer for both API v1 and API v2.

Usage:
```bash
./scripts/build_all_with_legacy.sh
```

This script:
1. Builds separate shared libraries for each locale with optimized rules (API v1 and API v2)
2. Places all libraries in the `build/` directory with appropriate suffixes
3. Shows progress and any warnings during the build process

### `build_all_with_clang.sh`
Builds all supported locale-specific tokenizers using the Clang compiler to check portability.

Usage:
```bash
./scripts/build_all_with_clang.sh
```

This script:
1. Uses Clang instead of GCC for compilation
2. Builds all tokenizers to ensure cross-compiler compatibility
3. Performs the same operations as `build_all.sh` but with Clang

## Test Scripts

### `test.sh`
Builds and runs tests for the universal tokenizer and Japanese tokenizer (API v2 by default).

Usage:
```bash
./scripts/test.sh
```

### `test_legacy.sh`
Builds and runs tests for the universal tokenizer and Japanese tokenizer using API v1 (legacy).

Usage:
```bash
./scripts/test_legacy.sh
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