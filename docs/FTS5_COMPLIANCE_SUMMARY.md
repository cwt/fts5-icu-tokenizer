# FTS5 ICU Tokenizer - FTS5 API Compliance

This document summarizes how the FTS5 ICU Tokenizer project implements full compliance with the SQLite FTS5 custom tokenizer documentation using the FTS5 v2 API.

## Implementation

### Single FTS5 v2 Implementation (fts5_icu.c)

The project now uses a single implementation file that fully complies with the FTS5 v2 API:
- Uses the `fts5_tokenizer_v2` structure with `iVersion` set to 2
- Implements correct function signatures for all required functions
- Properly handles locale-specific parameters in `xTokenize`
- Uses the enhanced callback function signature

### Simplified Build System

The build system was simplified to compile a single implementation:
- Single source file `src/fts5_icu.c` 
- Single build target `fts5_icu`
- Updated linking for the unified implementation

### Enhanced Function Signatures

All function signatures match FTS5 v2 requirements:

#### xCreate Function
```c
static int icuCreate(
  void *pCtx,
  const char **azArg,
  int nArg,
  Fts5Tokenizer **ppOut
)
```

#### xTokenize Function
```c
static int icuTokenize(
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

### Updated Registration Process

The registration process uses the v2 API:
```c
fts5_tokenizer_v2 tokenizer = {
  .iVersion = 2,
  .xCreate = icuCreate,
  .xDelete = icuDelete,
  .xTokenize = icuTokenize
};

// Use the v2 registration method
int rc = pFts5Api->xCreateTokenizer_v2(pFts5Api, TOKENIZER_NAME, NULL, &tokenizer, NULL);
```

### Proper Error Handling

Enhanced error handling is implemented:
- Version checking to ensure FTS5 v2 API is available
- Better error reporting for registration failures
- Proper handling of FTS5_TOKENIZE_* flags

## Benefits of the Implementation

1. **Full FTS5 API Compliance**:
   - Complies with current SQLite FTS5 documentation
   - Uses the latest API features and capabilities

2. **Enhanced Functionality**:
   - Proper locale support in tokenization
   - Correct handling of FTS5 flags
   - Better error reporting

3. **Simplified Architecture**:
   - Single implementation reduces maintenance overhead
   - Clear and focused codebase
   - Easier to understand and modify

4. **Internationalization**:
   - Full support for language-specific tokenization
   - Enhanced multi-language text processing capabilities

## Testing

The implementation is tested with:
- `tests/test_universal_legacy_with_th_zh.sql` - Tests universal tokenizer with various languages