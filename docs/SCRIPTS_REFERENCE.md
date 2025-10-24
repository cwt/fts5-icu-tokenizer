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
Builds all supported locale-specific tokenizers and the universal tokenizer.

Usage:
```bash
./scripts/build_all.sh
```

This script:
1. Builds separate shared libraries for each locale with optimized rules
2. Places all libraries in the `build/` directory
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
Builds and runs tests for the universal tokenizer and Japanese tokenizer.

Usage:
```bash
./scripts/test.sh
```

### `test_all.sh`
Tests all built libraries with appropriate sample text.

Usage:
```bash
./scripts/test_all.sh
```

This script:
1. Tests the universal tokenizer with mixed language content
2. Tests each locale-specific tokenizer with sample text in that language
3. Reports success or failure for each test

## Code Quality Scripts

### `code-format.sh`
Formats all source code files using clang-format and removes trailing whitespace.

Usage:
```bash
./scripts/code-format.sh
```

This script:
1. Applies clang-format rules to all .c and .h files in the src/ directory
2. Removes trailing whitespace from all .c and .h files
3. Modifies files in-place using the `-i` flag

### `lint-check.sh`
Performs static code analysis using cppcheck.

Usage:
```bash
./scripts/lint-check.sh
```

This script runs cppcheck with the following configuration:
- Exhaustive checking level
- Enables warning, style, performance, and portability checks
- Uses C11 standard compliance
- Provides verbose output

## Test Development Scripts

### `build_test.sh`
Builds the ICU transliterator test program for development and debugging.

Usage:
```bash
./scripts/build_test.sh
```

### `run_test.sh`
Builds and runs the ICU transliterator test program.

Usage:
```bash
./scripts/run_test.sh
```

This script:
1. Builds the test program
2. Runs the original test program
3. Runs the locale-specific test program

## Utility Scripts

### `demo.sh`
Provides a demonstration of building and testing the Japanese and universal tokenizers.

Usage:
```bash
./scripts/demo.sh
```

This script:
1. Builds the Japanese tokenizer
2. Checks the built libraries
3. Tests both Japanese and universal tokenizers
4. Shows how to use the implementation in projects