/**
 * @file test_locale_tokenizer.c
 * @brief A simple C program to test the locale-specific tokenizer
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// SQLite headers
#include "sqlite3.h"
#include "sqlite3ext.h"

// ICU headers
#include <unicode/utypes.h>
#include <unicode/ustring.h>
#include <unicode/utrans.h>

int main() {
    printf("Testing locale-specific ICU transliterator rules\n");
    printf("================================================\n\n");

    // Test the Chinese-specific rule
    UErrorCode status = U_ZERO_ERROR;
    UTransliterator *transliterator = utrans_openU(
        u"NFKD; Traditional-Simplified; Lower",
        -1, UTRANS_FORWARD, NULL, 0, NULL, &status);

    if (U_FAILURE(status)) {
        fprintf(stderr, "Error creating Chinese transliterator: %s\n", u_errorName(status));
        return 1;
    }

    // Test with Traditional Chinese text
    const char* input = "繁體中文測試";
    printf("Input: %s\n", input);

    // Convert input UTF-8 string to UTF-16
    UChar *utf16Input = NULL;
    int32_t inputLen = 0;

    // First get the required length
    u_strFromUTF8(NULL, 0, &inputLen, input, -1, &status);
    if (status != U_BUFFER_OVERFLOW_ERROR) {
        fprintf(stderr, "Error getting UTF-16 length: %s\n", u_errorName(status));
        utrans_close(transliterator);
        return 1;
    }

    status = U_ZERO_ERROR;
    utf16Input = (UChar*)malloc(sizeof(UChar) * (inputLen + 1));
    if (!utf16Input) {
        fprintf(stderr, "Memory allocation error\n");
        utrans_close(transliterator);
        return 1;
    }

    u_strFromUTF8(utf16Input, inputLen + 1, NULL, input, -1, &status);
    if (U_FAILURE(status)) {
        fprintf(stderr, "Error converting to UTF-16: %s\n", u_errorName(status));
        free(utf16Input);
        utrans_close(transliterator);
        return 1;
    }

    // Perform transliteration
    int32_t limit = inputLen;
    int32_t capacity = inputLen * 3; // Provide extra space for expansion
    UChar *utf16Output = (UChar*)malloc(sizeof(UChar) * capacity);
    if (!utf16Output) {
        fprintf(stderr, "Memory allocation error\n");
        free(utf16Input);
        utrans_close(transliterator);
        return 1;
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
        return 1;
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
        return 1;
    }

    status = U_ZERO_ERROR;
    utf8Output = (char*)malloc(sizeof(char) * (outputLen + 1));
    if (!utf8Output) {
        fprintf(stderr, "Memory allocation error\n");
        free(utf16Input);
        free(utf16Output);
        utrans_close(transliterator);
        return 1;
    }

    u_strToUTF8(utf8Output, outputLen + 1, NULL, utf16Output, limit, &status);
    if (U_FAILURE(status)) {
        fprintf(stderr, "Error converting to UTF-8: %s\n", u_errorName(status));
        free(utf16Input);
        free(utf16Output);
        free(utf8Output);
        utrans_close(transliterator);
        return 1;
    }

    // Print results
    printf("Output: %s\n", utf8Output);
    printf("\nTest completed successfully!\n");

    // Cleanup
    free(utf16Input);
    free(utf16Output);
    free(utf8Output);
    utrans_close(transliterator);

    return 0;
}