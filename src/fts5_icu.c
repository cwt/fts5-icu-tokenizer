/**
 * @file fts5_icu.c
 * @brief A dynamic FTS5 tokenizer for SQLite that uses ICU to segment text
 *		based on a locale provided at compile time.
 *
 * This version is written in pure C for maximum stability and direct
 * control over memory management, making it suitable for high-volume,
 * long-running systems.
 *
 * Updated to comply with FTS5 v2 API specifications.
 * The user defines only:
 *   -DTOKENIZER_LOCALE="ja"   (or "zh", "th", etc.)
 *
 * All other settings (TOKENIZER_NAME, INIT_LOCALE_SUFFIX, ICU rules)
 * are derived automatically at compile time.
 */

#include "fts5_icu.h"

// Define the fts5_api pointer before use - this must come after sqlite3ext.h is
// included
SQLITE_EXTENSION_INIT1

// Helper function to get the FTS5 API pointer from the database connection.
static fts5_api* fts5_api_from_db(sqlite3* db) {
    fts5_api* pApi = 0;
    sqlite3_stmt* pStmt = 0;
    if (sqlite3_prepare_v2(db, "SELECT fts5(?)", -1, &pStmt, 0) == SQLITE_OK) {
        sqlite3_bind_pointer(pStmt, 1, &pApi, "fts5_api_ptr", 0);
        sqlite3_step(pStmt);
    }
    sqlite3_finalize(pStmt);
    return pApi;
}

// Forward declarations for v2 API
static int icuCreate(void*, const char**, int, Fts5Tokenizer**);
static void icuDelete(Fts5Tokenizer*);
static int icuTokenize(Fts5Tokenizer*, void*, int, const char*, int, const char*, int,
                       int (*)(void*, int, const char*, int, int, int));

// Main tokenizer struct for v2 API
typedef struct IcuTokenizerV2 {
    fts5_tokenizer_v2 fts_tokenizer_v2;  // Must be first member for v2 API
    UBreakIterator* pBreakIterator;
    UTransliterator* pTransliterator;
} IcuTokenizerV2;

// ========================================================================
// === FTS5 TOKENIZER CREATION CALLBACK (xCreate) =========================
// ========================================================================

static int icuCreate(void* pCtx, const char** azArg, int nArg, Fts5Tokenizer** ppOut) {
    UNUSED_PARAMETER(pCtx);
    UNUSED_PARAMETER(azArg);
    UNUSED_PARAMETER(nArg);

    IcuTokenizerV2* pTokenizer = (IcuTokenizerV2*)sqlite3_malloc(sizeof(IcuTokenizerV2));
    if (!pTokenizer)
        return SQLITE_NOMEM;
    memset(pTokenizer, 0, sizeof(IcuTokenizerV2));

    UErrorCode status = U_ZERO_ERROR;

    // Open break iterator with compile-time locale
    pTokenizer->pBreakIterator = ubrk_open(UBRK_WORD, TOKENIZER_LOCALE, NULL, 0, &status);
    if (U_FAILURE(status)) {
        // Avoid fprintf to stderr in SQLite extension; instead, just
        // return error
        ubrk_close(pTokenizer->pBreakIterator);
        sqlite3_free(pTokenizer);
        return SQLITE_ERROR;
    }

    // Use compile-time selected rule
    pTokenizer->pTransliterator = utrans_openU(ICU_TOKENIZER_RULES, -1, UTRANS_FORWARD, NULL, 0,
                                               NULL, &status);
    if (U_FAILURE(status)) {
        // Avoid fprintf to stderr in SQLite extension; instead, just
        // return error
        ubrk_close(pTokenizer->pBreakIterator);
        sqlite3_free(pTokenizer);
        return SQLITE_ERROR;
    }

    // Setup vtable for v2 API
    pTokenizer->fts_tokenizer_v2.iVersion = 2;
    pTokenizer->fts_tokenizer_v2.xCreate = icuCreate;
    pTokenizer->fts_tokenizer_v2.xDelete = icuDelete;
    pTokenizer->fts_tokenizer_v2.xTokenize = icuTokenize;

    *ppOut = (Fts5Tokenizer*)pTokenizer;
    return SQLITE_OK;
}

