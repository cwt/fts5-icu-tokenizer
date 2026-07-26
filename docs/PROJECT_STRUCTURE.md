# FTS5 ICU Tokenizer - Project Structure

This document explains the organization of the FTS5 ICU Tokenizer project.

## Directory Structure

```
fts5-icu-tokenizer/
├── docs/                   # Documentation files
├── scripts/                # Build and utility scripts
├── src/                    # Zig source code files
├── tests/                  # Test scripts and SQL files
├── build.zig               # Zig build configuration
├── build.zig.zon           # Zig package dependencies & metadata
├── LICENSE                 # License information
├── README.md               # Main project documentation
└── .hg/                    # Mercurial version control directory
```

## Directory Details

### `docs/`
Documentation files:
- `BUILD_TEST_README.md` - Instructions for building and testing all tokenizers
- `FTS5_API_IMPLEMENTATION.md` - Complete documentation on the FTS5 v2 API implementation
- `SCRIPTS_REFERENCE.md` - Reference guide for all scripts in the scripts directory

### `scripts/`
Utility scripts for building and testing:
- `build.sh` - Builds the primary tokenizer
- `build_all.sh` - Builds all supported locales and the universal tokenizer (v2 API)
- `build_legacy.sh` - Builds the primary tokenizer using API v1 (legacy)
- `build_all_legacy.sh` - Builds all supported locales (API v1)
- `test.sh` - Tests default universal & Japanese tokenizers
- `test_all.sh` - Tests all built libraries
- `code-format.sh` - Formats code using `zig fmt`
- `lint-check.sh` - Checks source code using `zig ast-check`

### `src/`
Source code files:
- `fts5_icu.zig` - Entrypoint for FTS5 ICU tokenizers (v1 & v2 APIs)
- `tokenizer.zig` - Core tokenization logic & ICU word boundary iterator
- `rules.zig` - Locale-specific transliteration & normalization rule mappings
- `c_icu.zig` / `c_includes.h` - C interop bindings for ICU & SQLite APIs

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