#include "c_includes.h"

UBreakIterator* fts5_ubrk_open(UBreakIteratorType type, const char* locale, const UChar* text, int32_t textLength, UErrorCode* status) {
    return ubrk_open(type, locale, text, textLength, status);
}

void fts5_ubrk_close(UBreakIterator* bi) {
    ubrk_close(bi);
}

void fts5_ubrk_setText(UBreakIterator* bi, const UChar* text, int32_t textLength, UErrorCode* status) {
    ubrk_setText(bi, text, textLength, status);
}

int32_t fts5_ubrk_first(UBreakIterator* bi) {
    return ubrk_first(bi);
}

int32_t fts5_ubrk_next(UBreakIterator* bi) {
    return ubrk_next(bi);
}

int32_t fts5_ubrk_getRuleStatus(UBreakIterator* bi) {
    return ubrk_getRuleStatus(bi);
}

UTransliterator* fts5_utrans_openU(const UChar* id, int32_t idLength, UTransDirection dir, const UChar* rules, int32_t rulesLength, UParseError* parseError, UErrorCode* status) {
    return utrans_openU(id, idLength, dir, rules, rulesLength, parseError, status);
}

void fts5_utrans_close(UTransliterator* trans) {
    utrans_close(trans);
}

void fts5_utrans_transUChars(const UTransliterator* trans, UChar* text, int32_t* textLength, int32_t textCapacity, int32_t start, int32_t* limit, UErrorCode* status) {
    utrans_transUChars(trans, text, textLength, textCapacity, start, limit, status);
}

char* fts5_u_strToUTF8WithSub(char* dest, int32_t destCapacity, int32_t* pDestLength, const UChar* src, int32_t srcLength, UChar32 subchar, int32_t* pNumSubstitutions, UErrorCode* pErrorCode) {
    return u_strToUTF8WithSub(dest, destCapacity, pDestLength, src, srcLength, subchar, pNumSubstitutions, pErrorCode);
}

UChar* fts5_u_strFromUTF8(UChar* dest, int32_t destCapacity, int32_t* pDestLength, const char* src, int32_t srcLength, UErrorCode* pErrorCode) {
    return u_strFromUTF8(dest, destCapacity, pDestLength, src, srcLength, pErrorCode);
}

char* fts5_u_strToUTF8(char* dest, int32_t destCapacity, int32_t* pDestLength, const UChar* src, int32_t srcLength, UErrorCode* pErrorCode) {
    return u_strToUTF8(dest, destCapacity, pDestLength, src, srcLength, pErrorCode);
}