// ========================================================================
// === FTS5 TOKENIZER DELETION CALLBACK (xDelete) =========================
// ========================================================================

static void icuDelete(Fts5Tokenizer* pTok) {
    if (!pTok)
        return;
    IcuTokenizerV2* pTokenizer = (IcuTokenizerV2*)pTok;
    ubrk_close(pTokenizer->pBreakIterator);
    utrans_close(pTokenizer->pTransliterator);
    sqlite3_free(pTokenizer);
}

/**
 * @brief Allocates and validates buffer sizes for UTF-8 to UTF-16 conversion
 *
 * This function handles the complex memory allocation with overflow checks
 * required for safe Unicode conversion.
 *
 * @param nText The length of input UTF-8 text
 * @param[out] utf16_text_buffer Pointer to hold allocated UTF-16 buffer
 * @param[out] byte_offset_map Pointer to hold allocated offset mapping array
 * @param[out] utf16_buffer_size The calculated size of the UTF-16 buffer
 * @param[out] map_buffer_size The calculated size of the offset map
 * @return SQLITE_OK on success, appropriate error code on failure
 */
static int allocate_conversion_buffers(int nText, UChar** utf16_text_buffer,
                                       int32_t** byte_offset_map, int32_t* utf16_buffer_size,
                                       int32_t* map_buffer_size) {
    // Calculate required buffer sizes with safety margins
    // For UTF-8 to UTF-16 conversion, worst case is 2x space for surrogate
    // pairs However, most characters will be single UTF-16 code units, so
    // we use a reasonable upper bound

    // Check for integer overflow in buffer size calculation
    if (nText > (INT32_MAX - 1) / 2) {
        return SQLITE_ERROR;  // Prevent integer overflow
    }
    *utf16_buffer_size = nText * 2 + 1;

    if (*utf16_buffer_size > (INT32_MAX - 2) / (int32_t)sizeof(UChar)) {
        return SQLITE_ERROR;  // Prevent integer overflow in
                              // multiplication with sizeof(UChar)
    }

    // Allocate UTF-16 text buffer
    *utf16_text_buffer = (UChar*)sqlite3_malloc(*utf16_buffer_size * sizeof(UChar));
    if (!*utf16_text_buffer)
        return SQLITE_NOMEM;

    // Check for integer overflow in pMap size calculation
    if (nText > (INT32_MAX - 2) / 2) {
        sqlite3_free(*utf16_text_buffer);
        return SQLITE_ERROR;  // Prevent integer overflow
    }
    *map_buffer_size = nText * 2 + 2;

    if (*map_buffer_size > INT32_MAX / (int32_t)sizeof(int32_t)) {
        sqlite3_free(*utf16_text_buffer);
        return SQLITE_ERROR;  // Prevent integer overflow in
                              // multiplication with sizeof(int32_t)
    }

    // Allocate byte offset mapping array
    *byte_offset_map = (int32_t*)sqlite3_malloc(*map_buffer_size * sizeof(int32_t));
    if (!*byte_offset_map) {
        sqlite3_free(*utf16_text_buffer);
        return SQLITE_NOMEM;
    }

    return SQLITE_OK;
}

/**
 * @brief Validates buffer size against actual code point count
 *
 * This function performs a safety check to ensure our buffer size estimates
 * are adequate for the actual UTF-8 content.
 *
 * @param pText Input UTF-8 text
 * @param nText Length of input text
 * @param utf16_buffer_size Size of allocated UTF-16 buffer
 * @param pUText Allocated UTF-16 buffer to validate
 * @param pMap Allocated offset map to validate
 * @return SQLITE_OK if validation passes, error code otherwise
 */
