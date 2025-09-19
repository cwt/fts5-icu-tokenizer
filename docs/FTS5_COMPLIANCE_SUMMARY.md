# FTS5 ICU Tokenizer - FTS5 API Compliance

This document summarizes how the FTS5 ICU Tokenizer project implements full compliance with the SQLite FTS5 custom tokenizer documentation using the FTS5 v2 API as the default implementation.

## Issues with Legacy Implementation

The original implementation had several deviations from the FTS5 v2 API specifications:

1. **Outdated API Usage**:
   - Used the older `fts5_tokenizer` structure instead of `fts5_tokenizer_v2`
   - Missing version field in the tokenizer structure

2. **Incorrect Function Signatures**:
   - The `xTokenize` function signature was missing required parameters:
     - `pLocale` and `nLocale` parameters for locale-specific tokenization
     - Improper handling of FTS5_TOKENIZE_* flags
   - Callback function signature didn't match FTS5 requirements

3. **Registration Process**:
   - Used the older `xCreateTokenizer` method instead of `xCreateTokenizer_v2`

## Implementation

### 1. FTS5 v2 Implementation (fts5_icu_v2.c)

A new implementation file was created that fully complies with the FTS5 v2 API:
- Uses the `fts5_tokenizer_v2` structure with `iVersion` set to 2
- Implements correct function signatures for all required functions
- Properly handles locale-specific parameters in `xTokenize`
- Uses the enhanced callback function signature

### 2. Updated CMake Build System

The build system was updated to compile both the original and v2 implementations:
- Added new source file `src/fts5_icu_v2.c`
- Created separate build target `fts5_icu_v2`
- Configured proper compile definitions for the v2 implementation
- Updated linking to include both versions

### 3. Enhanced Function Signatures

All function signatures were updated to match FTS5 v2 requirements:

#### xCreate Function
```c
static int icuCreate_v2(
  void *pCtx,
  const char **azArg,
  int nArg,
  Fts5Tokenizer **ppOut
)
```

#### xTokenize Function
```c
static int icuTokenize_v2(
  Fts5Tokenizer *pTok,
  void *pCtx,
  int flags,            // FTS5_TOKENIZE_* flags
  const char *pText, 
  int nText,
  const char *pLocale,  // Locale support
  int nLocale,
  int (*xToken)(
    void *pCtx,
    int tflags,         // FTS5_TOKEN_* flags
    const char *pToken,
    int nToken,
    int iStart,
    int iEnd
  )
)
```

### 4. Updated Registration Process

The registration process was updated to use the v2 API:
```c
fts5_tokenizer_v2 tokenizer = {
  .iVersion = 2,
  .xCreate = icuCreate_v2,
  .xDelete = icuDelete_v2,
  .xTokenize = icuTokenize_v2
};

// Use the v2 registration method
int rc = pFts5Api->xCreateTokenizer_v2(pFts5Api, TOKENIZER_NAME, NULL, &tokenizer, NULL);
```

### 5. Added Proper Error Handling

Enhanced error handling was implemented:
- Version checking to ensure FTS5 v2 API is available
- Better error reporting for registration failures
- Proper handling of FTS5_TOKENIZE_* flags

### 6. Created Test Files

New test files were created to verify the v2 implementation:
- `tests/test_ja_tokenizer_v2.sql` - Japanese locale-specific tests
- `tests/test_universal_tokenizer_v2.sql` - Universal tokenizer tests

### 7. Updated Documentation

Documentation was added to help users understand and migrate to the v2 implementation:
- `docs/FTS5_V2_IMPLEMENTATION.md` - Detailed documentation of the v2 implementation
- Updated README.md to mention the v2 implementation
- Created build and test scripts for the v2 implementation

## Benefits of the FTS5 Implementation

1. **Full FTS5 API Compliance**:
   - Complies with current SQLite FTS5 documentation
   - Uses the latest API features and capabilities

2. **Enhanced Functionality**:
   - Proper locale support in tokenization
   - Correct handling of FTS5 flags
   - Better error reporting

3. **Backward Compatibility**:
   - Maintains the same tokenizer names as the original implementation
   - Existing SQL code doesn't need to be changed
   - Both implementations can coexist

4. **Future-Proof**:
   - Built using the current FTS5 API specifications
   - Ready for any future enhancements to the FTS5 API

## Migration Guide

For users of the legacy v1 implementation who want to migrate to the current implementation:

1. **Update Library Loading**:
   ```sql
   -- Old
   .load ./build/libfts5_icu_ja.so
   
   -- New
   .load ./build/libfts5_icu_v2_ja.so
   ```

2. **No Changes to SQL Code**:
   ```sql
   -- This remains the same
   CREATE VIRTUAL TABLE documents USING fts5(
       content,
       tokenize = 'icu_ja'
   );
   ```

The v2 implementation is recommended for new projects and provides a path for existing projects to upgrade to full FTS5 API compliance.