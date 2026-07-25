#!/bin/bash

# Test script for all supported locales and the universal tokenizer
# This script tests each built library with appropriate sample text

echo "Testing all supported locales and the universal tokenizer..."

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

# Extract expected version from build.zig.zon
EXPECTED_VERSION=$(grep -E '\.version = "' build.zig.zon | sed -E 's/.*"([^"]+)".*/\1/')

# Test extension version function
echo ""
echo "=================================================="
echo "Testing extension version (v2)"
echo "=================================================="
if [ -f "./zig-out/lib/libfts5_icu.${LIB_EXT}" ]; then
    DETECTED_VERSION=$(${SQLITE3} :memory: ".load ./zig-out/lib/libfts5_icu" "SELECT fts5_icu_version();" 2>/dev/null)
    echo "Extension version: ${DETECTED_VERSION} (Expected: ${EXPECTED_VERSION})"
    if [ "${DETECTED_VERSION}" = "${EXPECTED_VERSION}" ]; then
        echo "SUCCESS: Version function test completed"
    else
        echo "ERROR: Version mismatch (Got: '${DETECTED_VERSION}', Expected: '${EXPECTED_VERSION}')"
        exit 1
    fi
else
    echo "WARNING: Universal tokenizer library not found"
fi

# Test the universal tokenizer
echo ""
echo "=================================================="
echo "Testing universal tokenizer"
echo "=================================================="
if [ -f "./zig-out/lib/libfts5_icu.${LIB_EXT}" ]; then
    ${SQLITE3} < ./tests/test_universal_tokenizer.sql
    if [ $? -ne 0 ]; then
        echo "ERROR: Test failed for universal tokenizer"
    else
        echo "SUCCESS: Universal tokenizer test completed"
    fi
else
    echo "WARNING: Universal tokenizer library not found"
fi

# Test locale-specific tokenizers
echo ""
echo "=================================================="
echo "Testing locale-specific tokenizers"
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
    echo "Testing $locale tokenizer"
    echo "--------------------------------------------------"
    
    if [ -f "./zig-out/lib/libfts5_icu_${locale}.${LIB_EXT}" ]; then
        if [ -f "./$test_script" ]; then
            ${SQLITE3} < "./$test_script"
            if [ $? -ne 0 ]; then
                echo "ERROR: Test failed for $locale tokenizer"
            else
                echo "SUCCESS: $locale tokenizer test completed"
            fi
        else
            echo "WARNING: Test script $test_script not found"
        fi
    else
        echo "WARNING: Library libfts5_icu_${locale}.${LIB_EXT} not found"
    fi
done

echo ""
echo "=================================================="
echo "All locale-specific tokenizer tests completed!"
echo "=================================================="

echo ""
echo "============================================================================"
echo "Testing TH and ZH on the universal tokenizer with some expected failed cases"
echo "============================================================================"

if [ -f "./zig-out/lib/libfts5_icu.${LIB_EXT}" ]; then
    ${SQLITE3} < ./tests/test_universal_with_th_zh.sql | sed -e 's/|/ /g'  # format output for readability
else
    echo "WARNING: Universal tokenizer library not found, skipping TH/ZH test"
fi


