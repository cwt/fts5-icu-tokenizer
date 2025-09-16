/**
 * @file fts5_icu.c
 * @brief A dynamic FTS5 tokenizer for SQLite that uses ICU to segment text
 * based on a locale provided at compile time.
 *
 * This version is written in pure C for maximum stability and direct
 * control over memory management, making it suitable for high-volume,
 * long-running systems.
 *
 * The locale, tokenizer name, and library entry point are set at compile time
 * via preprocessor definitions passed in by the CMake build system.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// SQLite headers
#include "sqlite3.h"
#include "sqlite3ext.h" // Required for SQLITE_EXTENSION_INIT2

// ICU headers
#include <unicode/utypes.h>
#include <unicode/ubrk.h>
#include <unicode/ustring.h>
#include <unicode/uchar.h>
#include <unicode/utrans.h>

/*
** These macros are passed in by CMake. They default to "" and "icu" if not defined.
*/
#ifndef TOKENIZER_LOCALE
# define TOKENIZER_LOCALE ""
#endif
#ifndef TOKENIZER_NAME
# define TOKENIZER_NAME "icu"
#endif

#ifndef UNUSED_PARAMETER
# define UNUSED_PARAMETER(X) (void)(X)
#endif

// Define the fts5_api pointer before use
SQLITE_EXTENSION_INIT1

// Forward declarations for the tokenizer functions
static int icuCreate(void*, const char**, int, Fts5Tokenizer**);
static void icuDelete(Fts5Tokenizer*);
static int icuTokenize(Fts5Tokenizer*, void*, int, const char*, int, int (*)(void*, int, const char*, int, int, int));

// Main tokenizer struct
typedef struct IcuTokenizer {
    fts5_tokenizer fts_tokenizer; // This MUST be the first member
    UBreakIterator *pBreakIterator;
    UTransliterator *pTransliterator;
} IcuTokenizer;

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


/**
 * @brief FTS5 tokenizer creation callback (xCreate).
 */
static int icuCreate(
  void *pCtx,
  const char **azArg,
  int nArg,
  Fts5Tokenizer **ppOut
){
  UNUSED_PARAMETER(pCtx);
  UNUSED_PARAMETER(azArg);
  UNUSED_PARAMETER(nArg);

  IcuTokenizer *pTokenizer = (IcuTokenizer*)sqlite3_malloc(sizeof(IcuTokenizer));
  if( pTokenizer==NULL ){
    return SQLITE_NOMEM;
  }
  memset(pTokenizer, 0, sizeof(IcuTokenizer));

  UErrorCode status = U_ZERO_ERROR;
  // Use the locale defined at compile time by CMake
  pTokenizer->pBreakIterator = ubrk_open(UBRK_WORD, TOKENIZER_LOCALE, NULL, 0, &status);

  if( U_FAILURE(status) ){
    fprintf(stderr, "ICU Tokenizer Error: ubrk_open() for locale '%s' failed: %s\n", TOKENIZER_LOCALE, u_errorName(status));
    sqlite3_free(pTokenizer);
    return SQLITE_ERROR;
  }
  
  pTokenizer->pTransliterator = utrans_openU(u"NFKD; [:Nonspacing Mark:] Remove; Greek-Latin; Latin-ASCII; Lower; NFKC; Traditional-Simplified; Katakana-Hiragana", -1, UTRANS_FORWARD, NULL, 0, NULL, &status);

  if( U_FAILURE(status) ){
    fprintf(stderr, "ICU Tokenizer Error: utrans_openU() for locale '%s' failed: %s\n", TOKENIZER_LOCALE, u_errorName(status));
    sqlite3_free(pTokenizer);
    return SQLITE_ERROR;
  }

  pTokenizer->fts_tokenizer.xCreate = icuCreate;
  pTokenizer->fts_tokenizer.xDelete = icuDelete;
  pTokenizer->fts_tokenizer.xTokenize = icuTokenize;

  *ppOut = (Fts5Tokenizer*)pTokenizer;
  return SQLITE_OK;
}

/**
 * @brief FTS5 tokenizer deletion callback (xDelete).
 */
static void icuDelete(Fts5Tokenizer *pTok){
  if( pTok ){
    IcuTokenizer *pTokenizer = (IcuTokenizer*)pTok;
    ubrk_close(pTokenizer->pBreakIterator);
    utrans_close(pTokenizer->pTransliterator);
    sqlite3_free(pTokenizer);
  }
}

/**
 * @brief The core tokenization function (xTokenize).
 */
