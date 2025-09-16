/**
 * @file test_transliterator.c
 * @brief A simple C program to test the enhanced ICU transliterator rules
 * with various language samples.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ICU headers
#include <unicode/utypes.h>
#include <unicode/ustring.h>
#include <unicode/utrans.h>

/**
 * @brief Test the ICU transliterator with a given input string
 * 
 * @param input The input string to transliterate
 * @param testName A descriptive name for the test
 */
void testTransliterator(const char* input, const char* testName) {
    UErrorCode status = U_ZERO_ERROR;
    
    // Create the transliterator with the same rules as used in fts5_icu.c
    UTransliterator *transliterator = utrans_openU(
        u"NFKD; [:Nonspacing Mark:] Remove; Arabic-Latin; Cyrillic-Latin; Hebrew-Latin; Greek-Latin; Latin-ASCII; Lower; NFKC; Traditional-Simplified; Katakana-Hiragana",
        -1, UTRANS_FORWARD, NULL, 0, NULL, &status);
    
    if (U_FAILURE(status)) {
        fprintf(stderr, "Error creating transliterator: %s\n", u_errorName(status));
        return;
    }
    
    // Convert input UTF-8 string to UTF-16
    UChar *utf16Input = NULL;
    int32_t inputLen = 0;
    
    // First get the required length
    u_strFromUTF8(NULL, 0, &inputLen, input, -1, &status);
    if (status != U_BUFFER_OVERFLOW_ERROR) {
        fprintf(stderr, "Error getting UTF-16 length: %s\n", u_errorName(status));
        utrans_close(transliterator);
        return;
    }
    
    status = U_ZERO_ERROR;
    utf16Input = (UChar*)malloc(sizeof(UChar) * (inputLen + 1));
    if (!utf16Input) {
        fprintf(stderr, "Memory allocation error\n");
        utrans_close(transliterator);
        return;
    }
    
    u_strFromUTF8(utf16Input, inputLen + 1, NULL, input, -1, &status);
    if (U_FAILURE(status)) {
        fprintf(stderr, "Error converting to UTF-16: %s\n", u_errorName(status));
        free(utf16Input);
        utrans_close(transliterator);
        return;
    }
    
    // Perform transliteration
    int32_t limit = inputLen;
    int32_t capacity = inputLen * 3; // Provide extra space for expansion
    UChar *utf16Output = (UChar*)malloc(sizeof(UChar) * capacity);
    if (!utf16Output) {
        fprintf(stderr, "Memory allocation error\n");
        free(utf16Input);
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
        free(utf16Output);
        utrans_close(transliterator);
        return;
    }
    
    // Convert result back to UTF-8 for display
    char *utf8Output = NULL;
    int32_t outputLen = 0;
    
    // First get the required length
    status = U_ZERO_ERROR; // Reset status
    u_strToUTF8(NULL, 0, &outputLen, utf16Output, limit, &status);
    if (status != U_BUFFER_OVERFLOW_ERROR) {
        fprintf(stderr, "Error getting UTF-8 length: %s\n", u_errorName(status));
        free(utf16Input);
        free(utf16Output);
        utrans_close(transliterator);
        return;
    }
    
    status = U_ZERO_ERROR;
    utf8Output = (char*)malloc(sizeof(char) * (outputLen + 1));
    if (!utf8Output) {
        fprintf(stderr, "Memory allocation error\n");
        free(utf16Input);
        free(utf16Output);
        utrans_close(transliterator);
        return;
    }
    
    u_strToUTF8(utf8Output, outputLen + 1, NULL, utf16Output, limit, &status);
    if (U_FAILURE(status)) {
        fprintf(stderr, "Error converting to UTF-8: %s\n", u_errorName(status));
        free(utf16Input);
        free(utf16Output);
        free(utf8Output);
        utrans_close(transliterator);
        return;
    }
    
    // Print results
    printf("=== %s ===\n", testName);
    printf("Input:  %s\n", input);
    printf("Output: %s\n", utf8Output);
    printf("\n");
    
    // Cleanup
    free(utf16Input);
    free(utf16Output);
    free(utf8Output);
    utrans_close(transliterator);
}

int main() {
    printf("ICU Transliterator Test Program\n");
    printf("===============================\n\n");
    
    // Test with various language samples
    testTransliterator("العربية", "Arabic");
    testTransliterator("русский", "Cyrillic");
    testTransliterator("עברית", "Hebrew");
    testTransliterator("Ελληνικά", "Greek");
    testTransliterator("中文", "Chinese");
    testTransliterator("日本語", "Japanese");
    testTransliterator("Français", "French with diacritics");
    testTransliterator("Español", "Spanish with diacritics");
    testTransliterator("ỆᶍǍᶆṔƚÉ", "Complex diacritics");
    
    // Test some edge cases
    testTransliterator("Τη γλώσσα μου έδωσαν ελληνικό", "Greek phrase");
    testTransliterator("В чащах юга жил бы цитрус? Да, но фальшивый экземпляр!", "Russian phrase");
    testTransliterator("視野無限廣，窗外有藍天", "Traditional Chinese");
    testTransliterator("视野无限广，窗外有蓝天", "Simplified Chinese");
    
    printf("All tests completed.\n");
    return 0;
}