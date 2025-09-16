# FTS5 ICU Tokenizer - Project Structure

This document explains the organization of the FTS5 ICU Tokenizer project.

## Directory Structure

```
fts5-icu-tokenizer/
├── build/                  # Build output directory (created during build process)
├── docs/                   # Documentation files
├── scripts/                # Build and utility scripts
├── src/                    # Source code
├── tests/                  # Test scripts and SQL files
├── CMakeLists.txt          # CMake build configuration
├── LICENSE                 # License information
├── README.md               # Main project documentation
└── .hg/                    # Mercurial version control directory
```

## Directory Details

### `build/`
Contains the compiled shared libraries after building:
- `libfts5_icu.so` - Universal tokenizer
- `libfts5_icu_*.so` - Locale-specific tokenizers (one for each supported locale)

### `docs/`
Documentation files:
- `BUILD_TEST_README.md` - Instructions for building and testing all tokenizers

### `scripts/`
Utility scripts for building and testing:
- `build_all.sh` - Builds all supported locales and the universal tokenizer
- `test_all.sh` - Tests all built libraries
- `build_test.sh` - Original build test script (legacy)
- `run_test.sh` - Original run test script (legacy)

### `src/`
Source code files:
- `fts5_icu.c` - Main implementation of the FTS5 ICU tokenizer

### `tests/`
Test SQL scripts for each supported locale:
- `test_*_tokenizer.sql` - Individual test scripts for each locale
- `test_universal_tokenizer.sql` - Test script for the universal tokenizer

## Usage

### Building
To build all tokenizers:
```bash
./scripts/build_all.sh
```

### Testing
To test all built tokenizers:
```bash
./scripts/test_all.sh
```

### Individual Locale Testing
To test a specific locale:
```bash
sqlite3 < tests/test_ja_tokenizer.sql    # Japanese
sqlite3 < tests/test_zh_tokenizer.sql    # Chinese
# etc.
```

## Supported Locales

See `docs/BUILD_TEST_README.md` for a complete list of supported locales and their aliases.