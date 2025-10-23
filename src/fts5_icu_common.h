/**
 * @file fts5_icu_common.h
 * @brief Common definitions and type definitions for ICU-based FTS5 tokenizers
 */

#ifndef FTS5_ICU_COMMON_H
#define FTS5_ICU_COMMON_H

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
** These macros are passed in by the build system.
** They will be auto-derived from TOKENIZER_LOCALE below.
*/
#ifndef TOKENIZER_LOCALE
# define TOKENIZER_LOCALE ""
#endif

#ifndef UNUSED_PARAMETER
# define UNUSED_PARAMETER(X) (void)(X)
#endif

// ========================================================================
// === ICU RULE DEFINITIONS ===============================================
// ========================================================================

// Base normalization: decompose and remove diacritics
#define ICU_RULE_BASE u"NFKD; "

// Language-specific rules built from base
#define ICU_RULE_JA (ICU_RULE_BASE u"Katakana-Hiragana; Lower; NFKC")  // Japanese
#define ICU_RULE_ZH (ICU_RULE_BASE u"Traditional-Simplified; Lower; NFKC")  // Chinese
#define ICU_RULE_TH (ICU_RULE_BASE u"Lower; NFKC")                    // Thai
#define ICU_RULE_KO (ICU_RULE_BASE u"Lower; NFKC")                    // Korean
#define ICU_RULE_AR (ICU_RULE_BASE u"Arabic-Latin; Lower; NFKC")      // Arabic
#define ICU_RULE_RU (ICU_RULE_BASE u"Cyrillic-Latin; Lower; NFKC")    // Russian
#define ICU_RULE_HE (ICU_RULE_BASE u"Hebrew-Latin; Lower; NFKC")      // Hebrew
#define ICU_RULE_EL (ICU_RULE_BASE u"Greek-Latin; Lower; NFKC")       // Greek

// Default comprehensive rule for mixed or unknown locales
#define ICU_RULE_DEFAULT \
    (ICU_RULE_BASE \
    u"Arabic-Latin; Cyrillic-Latin; Hebrew-Latin; Greek-Latin; Latin-ASCII; " \
    u"Lower; NFKC; Traditional-Simplified; Katakana-Hiragana")

// ========================================================================
// === AUTO-CONFIGURATION FROM TOKENIZER_LOCALE =========================
// ========================================================================
// If user sets -DTOKENIZER_LOCALE="xx", we auto-derive the rest.

#undef TOKENIZER_NAME
#undef INIT_LOCALE_SUFFIX
#undef ICU_TOKENIZER_RULES

// Since we can't use strcmp in preprocessor directives, we use separate defines for each locale
// that are set by the build system based on the LOCALE variable.

// If C_INIT_SUFFIX_NO_UNDERSCORE is defined, use it for the function name
// Otherwise, use the traditional approach
#ifdef C_INIT_SUFFIX_NO_UNDERSCORE
  #define INIT_LOCALE_SUFFIX_FOR_FUNCTION C_INIT_SUFFIX_NO_UNDERSCORE
#else
  #define INIT_LOCALE_SUFFIX_FOR_FUNCTION INIT_LOCALE_SUFFIX
#endif

#if defined(TOKENIZER_LOCALE_JA)
  #define INIT_LOCALE_SUFFIX _ja
  #define TOKENIZER_NAME "icu_ja"
  #define ICU_TOKENIZER_RULES ICU_RULE_JA

#elif defined(TOKENIZER_LOCALE_ZH)
  #define INIT_LOCALE_SUFFIX _zh
  #define TOKENIZER_NAME "icu_zh"
  #define ICU_TOKENIZER_RULES ICU_RULE_ZH

#elif defined(TOKENIZER_LOCALE_TH)
  #define INIT_LOCALE_SUFFIX _th
  #define TOKENIZER_NAME "icu_th"
  #define ICU_TOKENIZER_RULES ICU_RULE_TH

#elif defined(TOKENIZER_LOCALE_KO)
  #define INIT_LOCALE_SUFFIX _ko
  #define TOKENIZER_NAME "icu_ko"
  #define ICU_TOKENIZER_RULES ICU_RULE_KO

#elif defined(TOKENIZER_LOCALE_AR)
  #define INIT_LOCALE_SUFFIX _ar
  #define TOKENIZER_NAME "icu_ar"
  #define ICU_TOKENIZER_RULES ICU_RULE_AR

#elif defined(TOKENIZER_LOCALE_RU)
  #define INIT_LOCALE_SUFFIX _ru
  #define TOKENIZER_NAME "icu_ru"
  #define ICU_TOKENIZER_RULES ICU_RULE_RU

#elif defined(TOKENIZER_LOCALE_HE)
  #define INIT_LOCALE_SUFFIX _he
  #define TOKENIZER_NAME "icu_he"
  #define ICU_TOKENIZER_RULES ICU_RULE_HE

#elif defined(TOKENIZER_LOCALE_EL)
  #define INIT_LOCALE_SUFFIX _el
  #define TOKENIZER_NAME "icu_el"
  #define ICU_TOKENIZER_RULES ICU_RULE_EL

#else
  // Default/fallback: generic tokenizer
  #define INIT_LOCALE_SUFFIX
  #define TOKENIZER_NAME "icu"
  #define ICU_TOKENIZER_RULES ICU_RULE_DEFAULT
#endif

// Main tokenizer struct (common base)
typedef struct IcuTokenizer {
    UBreakIterator *pBreakIterator;
    UTransliterator *pTransliterator;
} IcuTokenizer;

// Paste macro for module initialization
#define PASTE_IMPL(a,b,c) a##b##c
#define PASTE(a,b,c) PASTE_IMPL(a,b,c)

#endif // FTS5_ICU_COMMON_H