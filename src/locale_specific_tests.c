/**
 * @file locale_specific_tests.c
 * @brief A C program to test locale-specific ICU transliterator rules
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ICU headers
#include <unicode/ustring.h>
#include <unicode/utrans.h>
#include <unicode/utypes.h>

/**
 * @brief Test the ICU transliterator with a given input string and rules
 *
 * @param input The input string to transliterate
 * @param rules The transliterator rules to apply
 * @param testName A descriptive name for the test
 */
static void testTransliteratorWithRules(const char* input, const char* rules,
                                        const char* testName) {
    UErrorCode status = U_ZERO_ERROR;

    // Convert rules from UTF-8 to UTF-16
    UChar* utf16Rules = NULL;
    int32_t rulesLen = 0;

    // First get the required length
    u_strFromUTF8(NULL, 0, &rulesLen, rules, -1, &status);
    if (status != U_BUFFER_OVERFLOW_ERROR) {
        fprintf(stderr, "Error getting UTF-16 length for rules: %s\n", u_errorName(status));
        return;
    }

    status = U_ZERO_ERROR;
    utf16Rules = (UChar*)malloc(sizeof(UChar) * (rulesLen + 1));
    if (!utf16Rules) {
        fprintf(stderr, "Memory allocation error for rules\n");
        return;
    }

    u_strFromUTF8(utf16Rules, rulesLen + 1, NULL, rules, -1, &status);
    if (U_FAILURE(status)) {
        fprintf(stderr, "Error converting rules to UTF-16: %s\n", u_errorName(status));
        free(utf16Rules);
        return;
    }

    // Create the transliterator with the specified rules
    UTransliterator* transliterator = utrans_openU(utf16Rules, -1, UTRANS_FORWARD, NULL, 0, NULL,
                                                   &status);

    if (U_FAILURE(status)) {
        fprintf(stderr, "Error creating transliterator with rules '%s': %s\n", rules,
                u_errorName(status));
        free(utf16Rules);
        return;
    }

    // Convert input UTF-8 string to UTF-16
    UChar* utf16Input = NULL;
    int32_t inputLen = 0;

    // First get the required length
    u_strFromUTF8(NULL, 0, &inputLen, input, -1, &status);
    if (status != U_BUFFER_OVERFLOW_ERROR) {
        fprintf(stderr, "Error getting UTF-16 length: %s\n", u_errorName(status));
        utrans_close(transliterator);
        free(utf16Rules);
        return;
    }

    status = U_ZERO_ERROR;
    utf16Input = (UChar*)malloc(sizeof(UChar) * (inputLen + 1));
    if (!utf16Input) {
        fprintf(stderr, "Memory allocation error\n");
        utrans_close(transliterator);
        free(utf16Rules);
        return;
    }

    u_strFromUTF8(utf16Input, inputLen + 1, NULL, input, -1, &status);
    if (U_FAILURE(status)) {
        fprintf(stderr, "Error converting to UTF-16: %s\n", u_errorName(status));
        free(utf16Input);
        free(utf16Rules);
        utrans_close(transliterator);
        return;
    }

    // Perform transliteration
    int32_t limit = inputLen;
    int32_t capacity = inputLen * 3;  // Provide extra space for expansion
    UChar* utf16Output = (UChar*)malloc(sizeof(UChar) * capacity);
    if (!utf16Output) {
        fprintf(stderr, "Memory allocation error\n");
        free(utf16Input);
        free(utf16Rules);
        utrans_close(transliterator);
        return;
    }

    // Copy input to output buffer for in-place transliteration
    u_strncpy(utf16Output, utf16Input, inputLen);

    status = U_ZERO_ERROR;
    utrans_transUChars(transliterator, utf16Output, &inputLen, capacity, 0, &limit, &status);
    if (U_FAILURE(status)) {
        fprintf(stderr, "Error during transliteration: %s\n", u_errorName(status));
        free(utf16Input);
        free(utf16Rules);
        free(utf16Output);
        utrans_close(transliterator);
        return;
    }

    // Convert result back to UTF-8 for display
    char* utf8Output = NULL;
    int32_t outputLen = 0;

    // First get the required length
    status = U_ZERO_ERROR;  // Reset status
    u_strToUTF8(NULL, 0, &outputLen, utf16Output, limit, &status);
    if (status != U_BUFFER_OVERFLOW_ERROR) {
        fprintf(stderr, "Error getting UTF-8 length: %s\n", u_errorName(status));
        free(utf16Input);
        free(utf16Rules);
        free(utf16Output);
        utrans_close(transliterator);
        return;
    }

    status = U_ZERO_ERROR;
    utf8Output = (char*)malloc(sizeof(char) * (outputLen + 1));
    if (!utf8Output) {
        fprintf(stderr, "Memory allocation error\n");
        free(utf16Input);
        free(utf16Rules);
        free(utf16Output);
        utrans_close(transliterator);
        return;
    }

    u_strToUTF8(utf8Output, outputLen + 1, NULL, utf16Output, limit, &status);
    if (U_FAILURE(status)) {
        fprintf(stderr, "Error converting to UTF-8: %s\n", u_errorName(status));
        free(utf16Input);
        free(utf16Rules);
        free(utf16Output);
        free(utf8Output);
        utrans_close(transliterator);
        return;
    }

    // Print results
    printf("=== %s ===\n", testName);
    printf("Rules:  %s\n", rules);
    printf("Input:  %s\n", input);
    printf("Output: %s\n", utf8Output);
    printf("\n");

    // Cleanup
    free(utf16Input);
    free(utf16Rules);
    free(utf16Output);
    free(utf8Output);
    utrans_close(transliterator);
}

int main() {
    printf("Locale-Specific ICU Transliterator Test Program\n");
    printf("==============================================\n\n");

    // Test locale-specific rules (updated to match current ICU rules in
    // fts5_icu.c)
    testTransliteratorWithRules("中文", "NFKD; Traditional-Simplified; Lower", "Chinese (zh)");
    testTransliteratorWithRules("日本語", "NFKD; Katakana-Hiragana; Lower", "Japanese (ja)");
    testTransliteratorWithRules("ภาษาไทย", "NFKD; Lower", "Thai (th)");
    testTransliteratorWithRules("한국어", "NFKD; Lower", "Korean (ko)");
    testTransliteratorWithRules("العربية", "NFKD; Arabic-Latin; Lower", "Arabic (ar)");
    testTransliteratorWithRules("русский", "NFKD; Cyrillic-Latin; Lower", "Russian (ru)");
    testTransliteratorWithRules("עברית", "NFKD; Hebrew-Latin; Lower", "Hebrew (he)");
    testTransliteratorWithRules("Ελληνικά", "NFKD; Greek-Latin; Lower", "Greek (el)");
    testTransliteratorWithRules("Français", "NFKD; Latin-ASCII; Lower", "French (fr)");

    printf("All locale-specific tests completed.\n");
    return 0;
}