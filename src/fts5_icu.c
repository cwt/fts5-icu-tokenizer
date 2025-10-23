/**
 * @file fts5_icu.c
 * @brief A dynamic FTS5 tokenizer for SQLite that uses ICU to segment text
 *        based on a locale provided at compile time.
 *
 * This version is written in pure C for maximum stability and direct
 * control over memory management, making it suitable for high-volume,
 * long-running systems.
 *
 * The user defines only:
 *   -DTOKENIZER_LOCALE="ja"   (or "zh", "th", etc.)
 *
 * All other settings (TOKENIZER_NAME, INIT_LOCALE_SUFFIX, ICU rules)
 * are derived automatically at compile time.
 */

#include "fts5_icu_common.h"

// Define the fts5_api pointer before use
SQLITE_EXTENSION_INIT1

// Helper function to get the FTS5 API pointer from the database connection.
static fts5_api *fts5_api_from_db(sqlite3 *db){
  fts5_api *pApi = 0;
  sqlite3_stmt *pStmt = 0;
  if( sqlite3_prepare_v2(db, "SELECT fts5(?)", -1, &pStmt, 0)==SQLITE_OK ){
    sqlite3_bind_pointer(pStmt, 1, &pApi, "fts5_api_ptr", 0);
    sqlite3_step(pStmt);
  }
  sqlite3_finalize(pStmt);
  return pApi;
}

// Forward declarations
static int icuCreate(void*, const char**, int, Fts5Tokenizer**);
static void icuDelete(Fts5Tokenizer*);
static int icuTokenize(Fts5Tokenizer*, void*, int, const char*, int, int (*)(void*, int, const char*, int, int, int));

// Main tokenizer struct
typedef struct IcuTokenizerV1 {
    fts5_tokenizer fts_tokenizer; // Must be first member
    UBreakIterator *pBreakIterator;
    UTransliterator *pTransliterator;
} IcuTokenizerV1;

// ========================================================================
// === FTS5 TOKENIZER CREATION CALLBACK (xCreate) =========================
// ========================================================================

static int icuCreate(
  void *pCtx,
  const char **azArg,
  int nArg,
  Fts5Tokenizer **ppOut
){
  UNUSED_PARAMETER(pCtx);
  UNUSED_PARAMETER(azArg);
  UNUSED_PARAMETER(nArg);

  IcuTokenizerV1 *pTokenizer = (IcuTokenizerV1*)sqlite3_malloc(sizeof(IcuTokenizerV1));
  if (!pTokenizer) return SQLITE_NOMEM;
  memset(pTokenizer, 0, sizeof(IcuTokenizerV1));

  UErrorCode status = U_ZERO_ERROR;

  // Open break iterator with compile-time locale
  pTokenizer->pBreakIterator = ubrk_open(UBRK_WORD, TOKENIZER_LOCALE, NULL, 0, &status);
  if (U_FAILURE(status)) {
    // Avoid fprintf to stderr in SQLite extension; instead, just return error
    ubrk_close(pTokenizer->pBreakIterator);
    sqlite3_free(pTokenizer);
    return SQLITE_ERROR;
  }

  // Use compile-time selected rule
  pTokenizer->pTransliterator = utrans_openU(ICU_TOKENIZER_RULES, -1, UTRANS_FORWARD, NULL, 0, NULL, &status);
  if (U_FAILURE(status)) {
    // Avoid fprintf to stderr in SQLite extension; instead, just return error
    ubrk_close(pTokenizer->pBreakIterator);
    sqlite3_free(pTokenizer);
    return SQLITE_ERROR;
  }

  // Setup vtable
  pTokenizer->fts_tokenizer.xCreate = icuCreate;
  pTokenizer->fts_tokenizer.xDelete = icuDelete;
  pTokenizer->fts_tokenizer.xTokenize = icuTokenize;

  *ppOut = (Fts5Tokenizer*)pTokenizer;
  return SQLITE_OK;
}

// ========================================================================
// === FTS5 TOKENIZER DELETION CALLBACK (xDelete) =========================
// ========================================================================

static void icuDelete(Fts5Tokenizer *pTok){
  if (!pTok) return;
  IcuTokenizerV1 *pTokenizer = (IcuTokenizerV1*)pTok;
  ubrk_close(pTokenizer->pBreakIterator);
  utrans_close(pTokenizer->pTransliterator);
  sqlite3_free(pTokenizer);
}

// ========================================================================
// === CORE TOKENIZATION FUNCTION (xTokenize) =============================
// ========================================================================