static int icuTokenize(
  Fts5Tokenizer *pTok,
  void *pCtx,
  int flags,
  const char *pText,
  int nText,
  int (*xToken)(void*, int, const char*, int, int, int)
){
  UNUSED_PARAMETER(flags);
  IcuTokenizer *pTokenizer = (IcuTokenizer*)pTok;
  UErrorCode status = U_ZERO_ERROR;

  if( pText==NULL || nText<=0 ){
    return SQLITE_OK;
  }

  // Allocate memory for UTF-16 text and the offset map.
  UChar *pUText = (UChar*)sqlite3_malloc(sizeof(UChar) * (nText + 1));
  if(!pUText) return SQLITE_NOMEM;
  int32_t *pMap = (int32_t*)sqlite3_malloc(sizeof(int32_t) * (nText + 2));
  if(!pMap){
    sqlite3_free(pUText);
    return SQLITE_NOMEM;
  }

  // Convert UTF-8 to UTF-16 and build the map simultaneously.
  int32_t iU16 = 0;
  int32_t iU8 = 0;

  while(iU8 < nText){
    UChar32 c;
    pMap[iU16] = iU8;
    U8_NEXT(pText, iU8, nText, c);

    UBool isError = 0;
    U16_APPEND(pUText, iU16, nText + 1, c, isError);
    if(isError){
        sqlite3_free(pUText);
        sqlite3_free(pMap);
        return SQLITE_ERROR;
    }
    if(c > 0xFFFF){
        pMap[iU16 - 1] = pMap[iU16 - 2];
    }
  }
  pMap[iU16] = nText;

  // Set the text for the break iterator
  ubrk_setText(pTokenizer->pBreakIterator, pUText, iU16, &status);
  if(U_FAILURE(status)){
    sqlite3_free(pUText);
    sqlite3_free(pMap);
    return SQLITE_ERROR;
  }

  UChar buf[256];
  int32_t nBuf = 256;
  char dest[512];
  int32_t nDest = 512;

  // Loop through boundaries and emit tokens
  int32_t iPrev = ubrk_first(pTokenizer->pBreakIterator);
  int32_t iNext;
  while( (iNext = ubrk_next(pTokenizer->pBreakIterator)) != UBRK_DONE ){
    int32_t wordStatus = ubrk_getRuleStatus(pTokenizer->pBreakIterator);
    if( wordStatus >= UBRK_WORD_NONE && wordStatus < UBRK_WORD_NONE_LIMIT ){
      iPrev = iNext;
      continue;
    }

    int32_t iStartByte = pMap[iPrev];
    int32_t iEndByte = pMap[iNext];
    int nTokenByte = iEndByte - iStartByte;

    if( nTokenByte > 0 ){
      int nByte = iNext - iPrev;
      if (nByte > nBuf)
        nByte = nBuf;
      u_strncpy(buf, pUText + iPrev, nByte);
      int32_t limit = nByte;
      utrans_transUChars(pTokenizer->pTransliterator, buf, &nByte, nBuf, 0, &limit, &status);
      if (U_FAILURE(status))
      {
        sqlite3_free(pUText);
        sqlite3_free(pMap);
        return SQLITE_ERROR;
      }
      nByte = limit;
      u_strToUTF8WithSub(dest, nDest, &nByte, buf, nByte, 0xFFFD, NULL, &status);
      if (U_FAILURE(status))
      {
        sqlite3_free(pUText);
        sqlite3_free(pMap);
        return SQLITE_ERROR;
      }
      if (nByte > nDest)
        nByte = nDest;
      int rc = xToken(pCtx, 0, dest, nByte, iStartByte, iEndByte);
      if( rc != SQLITE_OK ){
        sqlite3_free(pUText);
        sqlite3_free(pMap);
        return rc;
      }
    }
    iPrev = iNext;
  }

  sqlite3_free(pUText);
  sqlite3_free(pMap);

  return SQLITE_OK;
}

/*
** The main entry point for the SQLite extension.
** The name is constructed dynamically by the C preprocessor based on macros
** from the CMake build script.
**
** For example, if CMake defines INIT_LOCALE_SUFFIX as 'th', the function name
** becomes 'sqlite3_ftsicuth_init'. If it's empty, the name becomes
** 'sqlite3_ftsicu_init'.
*/
#define PASTE_IMPL(a,b,c) a##b##c
#define PASTE(a,b,c) PASTE_IMPL(a,b,c)

#ifndef INIT_LOCALE_SUFFIX
#define INIT_LOCALE_SUFFIX // Define as empty if not set by CMake
#endif

#ifdef _WIN32
__declspec(dllexport)
#endif
int PASTE(sqlite3_ftsicu, INIT_LOCALE_SUFFIX, _init)(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
){
  SQLITE_EXTENSION_INIT2(pApi);

  fts5_api *pFts5Api;
  fts5_tokenizer tokenizer;

  pFts5Api = fts5_api_from_db(db);
  if( !pFts5Api ){
      *pzErrMsg = sqlite3_mprintf("Failed to get FTS5 API");
      return SQLITE_ERROR;
  }

  tokenizer.xCreate = icuCreate;
  tokenizer.xDelete = icuDelete;
  tokenizer.xTokenize = icuTokenize;

  // Use the tokenizer name defined at compile time by CMake
  return pFts5Api->xCreateTokenizer(pFts5Api, TOKENIZER_NAME, (void*)pFts5Api, &tokenizer, NULL);
}
