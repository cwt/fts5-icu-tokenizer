# FTS5 ICU Tokenizer for SQLite - Implementation

This project uses the FTS5 v2 API implementation, which complies with the FTS5 v2 API specifications and provides enhanced internationalization capabilities.

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

## Files

- `fts5_icu.c` - The main implementation file that uses the FTS5 v2 API
- `CMakeLists.txt` - Build configuration that builds the v2 implementation

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

The implementation provides better compliance with the FTS5 specification and is the recommended approach.