#!/bin/bash

# Test script for all supported locales and the universal tokenizer using API v1
# This script tests each built library with appropriate sample text

echo "Testing all supported locales and the universal tokenizer (API v1)..."

# Prefer Homebrew sqlite3 (Apple's system sqlite3 lacks .load support)
if command -v brew &>/dev/null && [ -x "$(brew --prefix sqlite 2>/dev/null || brew --prefix sqlite3 2>/dev/null || echo /none)/bin/sqlite3" ]; then
    SQLITE3="$(brew --prefix sqlite 2>/dev/null || brew --prefix sqlite3)/bin/sqlite3"
elif command -v sqlite3 &> /dev/null; then
    SQLITE3=sqlite3
else
    echo "ERROR: sqlite3 is not installed or not in PATH"
    exit 1
fi

# Detect shared library extension
case "$(uname -s)" in
    Darwin) LIB_EXT=dylib ;;
    *)      LIB_EXT=so ;;
esac

# Test the universal tokenizer
echo ""
echo "=================================================="
echo "Testing universal tokenizer (API v1)"
echo "=================================================="
if [ -f "./build/libfts5_icu_legacy.${LIB_EXT}" ]; then
    # Replace the library name in the SQL file to point to the legacy version (tokenizer name remains the same)
    sed 's/libfts5_icu/libfts5_icu_legacy/' ./tests/test_universal_tokenizer.sql | $SQLITE3
    if [ $? -ne 0 ]; then
        echo "ERROR: Test failed for universal tokenizer (API v1)"
    else
        echo "SUCCESS: Universal tokenizer test completed (API v1)"
    fi
else
    echo "WARNING: Universal tokenizer library (API v1) not found"
fi

# Test locale-specific tokenizers
echo ""
echo "=================================================="
echo "Testing locale-specific tokenizers (API v1)"
echo "=================================================="

# Define test cases: locale, test script file
TEST_CASES=(
    "ar:tests/test_ar_tokenizer.sql"
    "el:tests/test_el_tokenizer.sql"
    "he:tests/test_he_tokenizer.sql"
    "ja:tests/test_ja_tokenizer.sql"
    "ko:tests/test_ko_tokenizer.sql"
    "ru:tests/test_ru_tokenizer.sql"
    "th:tests/test_th_tokenizer.sql"
    "zh:tests/test_zh_tokenizer.sql"
)

# Test each locale
for test_case in "${TEST_CASES[@]}"; do
    locale="${test_case%%:*}"
    test_script="${test_case#*:}"

    echo ""
    echo "--------------------------------------------------"
    echo "Testing $locale tokenizer (API v1)"
    echo "--------------------------------------------------"

    if [ -f "./build/libfts5_icu_${locale}_legacy.${LIB_EXT}" ]; then
        if [ -f "./$test_script" ]; then
            # Replace the library name in the SQL file to point to the legacy version (tokenizer name remains the same)
            sed "s/libfts5_icu_${locale}/libfts5_icu_${locale}_legacy/" ./$test_script | $SQLITE3
            if [ $? -ne 0 ]; then
                echo "ERROR: Test failed for $locale tokenizer (API v1)"
            else
                echo "SUCCESS: $locale tokenizer test completed (API v1)"
            fi
        else
            echo "WARNING: Test script $test_script not found"
        fi
    else
        echo "WARNING: Library libfts5_icu_${locale}_legacy.${LIB_EXT} not found"
    fi
done

echo ""
echo "=================================================="
echo "All locale-specific tokenizer tests completed (API v1)!"
echo "=================================================="

echo ""
echo "============================================================================"
echo "Testing TH and ZH on the universal tokenizer with some expected failed cases (API v1)"
echo "============================================================================"

if [ -f "./build/libfts5_icu_legacy.${LIB_EXT}" ]; then
    sed 's/libfts5_icu/libfts5_icu_legacy/' ./tests/test_universal_with_th_zh.sql | $SQLITE3 | sed -e 's/|/ /g'  # format output for readability
else
    echo "WARNING: Universal tokenizer library (API v1) not found, skipping TH/ZH test"
fi