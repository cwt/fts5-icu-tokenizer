# FTS5 ICU Tokenizer - Single Implementation Approach

This document summarizes the changes made to simplify the project to a single FTS5 v2 API implementation, removing the legacy v1 implementation entirely.

## Changes Made

### 1. Source Code Updates
- Consolidated to a single implementation in `src/fts5_icu.c` that uses the FTS5 v2 API
- Removed `src/fts5_icu_v2.c` and `src/fts5_icu_legacy.c`
- Simplified codebase to single unified approach

### 2. Build System Updates (CMakeLists.txt)
- Updated project version from 3.0 to 4.0
- Simplified library building to a single target:
  - Current implementation: `libfts5_icu*.so`

### 3. Test File Updates
- Updated `tests/test_universal_legacy_with_th_zh.sql` to load the current library
- Removed references to legacy implementation

### 4. Documentation Updates
- Updated documentation to reflect single implementation approach
- Removed all legacy implementation references

## New File Structure

### Built Libraries
```
build/
├── libfts5_icu.so              # Universal tokenizer (v2 API)
├── libfts5_icu_ar.so           # Arabic tokenizer (v2 API)
├── libfts5_icu_el.so           # Greek tokenizer (v2 API)
├── libfts5_icu_he.so           # Hebrew tokenizer (v2 API)
├── libfts5_icu_ja.so           # Japanese tokenizer (v2 API)
├── libfts5_icu_ko.so           # Korean tokenizer (v2 API)
├── libfts5_icu_ru.so           # Russian tokenizer (v2 API)
├── libfts5_icu_th.so           # Thai tokenizer (v2 API)
└── libfts5_icu_zh.so           # Chinese tokenizer (v2 API)
```

## Usage

### Current Implementation (Only Available)
```sql
-- Load the library
.load ./build/libfts5_icu.so

CREATE VIRTUAL TABLE documents USING fts5(
    content,
    tokenize = 'icu'
);
```

## Benefits of the Update

1. **Full FTS5 API Compliance**: The implementation fully complies with the current FTS5 v2 API specifications
2. **Simplified Codebase**: Single implementation reduces maintenance overhead
3. **Modern Approach**: Uses current best practices and API
4. **Performance**: Implementation includes all the performance improvements from the v2 API
5. **Internationalization**: v2 API provides locale-aware tokenization capabilities