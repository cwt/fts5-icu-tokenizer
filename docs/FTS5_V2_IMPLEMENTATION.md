# FTS5 ICU Tokenizer for SQLite - Implementation

This project now uses the FTS5 v2 API implementation as the default, which complies with the FTS5 v2 API specifications.

The legacy v1 implementation is still available for backward compatibility but is deprecated.

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