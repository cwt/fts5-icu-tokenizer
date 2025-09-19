# FTS5 ICU Tokenizer - Default Implementation Update Summary

This document summarizes the changes made to make the FTS5 v2 implementation the default and preferred extension, with the v1 implementation moved to a legacy section.

## Changes Made

### 1. README.md Updates
- Completely rewritten to make the FTS5 v2 implementation the default
- Moved the v1 implementation to a "Legacy FTS5 v1 Implementation (Deprecated)" section
- Updated all examples to use the new default implementation
- Updated library names in examples (removed "_v2" suffix)

### 2. Build System Updates (CMakeLists.txt)
- Updated project version from 3.0 to 4.0
- Changed library naming:
  - New default implementation: `libfts5_icu*.so`
  - Legacy implementation: `libfts5_icu_legacy*.so`
- Updated installation order to install v2 first

### 3. Source Code Updates
- Kept both implementations:
  - `src/fts5_icu.c` - Legacy v1 implementation
  - `src/fts5_icu_v2.c` - FTS5 v2 implementation (now default)
- Both implementations are built, but v2 is now the default

### 4. Test File Updates
- Renamed test files to remove "_v2" suffix:
  - `tests/test_ja_tokenizer_v2.sql` → `tests/test_ja_tokenizer.sql`
  - `tests/test_universal_tokenizer_v2.sql` → `tests/test_universal_tokenizer.sql`
- Updated content to load the new default libraries

### 5. Script Updates
- Renamed scripts to remove "_v2" suffix:
  - `scripts/build_v2.sh` → `scripts/build.sh`
  - `scripts/test_v2.sh` → `scripts/test.sh`
  - `scripts/demo_v2.sh` → `scripts/demo.sh`
- Updated script content to reference the new default libraries
- Made all scripts executable

### 6. Documentation Updates
- Updated `docs/FTS5_V2_IMPLEMENTATION.md` to reflect that v2 is now the default
- Updated `docs/FTS5_COMPLIANCE_SUMMARY.md` to reflect current state
- Updated all references to make v2 the default implementation

## New File Structure

### Scripts
```
scripts/
├── build.sh           # Build script (formerly build_v2.sh)
├── build_all.sh       # Build all locales
├── build_test.sh      # Build test program
├── demo.sh            # Demo script (formerly demo_v2.sh)
├── run_test.sh        # Run test program
├── test_all.sh        # Test all locales
└── test.sh            # Test script (formerly test_v2.sh)
```

### Test Files
```
tests/
├── test_ar_tokenizer.sql
├── test_el_tokenizer.sql
├── test_he_tokenizer.sql
├── test_ja_tokenizer.sql      # Formerly test_ja_tokenizer_v2.sql
├── test_ko_tokenizer.sql
├── test_ru_tokenizer.sql
├── test_th_tokenizer.sql
├── test_universal_tokenizer.sql  # Formerly test_universal_tokenizer_v2.sql
└── test_zh_tokenizer.sql
```

### Built Libraries
```
build/
├── libfts5_icu.so              # Default universal tokenizer
├── libfts5_icu_ar.so           # Default Arabic tokenizer
├── libfts5_icu_el.so           # Default Greek tokenizer
├── libfts5_icu_he.so           # Default Hebrew tokenizer
├── libfts5_icu_ja.so           # Default Japanese tokenizer
├── libfts5_icu_ko.so           # Default Korean tokenizer
├── libfts5_icu_ru.so           # Default Russian tokenizer
├── libfts5_icu_th.so           # Default Thai tokenizer
├── libfts5_icu_zh.so           # Default Chinese tokenizer
└── libfts5_icu_legacy.so       # Legacy universal tokenizer
```

## Usage Changes

### New Default Usage (Recommended)
```sql
-- Load the default library
.load ./build/libfts5_icu.so

CREATE VIRTUAL TABLE documents USING fts5(
    content,
    tokenize = 'icu'
);
```

### Legacy Usage (Deprecated)
```sql
-- Load the legacy library
.load ./build/libfts5_icu_legacy.so

CREATE VIRTUAL TABLE documents USING fts5(
    content,
    tokenize = 'icu'
);
```

## Benefits of the Update

1. **Full FTS5 API Compliance**: The default implementation fully complies with the current FTS5 v2 API specifications
2. **Backward Compatibility**: Legacy implementation is still available for existing projects
3. **Clear Migration Path**: Simple library name change for users migrating from legacy to current implementation
4. **Future-Proof**: Default implementation uses current best practices and API
5. **Performance**: Default implementation includes all the performance improvements from the v2 API

## Migration Guide

For users of the legacy implementation who want to migrate to the current default implementation:

1. Change the library loading:
   ```sql
   -- Old (legacy)
   .load ./build/libfts5_icu.so
   
   -- New (default)
   .load ./build/libfts5_icu_legacy.so
   ```

2. No changes needed to SQL code - tokenizer names remain the same

The migration is simply swapping which library file you load, making it very straightforward for existing users to upgrade.