static int icuTokenize(
  Fts5Tokenizer *pTok,
  void *pCtx,
  int flags,
  const char *pText,
  int nText,
  int (*xToken)(void*, int, const char*, int, int, int)
){
  UNUSED_PARAMETER(flags);
  IcuTokenizerV1 *pTokenizer = (IcuTokenizerV1*)pTok;
  UErrorCode status = U_ZERO_ERROR;

  if (!pText || nText <= 0) return SQLITE_OK;

  // Allocate UTF-16 buffer and byte offset map
  UChar *pUText = (UChar*)sqlite3_malloc((nText + 1) * sizeof(UChar));
  if (!pUText) return SQLITE_NOMEM;

  int32_t *pMap = (int32_t*)sqlite3_malloc((nText + 2) * sizeof(int32_t));
  if (!pMap) {
    sqlite3_free(pUText);
    return SQLITE_NOMEM;
  }

  // Convert UTF-8 → UTF-16 and build byte offset map
  int32_t iU16 = 0;
  int32_t iU8 = 0;
  while (iU8 < nText && iU16 < nText + 1) {
    UChar32 c;
    // Bounds check for pMap access
    if (iU16 >= 0 && iU16 < nText + 2) {
      pMap[iU16] = iU8;
    }
    U8_NEXT(pText, iU8, nText, c);
    // Check for invalid UTF-8 sequence - if we get a replacement character (0xFFFD)
    // and it's not actually a valid character that happens to map to 0xFFFD,
    // and if we haven't reached the end of the string
    if (c == 0xFFFD && iU8 > 0 && iU8 <= nText) {
      // Check if this is a genuine error by looking at the byte that caused it
      // If the byte isn't at the expected position or is a continuation byte in wrong place
      unsigned char potential_error_byte = (iU8 > 0) ? pText[iU8 - 1] : 0;
      if (potential_error_byte != 0) {  // If we have a non-null byte that caused 0xFFFD
        sqlite3_free(pUText);
        sqlite3_free(pMap);
        return SQLITE_ERROR;
      }
    }
    UBool isError = 0;
    U16_APPEND(pUText, iU16, nText + 1, c, isError);
    if (isError) {
      sqlite3_free(pUText);
      sqlite3_free(pMap);
      return SQLITE_ERROR;
    }
    // For surrogate pairs, we adjust the byte mapping
    if (c > 0xFFFF && iU16 >= 2 && (iU16 - 1) < nText + 2) {
      pMap[iU16 - 1] = pMap[iU16 - 2]; // Properly handle surrogate pair byte mapping
    }
  }
  // Bounds check before final assignment to pMap
  if (iU16 >= 0 && iU16 < nText + 2) {
    pMap[iU16] = nText;
  }

  // Set text for break iterator
  ubrk_setText(pTokenizer->pBreakIterator, pUText, iU16, &status);
  if (U_FAILURE(status)) {
    sqlite3_free(pUText);
    sqlite3_free(pMap);
    return SQLITE_ERROR;
  }

  // Dynamic buffers for normalized text
  UChar *buf = NULL;
  char *dest = NULL;
  int32_t nBuf = 0;
  int32_t nDest = 0;
  int result = SQLITE_OK;

  int32_t iPrev = ubrk_first(pTokenizer->pBreakIterator);
  int32_t iNext;
  while ((iNext = ubrk_next(pTokenizer->pBreakIterator)) != UBRK_DONE) {
    // Bounds checking for array access
    if (iPrev < 0 || iNext < 0 || iPrev > iU16 || iNext > iU16) {
      result = SQLITE_ERROR;
      goto cleanup;
    }

    int32_t wordStatus = ubrk_getRuleStatus(pTokenizer->pBreakIterator);
    if (wordStatus >= UBRK_WORD_NONE && wordStatus < UBRK_WORD_NONE_LIMIT) {
      iPrev = iNext;
      continue;
    }

    // Bounds checking for pMap array access
    if (iPrev >= 0 && iPrev < nText + 2 && iNext >= 0 && iNext < nText + 2) {
      int32_t iStartByte = pMap[iPrev];
      int32_t iEndByte = pMap[iNext];
      int nTokenByte = iEndByte - iStartByte;
      if (nTokenByte <= 0) {
        iPrev = iNext;
        continue;
      }

      // Process the token
      int32_t nSrc = iNext - iPrev;

      // Grow buffer if needed for transliteration
      // Use a more conservative estimate for buffer size to handle complex ICU transformations
      // Check for integer overflow before multiplication
      int32_t requiredBufSize = 0;
      if (nSrc > (INT32_MAX - 2048) / 6) {
        result = SQLITE_ERROR;  // Prevent integer overflow
        goto cleanup;
      }
      requiredBufSize = (nSrc * 6) + 2048;  // Increased multiplier to handle complex transformations
      if (nBuf < requiredBufSize) {
        UChar *newBuf = (UChar*)sqlite3_realloc(buf, requiredBufSize * sizeof(UChar));
        if (!newBuf) {
          result = SQLITE_NOMEM;
          goto cleanup;
        }
        buf = newBuf;
        nBuf = requiredBufSize;
      }

      // Ensure we don't exceed buffer bounds when copying
      int32_t copyLen = (nSrc < nBuf) ? nSrc : (nBuf - 1);
      u_strncpy(buf, pUText + iPrev, copyLen);
      buf[copyLen] = 0;  // Null terminate for safety

      int32_t limit = copyLen;
      status = U_ZERO_ERROR;
      utrans_transUChars(pTokenizer->pTransliterator, buf, &copyLen, nBuf, 0, &limit, &status);
      if (U_FAILURE(status)) {
        result = SQLITE_ERROR;
        goto cleanup;
      }
      copyLen = limit;

      // Convert back to UTF-8
      // Use a more conservative estimate for UTF-8 buffer size to handle expanded characters
      // Check for integer overflow before multiplication
      int32_t requiredDestSize = 0;
      if (copyLen > (INT32_MAX - 4096) / 8) {
        result = SQLITE_ERROR;  // Prevent integer overflow
        goto cleanup;
      }
      requiredDestSize = (copyLen * 8) + 4096;  // Increased multiplier to handle all possible expansions
      if (nDest < requiredDestSize) {
        char *newDest = (char*)sqlite3_realloc(dest, requiredDestSize);
        if (!newDest) {
          result = SQLITE_NOMEM;
          goto cleanup;
        }
        dest = newDest;
        nDest = requiredDestSize;
      }

      int32_t utf8Len = 0;
      status = U_ZERO_ERROR;
      // Ensure we don't exceed buffer bounds for UTF-8 conversion
      int32_t safeCopyLen = (copyLen < nBuf) ? copyLen : (nBuf - 1);
      u_strToUTF8WithSub(dest, nDest, &utf8Len, buf, safeCopyLen, 0xFFFD, NULL, &status);
      if (U_FAILURE(status) || utf8Len < 0 || utf8Len > nDest) {
        result = SQLITE_ERROR;
        goto cleanup;
      }

      // Ensure we don't pass invalid parameters to xToken
      if (dest && utf8Len > 0 && utf8Len <= nDest) {
        if (xToken(pCtx, 0, dest, utf8Len, iStartByte, iEndByte) != SQLITE_OK) {
          result = SQLITE_ERROR;
          goto cleanup;
        }
      } else if (utf8Len > 0) {
        // Handle case where utf8Len exceeds buffer but we still have data
        int safeLen = (utf8Len <= nDest) ? utf8Len : nDest;
        if (safeLen > 0 && xToken(pCtx, 0, dest, safeLen, iStartByte, iEndByte) != SQLITE_OK) {
          result = SQLITE_ERROR;
          goto cleanup;
        }
      }

      iPrev = iNext;
    } else {
      iPrev = iNext;
      continue;
    }
  }

cleanup:
  if (buf) sqlite3_free(buf);
  if (dest) sqlite3_free(dest);
  if (pUText) sqlite3_free(pUText);
  if (pMap) sqlite3_free(pMap);
  return result;
}

// ========================================================================
// === MODULE INITIALIZATION ==============================================
// ========================================================================

#define PASTE_IMPL(a,b,c) a##b##c
#define PASTE(a,b,c) PASTE_IMPL(a,b,c)

#ifdef _WIN32
__declspec(dllexport)
#endif
int PASTE(sqlite3_ftsicu, INIT_LOCALE_SUFFIX_FOR_FUNCTION, _init)(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
){
  SQLITE_EXTENSION_INIT2(pApi);
  fts5_api *pFts5Api = fts5_api_from_db(db);
  if (!pFts5Api) {
    *pzErrMsg = sqlite3_mprintf("Failed to get FTS5 API");
    return SQLITE_ERROR;
  }

  fts5_tokenizer tokenizer = {
    .xCreate = icuCreate,
    .xDelete = icuDelete,
    .xTokenize = icuTokenize
  };

  int rc = pFts5Api->xCreateTokenizer(pFts5Api, TOKENIZER_NAME, NULL, &tokenizer, NULL);
  if (rc != SQLITE_OK) {
    *pzErrMsg = sqlite3_mprintf("Failed to register ICU tokenizer: %s", sqlite3_errstr(rc));
  }
  return rc;
}
