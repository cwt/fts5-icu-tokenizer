# FTS5 ICU Tokenizer for SQLite - FTS5 API Implementation

This project uses the FTS5 v2 API implementation, which fully complies with the FTS5 v2 API specifications and provides enhanced internationalization capabilities.

## Advantages of the FTS5 v2 API

The FTS5 v2 API provides several important advantages over the v1 API:

### 1. Locale Support
The most significant enhancement in the v2 API is the addition of `pLocale` and `nLocale` parameters to the `xTokenize` method. This allows tokenizers to:
- Receive locale information for text processing
- Adjust tokenization behavior based on language-specific rules
- Support internationalization more effectively

### 2. Version Tracking
The v2 API includes an `iVersion` field that explicitly identifies the API version, making it easier to manage compatibility between different tokenizer implementations.

### 3. Better Internationalization
With locale support, v2 tokenizers can implement language-specific tokenization rules, such as:
- Language-specific stemming
- Locale-aware case folding
- Language-specific stop word handling

### 4. Enhanced Function Signatures
The v2 API provides proper function signatures that comply with current FTS5 documentation, ensuring better integration with SQLite's FTS5 subsystem.

## API Structure Differences

### v1 API Structure (fts5_tokenizer)
```c
typedef struct fts5_tokenizer fts5_tokenizer;
struct fts5_tokenizer {
  int (*xCreate)(void*, const char **azArg, int nArg, Fts5Tokenizer **ppOut);
  void (*xDelete)(Fts5Tokenizer*);
  int (*xTokenize)(Fts5Tokenizer*, 
      void *pCtx,
      int flags,
      const char *pText, int nText,
      int (*xToken)(
        void *pCtx,
        int tflags,
        const char *pToken,
        int nToken,
        int iStart,
        int iEnd
      )
  );
};
```

### v2 API Structure (fts5_tokenizer_v2)
```c
typedef struct fts5_tokenizer_v2 fts5_tokenizer_v2;
struct fts5_tokenizer_v2 {
  int iVersion;             /* Currently always 2 */
  int (*xCreate)(void*, const char **azArg, int nArg, Fts5Tokenizer **ppOut);
  void (*xDelete)(Fts5Tokenizer*);
  int (*xTokenize)(Fts5Tokenizer*, 
      void *pCtx,
      int flags,
      const char *pText, int nText, 
      const char *pLocale, int nLocale,  /* NEW in v2 */
      int (*xToken)(
        void *pCtx,
        int tflags,
        const char *pToken,
        int nToken,
        int iStart,
        int iEnd
      )
  );
};
```

The addition of the `pLocale` and `nLocale` parameters in the `xTokenize` method is the key enhancement that enables better internationalization support in the v2 API.

## Implementation Details

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

## Key Features of Implementation

1. **FTS5 v2 API Compliance**:
   - Uses the `fts5_tokenizer_v2` structure with version field set to 2
   - Implements the correct function signatures as specified in the FTS5 documentation
   - Uses `xCreateTokenizer_v2` for registration

2. **Proper Function Signatures**:
   - `xCreate` function signature matches FTS5 requirements exactly
   - `xTokenize` function includes all required parameters including locale support
   - Callback function signature includes all required parameters

3. **Enhanced Error Handling**:
   - Proper version checking for FTS5 API availability
   - Better error reporting for registration failures
   - Proper handling of FTS5_TOKENIZE_* flags

4. **Enhanced Functionality**:
   - Proper locale support in tokenization
   - Correct handling of FTS5 flags
   - Better error reporting

5. **Simplified Architecture**:
   - Single implementation reduces maintenance overhead
   - Clear and focused codebase
   - Easier to understand and modify

6. **Internationalization**:
   - Full support for language-specific tokenization
   - Enhanced multi-language text processing capabilities

## Function Signatures

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

## Building the Implementation

The implementation is built automatically when you build the project. It creates:
- Universal tokenizer library (fts5_icu.so)
- Locale-specific tokenizer libraries (fts5_icu_[locale].so)

To build for a specific locale:
```bash
mkdir build
cd build
cmake .. -DLOCALE=ja
cmake --build .
```

## Testing the Implementation

You can test the implementation using the provided SQL test scripts:

```bash
# Build the project
mkdir build && cd build && cmake .. && cmake --build .

# Test the implementation
sqlite3 < tests/test_universal_legacy_with_th_zh.sql
```

## Code Quality

The project maintains code quality through formatting and linting tools:

- **Code Formatting**: Use `./scripts/code-format.sh` to ensure consistent code style
- **Static Analysis**: Use `./scripts/lint-check.sh` to detect potential issues

The implementation provides better compliance with the FTS5 specification and is the recommended approach.