static int validate_buffer_size(const char* pText, int nText, int32_t utf16_buffer_size,
                                UChar* pUText, int32_t* pMap) {
    // Count the actual number of Unicode code points to validate our buffer
    // size assumption
    int32_t actualCodePointCount = 0;
    int32_t tempU8 = 0;
    UErrorCode tempStatus = U_ZERO_ERROR;

    while (tempU8 < nText) {
        UChar32 tempC;
        int32_t nextPos = tempU8;
        U8_NEXT(pText, nextPos, nText, tempC);
        if (U_FAILURE(tempStatus) || nextPos <= tempU8)
            break;  // Invalid UTF-8 sequence
        actualCodePointCount++;
        tempU8 = nextPos;
    }

    // Verify our buffer size assumption against actual code point count
    // Add buffer for potential surrogate pairs (each code point could need
    // 2 UChar)
    if (actualCodePointCount > utf16_buffer_size / 2) {
        sqlite3_free(pUText);
        sqlite3_free(pMap);
        return SQLITE_ERROR;  // Prevent buffer overflow
    }

    return SQLITE_OK;
}

/**
 * @brief Converts UTF-8 text to UTF-16 with byte offset mapping
 *
 * This function performs the core UTF-8 to UTF-16 conversion while building
 * a mapping between UTF-16 positions and original UTF-8 byte positions.
 *
 * @param pText Input UTF-8 text
 * @param nText Length of input text
 * @param pUText Pre-allocated UTF-16 buffer
 * @param utf16Size Size of UTF-16 buffer
 * @param pMap Pre-allocated offset mapping array
 * @return The number of UTF-16 code units written, or negative on error
 */
static int32_t convert_utf8_to_utf16_with_mapping(const char* pText, int nText, UChar* pUText,
                                                  int32_t utf16Size, int32_t* pMap) {
    // Convert UTF-8 → UTF-16 and build byte offset map
    int32_t utf16_pos = 0;
    int32_t utf8_pos = 0;

    while (utf8_pos < nText && utf16_pos < utf16Size) {
        UChar32 unicode_char;
        int32_t original_utf8_pos = utf8_pos;  // Save position BEFORE U8_NEXT

        U8_NEXT(pText, utf8_pos, nText, unicode_char);

        // Check for invalid UTF-8 sequence - if we get a replacement
        // character (0xFFFD) and it's not actually a valid character
        // that happens to map to 0xFFFD, and if we haven't reached the
        // end of the string
        if (unicode_char == 0xFFFD && utf8_pos > 0 && utf8_pos <= nText) {
            // Check if this is a genuine error by looking at the
            // byte that caused it If the byte isn't at the expected
            // position or is a continuation byte in wrong place
            unsigned char potential_error_byte = pText[utf8_pos - 1];
            if (potential_error_byte != 0) {  // If we have a non-null byte that caused
                                              // 0xFFFD
                return -1;                    // Error indicator
            }
        }

        // Bounds check to ensure we have enough space for potentially
        // two UChar values (for surrogate pairs)
        if (utf16_pos + 1 >= utf16Size) {
            return -1;  // Error indicator - prevent buffer overflow
        }

        // Store the original byte position BEFORE U16_APPEND modifies
        // utf16_pos
        int32_t original_utf16_pos = utf16_pos;  // Save position BEFORE
                                                 // U16_APPEND
        UBool isError = 0;
        U16_APPEND(pUText, utf16_pos, utf16Size, unicode_char, isError);
        if (isError) {
            return -1;  // Error indicator
        }

        // Now assign the byte position mapping using saved original
        // positions
        if (original_utf16_pos >= 0 &&
            original_utf16_pos < utf16Size /* assuming map size is similar */) {
            pMap[original_utf16_pos] = original_utf8_pos;  // Map to the start of the
                                                           // UTF-8 character
        }

        // For surrogate pairs, we adjust the byte mapping
        if (unicode_char > 0xFFFF && original_utf16_pos + 1 >= 0 &&
            original_utf16_pos + 1 < utf16Size /* assuming map size */) {
            pMap[original_utf16_pos + 1] = original_utf8_pos;  // Second half of
                                                               // surrogate pair maps to
                                                               // same UTF-8 start
        }

        // Check bounds again after U16_APPEND has updated utf16_pos
        if (utf16_pos >= utf16Size)
            break;
    }

    // Bounds check before final assignment to pMap
    if (utf16_pos >= 0 && utf16_pos < utf16Size /* assuming map size */) {
        pMap[utf16_pos] = nText;
    }

    return utf16_pos;  // Return the number of UTF-16 code units written
}

