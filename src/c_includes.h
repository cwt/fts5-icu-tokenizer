#ifndef C_INCLUDES_H
#define C_INCLUDES_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sqlite3.h"
#define SQLITE_EXTENSION_INIT1
#include "sqlite3ext.h"

#include <unicode/utypes.h>
#include <unicode/ustring.h>
#include <unicode/ubrk.h>
#include <unicode/utrans.h>
#include <unicode/uchar.h>

UBreakIterator* fts5_ubrk_open(UBreakIteratorType type, const char* locale, const UChar* text, int32_t textLength, UErrorCode* status);
void fts5_ubrk_close(UBreakIterator* bi);
void fts5_ubrk_setText(UBreakIterator* bi, const UChar* text, int32_t textLength, UErrorCode* status);
int32_t fts5_ubrk_first(UBreakIterator* bi);
int32_t fts5_ubrk_next(UBreakIterator* bi);
int32_t fts5_ubrk_getRuleStatus(UBreakIterator* bi);

UTransliterator* fts5_utrans_openU(const UChar* id, int32_t idLength, UTransDirection dir, const UChar* rules, int32_t rulesLength, UParseError* parseError, UErrorCode* status);
void fts5_utrans_close(UTransliterator* trans);
void fts5_utrans_transUChars(const UTransliterator* trans, UChar* text, int32_t* textLength, int32_t textCapacity, int32_t start, int32_t* limit, UErrorCode* status);

char* fts5_u_strToUTF8WithSub(char* dest, int32_t destCapacity, int32_t* pDestLength, const UChar* src, int32_t srcLength, UChar32 subchar, int32_t* pNumSubstitutions, UErrorCode* pErrorCode);
UChar* fts5_u_strFromUTF8(UChar* dest, int32_t destCapacity, int32_t* pDestLength, const char* src, int32_t srcLength, UErrorCode* pErrorCode);
char* fts5_u_strToUTF8(char* dest, int32_t destCapacity, int32_t* pDestLength, const UChar* src, int32_t srcLength, UErrorCode* pErrorCode);

#endif
