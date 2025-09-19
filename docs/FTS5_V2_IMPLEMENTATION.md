# FTS5 ICU Tokenizer for SQLite - Implementation

This project now uses the FTS5 v2 API implementation as the default, which complies with the FTS5 v2 API specifications and provides enhanced capabilities over the legacy v1 API.

The legacy v1 implementation is still available for backward compatibility but is deprecated.

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

- `fts5_icu_v2.c` - The main implementation file that uses the FTS5 v2 API
- `CMakeLists.txt` - Updated build configuration that builds both v1 and v2 versions
- `test_ja_tokenizer_v2.sql` - Test script for the Japanese locale-specific v2 tokenizer
- `test_universal_tokenizer_v2.sql` - Test script for the universal v2 tokenizer

## Key Improvements in v2 Implementation

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

## Building the v2 Implementation

The v2 implementation is built automatically when you build the project. It creates two sets of libraries:
- Original implementation (fts5_icu*.so)
- v2 implementation (fts5_icu_v2*.so)

To build for a specific locale:
```bash
mkdir build
cd build
cmake .. -DLOCALE=ja
cmake --build .
```

## Testing the v2 Implementation

You can test the v2 implementation using the provided SQL test scripts:

```bash
# Test the Japanese locale-specific v2 tokenizer
sqlite3 < tests/test_ja_tokenizer_v2.sql

# Test the universal v2 tokenizer
sqlite3 < tests/test_universal_tokenizer_v2.sql
```

## Migration from v1 to v2

If you're currently using the v1 implementation and want to migrate to v2:

1. Update your `.load` statements to use the v2 library:
   ```sql
   -- Old
   .load ./build/libfts5_icu_ja.so
   
   -- New
   .load ./build/libfts5_icu_v2_ja.so
   ```

2. The tokenizer names remain the same, so your `CREATE VIRTUAL TABLE` statements don't need to change:
   ```sql
   CREATE VIRTUAL TABLE documents USING fts5(
       content,
       tokenize = 'icu_ja'  -- Same name for both v1 and v2
   );
   ```

The v2 implementation provides better compliance with the FTS5 specification and is recommended for new projects.