/**
 * @brief Process a single token found by the break iterator
 *
 * This function handles the ICU transliteration and normalization of a single
 * token identified by the break iterator, then calls the callback function.
 *
 * @param pTokenizer The ICU tokenizer context
 * @param pUText The UTF-16 text buffer
 * @param pMap The byte position mapping array
 * @param iPrev Start position of the token in the UTF-16 buffer
 * @param iNext End position of the token in the UTF-16 buffer
 * @param pCtx Context for the callback function
 * @param xToken Callback function to pass the processed token to
 * @param wordStatus Status from the break iterator indicating token type
 * @param[in,out] buf Dynamic buffer for intermediate processing
 * @param[in,out] nBuf Size of the intermediate buffer
 * @param[in,out] dest Destination buffer for UTF-8 output
 * @param[in,out] nDest Size of the destination buffer
 * @return SQLITE_OK on success, appropriate error code on failure
 */
static int process_single_token(IcuTokenizerV2* pTokenizer, UChar* pUText, const int32_t* pMap,
                                int32_t iPrev, int32_t iNext, void* pCtx,
                                int (*xToken)(void*, int, const char*, int, int, int),
                                int32_t wordStatus, UChar** buf, int32_t* nBuf, char** dest,
                                int32_t* nDest) {
    int result = SQLITE_OK;

    // Check if this token is of interest (not a "none" type)
    if (wordStatus >= UBRK_WORD_NONE && wordStatus < UBRK_WORD_NONE_LIMIT) {
        return SQLITE_OK;  // Skip this token, continue processing
    }

    // Bounds checking for pMap array access
    if (iPrev < 0 || iPrev >= INT32_MAX / 2 || iNext < 0 || iNext >= INT32_MAX / 2) {
        return SQLITE_ERROR;
    }

    int32_t iStartByte = pMap[iPrev];
    int32_t iEndByte = pMap[iNext];
    int nTokenByte = iEndByte - iStartByte;
    if (nTokenByte <= 0) {
        return SQLITE_OK;  // Skip empty tokens
    }

    // Process the token
    int32_t nSrc = iNext - iPrev;

    // Grow buffer if needed for transliteration
    // Use a more conservative estimate for buffer size to handle complex
    // ICU transformations Check for integer overflow before multiplication
    int32_t requiredBufSize = 0;
    if (nSrc > (INT32_MAX - 2048) / 6) {
        return SQLITE_ERROR;  // Prevent integer overflow
    }
    requiredBufSize = (nSrc * 6) + 2048;  // Increased multiplier to handle
                                          // complex transformations
    if (*nBuf < requiredBufSize) {
        // Check for integer overflow in the multiplication with
        // sizeof(UChar)
        if (requiredBufSize > (INT32_MAX / sizeof(UChar))) {
            return SQLITE_ERROR;  // Prevent integer overflow
        }
        UChar* newBuf = (UChar*)sqlite3_realloc(*buf, requiredBufSize * sizeof(UChar));
        if (!newBuf) {
            return SQLITE_NOMEM;
        }
        *buf = newBuf;
        *nBuf = requiredBufSize;
    }

    // Ensure we don't exceed buffer bounds when copying
    int32_t copyLen = (nSrc < *nBuf) ? nSrc : (*nBuf - 1);
    u_strncpy(*buf, pUText + iPrev, copyLen);
    (*buf)[copyLen] = 0;  // Null terminate for safety

    // Validate the source buffer before transliteration
    int32_t srcLength = iNext - iPrev;
    if (srcLength <= 0 || srcLength >= *nBuf) {
        return SQLITE_ERROR;
    }

    UErrorCode status = U_ZERO_ERROR;
    int32_t limit = copyLen;
    utrans_transUChars(pTokenizer->pTransliterator, *buf, &copyLen, *nBuf, 0, &limit, &status);
    if (U_FAILURE(status)) {
        return SQLITE_ERROR;
    }
    // copyLen now contains the output length after transformation
    // limit contains the new limit position (not the output length)

    // Validate the output length after transformation
    if (copyLen < 0 || copyLen > *nBuf) {
        return SQLITE_ERROR;
    }

    // Convert back to UTF-8
    // Use a more conservative estimate for UTF-8 buffer size to handle
    // expanded characters Check for integer overflow before multiplication
    int32_t requiredDestSize = 0;
    if (copyLen > (INT32_MAX - 4096) / 8) {
        return SQLITE_ERROR;  // Prevent integer overflow
    }
    requiredDestSize = (copyLen * 8) + 4096;  // Increased multiplier to handle all possible
                                              // expansions
    if (*nDest < requiredDestSize) {
        char* newDest = (char*)sqlite3_realloc(*dest, requiredDestSize);
        if (!newDest) {
            return SQLITE_NOMEM;
        }
        *dest = newDest;
        *nDest = requiredDestSize;
    }

    int32_t utf8Len = 0;
    status = U_ZERO_ERROR;
    // Ensure we don't exceed buffer bounds for UTF-8 conversion
    int32_t safeCopyLen = (copyLen < *nBuf) ? copyLen : (*nBuf - 1);
    // Validate parameters before calling ICU function
    if (safeCopyLen < 0 || *nDest <= 0) {
        return SQLITE_ERROR;
    }
    u_strToUTF8WithSub(*dest, *nDest, &utf8Len, *buf, safeCopyLen, 0xFFFD, NULL, &status);
    if (U_FAILURE(status) || utf8Len < 0) {
        return SQLITE_ERROR;
    }
    // Note: utf8Len can be larger than nDest if the buffer was too small,
    // but ICU will truncate The actual usable length is min(utf8Len, nDest)

    // Additional validation to ensure utf8Len is reasonable
    if (utf8Len > *nDest * 4) {  // Maximum UTF-8 expansion is 4 bytes per code point
        return SQLITE_ERROR;
    }

    // Ensure we don't pass invalid parameters to xToken
    if (*dest && utf8Len > 0) {
        // Handle case where utf8Len might exceed buffer but ICU
        // truncated the output
        int safeLen = (utf8Len <= *nDest) ? utf8Len : *nDest;
        if (xToken(pCtx, 0, *dest, safeLen, iStartByte, iEndByte) != SQLITE_OK) {
            return SQLITE_ERROR;
        }
    }

    return result;
}

