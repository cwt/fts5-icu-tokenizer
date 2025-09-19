# FTS5 ICU Tokenizer - README Updates Summary

This document summarizes the updates made to the README.md file to reflect the correct library naming conventions after making the FTS5 v2 implementation the default.

## Changes Made to README.md

### 1. Windows Build Output Names
**Old:**
```
This will create `fts5_icu_v2_th.dll` and register the tokenizer as `icu_th`.
```

**New:**
```
This will create `fts5_icu_th.dll` and register the tokenizer as `icu_th`.
```

### 2. Windows Library Names
**Old:**
```
After successful compilation, you'll find `fts5_icu_v2.dll` (or `fts5_icu_v2_xx.dll` for locale-specific builds) in the `build\Release` directory.
```

**New:**
```
After successful compilation, you'll find `fts5_icu.dll` (or `fts5_icu_xx.dll` for locale-specific builds) in the `build\Release` directory.
```

### 3. Windows Load Commands
**Old:**
```sql
.load fts5_icu_v2.dll
```

**New:**
```sql
.load fts5_icu.dll
```

### 4. Windows Full Path Example
**Old:**
```
When you use a full path to load the extension (e.g., `.load ./build/Release/fts5_icu_v2.dll`), Windows may not automatically search for the required ICU DLLs
```

**New:**
```
When you use a full path to load the extension (e.g., `.load ./build/Release/fts5_icu.dll`), Windows may not automatically search for the required ICU DLLs
```

### 5. Linux/Unix Load Commands for Locale-Specific Tokenizers
**Old:**
```sql
.load ./build/libfts5_icu_v2_th.so
```

**New:**
```sql
.load ./build/libfts5_icu_th.so
```

### 6. Linux/Unix Load Commands for Universal Tokenizer
**Old:**
```sql
.load ./build/libfts5_icu_v2.so
```

**New:**
```sql
.load ./build/libfts5_icu.so
```

### 7. Build Examples
**Old:**
```
# This will show a warning and build libfts5_icu_v2_zh.so
# This will build libfts5_icu_v2_zh.so directly without warning
# These will both build libfts5_icu_v2_ko.so without any warnings
```

**New:**
```
# This will show a warning and build libfts5_icu_zh.so
# This will build libfts5_icu_zh.so directly without warning
# These will both build libfts5_icu_ko.so without any warnings
```

### 8. Test File Names
**Old:**
- `tests/test_ar_tokenizer_v2.sql`
- `tests/test_el_tokenizer_v2.sql`
- `tests/test_he_tokenizer_v2.sql`
- `tests/test_ja_tokenizer_v2.sql`
- `tests/test_ko_tokenizer_v2.sql`
- `tests/test_ru_tokenizer_v2.sql`
- `tests/test_th_tokenizer_v2.sql`
- `tests/test_zh_tokenizer_v2.sql`
- `tests/test_universal_tokenizer_v2.sql`

**New:**
- `tests/test_ar_tokenizer.sql`
- `tests/test_el_tokenizer.sql`
- `tests/test_he_tokenizer.sql`
- `tests/test_ja_tokenizer.sql`
- `tests/test_ko_tokenizer.sql`
- `tests/test_ru_tokenizer.sql`
- `tests/test_th_tokenizer.sql`
- `tests/test_zh_tokenizer.sql`
- `tests/test_universal_tokenizer.sql`

### 9. Test Commands
**Old:**
```bash
sqlite3 < tests/test_ja_tokenizer_v2.sql
sqlite3 < tests/test_universal_tokenizer_v2.sql
```

**New:**
```bash
sqlite3 < tests/test_ja_tokenizer.sql
sqlite3 < tests/test_universal_tokenizer.sql
```

### 10. Legacy Implementation Load Command
**Old:**
```sql
-- Load the v1 library instead of the v2
.load ./build/libfts5_icu.so
```

**New:**
```sql
-- Load the legacy v1 library
.load ./build/libfts5_icu_legacy.so
```

## Summary of Library Naming

### Current Build Output:
1. **Default (v2) implementations**:
   - Universal: `libfts5_icu.so` (or `fts5_icu.dll` on Windows)
   - Locale-specific: `libfts5_icu_ar.so`, `libfts5_icu_el.so`, etc.

2. **Legacy (v1) implementations**:
   - Universal: `libfts5_icu_legacy.so` (or `fts5_icu_legacy.dll` on Windows)
   - Locale-specific: `libfts5_icu_legacy_ar.so`, `libfts5_icu_legacy_el.so`, etc.

### Usage Examples:

**Default (Recommended)**:
```sql
.load ./build/libfts5_icu.so
CREATE VIRTUAL TABLE documents USING fts5(content, tokenize = 'icu');
```

**Legacy (Deprecated)**:
```sql
.load ./build/libfts5_icu_legacy.so
CREATE VIRTUAL TABLE documents USING fts5(content, tokenize = 'icu');
```

All documentation now correctly reflects that the v2 implementation is the default and uses the simpler naming convention without the `_v2` suffix, while the legacy v1 implementation uses the `_legacy` suffix.