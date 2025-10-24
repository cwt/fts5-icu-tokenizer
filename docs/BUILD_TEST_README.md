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

### `build_all.sh`
Builds all supported locale-specific tokenizers and the universal tokenizer.

Usage:
```bash
./build_all.sh
```

This script will:
1. Build separate shared libraries for each locale with optimized rules
2. Place all libraries in the `build/` directory
3. Show progress and any warnings during the build process

### Building Individual Locales
You can also build individual locales using CMake directly:

```bash
# Create build directory
mkdir build
cd build

# Configure for a specific locale (e.g., Japanese)
cmake .. -DLOCALE=ja

# Build
make

# The resulting library will be named libfts5_icu_ja.so
```

## Test Scripts

### `test_all.sh`
Tests all built libraries with appropriate sample text.

Usage:
```bash
./test_all.sh
```

This script will:
1. Test the universal tokenizer with mixed language content
2. Test each locale-specific tokenizer with sample text in that language
3. Report success or failure for each test

### Testing Individual Locales
You can also test individual locales using the specific test scripts:

```bash
# Test Japanese tokenizer
sqlite3 < test_ja_tokenizer.sql

# Test Chinese tokenizer
sqlite3 < test_zh_tokenizer.sql
```

## Locale Aliases

For compatibility, the following locale aliases are supported:
- **cn** → **zh** (Chinese)
- **jp** → **ja** (Japanese)
- **kr** → **ko** (Korean)
- **iw** → **he** (Hebrew)
- **gr** → **el** (Greek)

When using these aliases, you'll see a warning message during the build process, and the resulting library will use the standard ICU locale code.

## Function Names

Each built library exports a function with a name matching the SQLite FTS5 extension convention:
- For locale `ja`: `sqlite3_ftsicuja_init`
- For locale `zh`: `sqlite3_ftsicuzh_init`
- For universal tokenizer: `sqlite3_ftsicu_init`

This ensures compatibility with SQLite's extension loading mechanism.

## Code Quality Scripts

The project includes scripts for maintaining code quality:

### `code-format.sh`
Formats all source code files using clang-format. Usage:
```bash
./scripts/code-format.sh
```

### `lint-check.sh`
Performs static code analysis using cppcheck. Usage:
```bash
./scripts/lint-check.sh
```

For more information about the FTS5 v2 API implementation, see [docs/FTS5_API_IMPLEMENTATION.md](docs/FTS5_API_IMPLEMENTATION.md).

For a complete reference of all available scripts, see [docs/SCRIPTS_REFERENCE.md](docs/SCRIPTS_REFERENCE.md).