// ========================================================================
// === CORE TOKENIZATION FUNCTION (xTokenize) =============================
// ========================================================================

static int icuTokenize(Fts5Tokenizer* pTok, void* pCtx, int flags, const char* pText, int nText,
                       const char* pLocale, int nLocale,
                       int (*xToken)(void* pCtx, int tflags, const char* pToken, int nToken,
                                     int iStart, int iEnd)) {
    UNUSED_PARAMETER(flags);
    UNUSED_PARAMETER(pLocale);
    UNUSED_PARAMETER(nLocale);

    IcuTokenizerV2* pTokenizer = (IcuTokenizerV2*)pTok;
    UErrorCode status = U_ZERO_ERROR;

    if (!pText || nText <= 0)
        return SQLITE_OK;

    // Step 1: Allocate buffers for UTF-8 to UTF-16 conversion and byte
    // offset mapping
    UChar* utf16_text_buffer = NULL;
    int32_t* byte_offset_map = NULL;
    int32_t utf16_buffer_size, map_buffer_size;

    int result = allocate_conversion_buffers(nText, &utf16_text_buffer, &byte_offset_map,
                                             &utf16_buffer_size, &map_buffer_size);
    if (result != SQLITE_OK) {
        return result;  // Error already handled in the allocation
                        // function
    }

    // Step 2: Validate buffer size against actual code point count
    result = validate_buffer_size(pText, nText, utf16_buffer_size, utf16_text_buffer,
                                  byte_offset_map);
    if (result != SQLITE_OK) {
        return result;  // Error already handled in the validation
                        // function
    }

    // Step 3: Convert UTF-8 to UTF-16 with position mapping
    int32_t utf16_text_length = convert_utf8_to_utf16_with_mapping(
      pText, nText, utf16_text_buffer, utf16_buffer_size, byte_offset_map);

    if (utf16_text_length < 0) {
        // Error occurred in conversion
        sqlite3_free(utf16_text_buffer);
        sqlite3_free(byte_offset_map);
        return SQLITE_ERROR;
    }

    // Step 4: Set text for break iterator
    ubrk_setText(pTokenizer->pBreakIterator, utf16_text_buffer, utf16_text_length, &status);
    if (U_FAILURE(status)) {
        sqlite3_free(utf16_text_buffer);
        sqlite3_free(byte_offset_map);
        return SQLITE_ERROR;
    }

    // Step 5: Initialize dynamic buffers for normalized text
    UChar* transliteration_buffer = NULL;
    char* transliterated_utf8_buffer = NULL;
    int32_t transliteration_buffer_size = 0;
    int32_t transliterated_utf8_buffer_size = 0;

    // Step 6: Process tokens identified by the break iterator
    int32_t token_start = ubrk_first(pTokenizer->pBreakIterator);
    int32_t token_end;

    while ((token_end = ubrk_next(pTokenizer->pBreakIterator)) != UBRK_DONE) {
        // Bounds checking for array access - ensure positions are
        // within our UTF-16 buffer
        if (token_start < 0 || token_end < 0 || token_start > utf16_buffer_size ||
            token_end > utf16_buffer_size) {
            result = SQLITE_ERROR;
            break;
        }

        int32_t word_status = ubrk_getRuleStatus(pTokenizer->pBreakIterator);

        // Process the current token
        result = process_single_token(pTokenizer, utf16_text_buffer, byte_offset_map, token_start,
                                      token_end, pCtx, xToken, word_status, &transliteration_buffer,
                                      &transliteration_buffer_size, &transliterated_utf8_buffer,
                                      &transliterated_utf8_buffer_size);

        if (result != SQLITE_OK) {
            break;  // Error in processing this token
        }

        token_start = token_end;
    }

    // Step 7: Cleanup allocated memory
    if (transliteration_buffer)
        sqlite3_free(transliteration_buffer);
    if (transliterated_utf8_buffer)
        sqlite3_free(transliterated_utf8_buffer);
    if (utf16_text_buffer)
        sqlite3_free(utf16_text_buffer);
    if (byte_offset_map)
        sqlite3_free(byte_offset_map);

    return result;
}

