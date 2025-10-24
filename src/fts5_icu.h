/**
 * @file fts5_icu.h
 * @brief Enhanced definitions and type definitions for ICU-based FTS5 tokenizer
 *
 * This header file provides all the necessary definitions, constants, and
 * data structures for the ICU-based FTS5 tokenizer. It includes locale-specific
 * configuration and ICU rule definitions.
 */

#ifndef FTS5_ICU_H
#define FTS5_ICU_H

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// SQLite headers
#include "sqlite3.h"
#include "sqlite3ext.h"  // Required for SQLITE_EXTENSION_INIT2

// ICU headers
#include <unicode/ubrk.h>
#include <unicode/uchar.h>
#include <unicode/ustring.h>
#include <unicode/utrans.h>
#include <unicode/utypes.h>

/*
 * These macros are passed in by the build system.
 * They will be auto-derived from TOKENIZER_LOCALE below.
 */
#ifndef TOKENIZER_LOCALE
#define TOKENIZER_LOCALE ""
#endif

#ifndef UNUSED_PARAMETER
#define UNUSED_PARAMETER(X) (void)(X)
#endif

// ========================================================================
// === ICU RULE DEFINITIONS ===============================================
// ========================================================================

/**
 * @defgroup ICU_RULES ICU Transliterator Rules
 * @{
 *
 * ICU transliterator rules define how text is transformed during tokenization.
 * These rules handle normalization, script conversion, and case folding.
 * Each locale has optimized rules for its specific language characteristics.
 */

/** Base normalization: decompose and remove diacritics */
#define ICU_RULE_BASE u"NFKD; "

/**
 * @name Language-Specific ICU Rules
 *
 * Optimized ICU rules for specific languages. Each language uses rules
 * appropriate for its characteristics and common text processing needs.
 * @{
 */

/** Japanese: Normalize Katakana/Hiragana variations and convert to lowercase */
#define ICU_RULE_JA (ICU_RULE_BASE u"Katakana-Hiragana; Lower; NFKC")  // Japanese

/** Chinese: Convert between Traditional/Simplified forms and normalize */
#define ICU_RULE_ZH (ICU_RULE_BASE u"Traditional-Simplified; Lower; NFKC")  // Chinese

/** Thai: Basic normalization appropriate for Thai script */
#define ICU_RULE_TH (ICU_RULE_BASE u"Lower; NFKC")  // Thai

/** Korean: Basic normalization for Korean Hangul */
#define ICU_RULE_KO (ICU_RULE_BASE u"Lower; NFKC")  // Korean

/** Arabic: Convert Arabic script to Latin and normalize */
#define ICU_RULE_AR (ICU_RULE_BASE u"Arabic-Latin; Lower; NFKC")  // Arabic

/** Russian: Convert Cyrillic script to Latin and normalize */
#define ICU_RULE_RU (ICU_RULE_BASE u"Cyrillic-Latin; Lower; NFKC")  // Russian

/** Hebrew: Convert Hebrew script to Latin and normalize */
#define ICU_RULE_HE (ICU_RULE_BASE u"Hebrew-Latin; Lower; NFKC")  // Hebrew

/** Greek: Convert Greek script to Latin and normalize */
#define ICU_RULE_EL (ICU_RULE_BASE u"Greek-Latin; Lower; NFKC")  // Greek

/** @} */

/**
 * Default comprehensive rule for mixed or unknown locales.
 * This rule handles text in any supported script by converting to Latin/ASCII.
 * It's more comprehensive but potentially slower than locale-specific rules.
 */
#define ICU_RULE_DEFAULT                                                                           \
    (ICU_RULE_BASE u"Arabic-Latin; Cyrillic-Latin; Hebrew-Latin; "                                 \
                   u"Greek-Latin; Latin-ASCII; "                                                   \
                   u"Lower; NFKC; Traditional-Simplified; "                                        \
                   u"Katakana-Hiragana")

/** @} */

// ========================================================================
// === AUTO-CONFIGURATION FROM TOKENIZER_LOCALE =========================
// ========================================================================
// If user sets -DTOKENIZER_LOCALE="xx", we auto-derive the rest.

#undef TOKENIZER_NAME
#undef INIT_LOCALE_SUFFIX
#undef ICU_TOKENIZER_RULES

// Since we can't use strcmp in preprocessor directives, we use separate defines
// for each locale that are set by the build system based on the LOCALE
// variable.

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

/**
 * @brief Main tokenizer struct (common base)
 *
 * This structure holds the ICU objects needed for tokenization:
 * - Break iterator for identifying word boundaries
 * - Transliterator for text normalization
 */
typedef struct IcuTokenizer {
    UBreakIterator* pBreakIterator;   /**< ICU break iterator for word segmentation */
    UTransliterator* pTransliterator; /**< ICU transliterator for text normalization */
} IcuTokenizer;

/**
 * @brief Macro for module initialization function name construction
 *
 * This macro creates the appropriate function name based on the locale suffix.
 * For example, for locale "ja", it will create "sqlite3_ftsicu_ja_init".
 */
#define PASTE_IMPL(a, b, c) a##b##c
#define PASTE(a, b, c) PASTE_IMPL(a, b, c)

#endif  // FTS5_ICU_H