// ========================================================================
// === MODULE INITIALIZATION ==============================================
// ========================================================================

#define PASTE_IMPL(a, b, c) a##b##c
#define PASTE(a, b, c) PASTE_IMPL(a, b, c)

#ifdef _WIN32
__declspec(dllexport)
#endif
// cppcheck-suppress unusedFunction
int PASTE(sqlite3_ftsicu, INIT_LOCALE_SUFFIX_FOR_FUNCTION, _init)(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
){
    SQLITE_EXTENSION_INIT2(pApi);
    fts5_api* pFts5Api = fts5_api_from_db(db);
    if (!pFts5Api) {
        *pzErrMsg = sqlite3_mprintf("Failed to get FTS5 API");
        return SQLITE_ERROR;
    }

    // Check if v2 API is available
    if (pFts5Api->iVersion < 2) {
        *pzErrMsg = sqlite3_mprintf("FTS5 v2 API not available");
        return SQLITE_ERROR;
    }

    fts5_tokenizer_v2 tokenizer = {
      .iVersion = 2, .xCreate = icuCreate, .xDelete = icuDelete, .xTokenize = icuTokenize};

    int rc = pFts5Api->xCreateTokenizer_v2(pFts5Api, TOKENIZER_NAME, NULL, &tokenizer, NULL);
    if (rc != SQLITE_OK) {
        *pzErrMsg = sqlite3_mprintf("Failed to register ICU tokenizer: %s", sqlite3_errstr(rc));
    }
    return rc;
}
