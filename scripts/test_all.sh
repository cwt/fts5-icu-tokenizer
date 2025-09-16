#!/bin/bash

# Test script for all supported locales and the universal tokenizer
# This script tests each built library with appropriate sample text

echo "Testing all supported locales and the universal tokenizer..."

# Check if sqlite3 is available
if ! command -v sqlite3 &> /dev/null; then
    echo "ERROR: sqlite3 is not installed or not in PATH"
    exit 1
fi

# Test the universal tokenizer
echo ""
echo "=================================================="
echo "Testing universal tokenizer"
echo "=================================================="
if [ -f "./build/libfts5_icu.so" ]; then
    sqlite3 < ./tests/test_universal_tokenizer.sql
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
    
    if [ -f "./build/libfts5_icu_${locale}.so" ]; then
        if [ -f "./$test_script" ]; then
            sqlite3 < ./$test_script
            if [ $? -ne 0 ]; then
                echo "ERROR: Test failed for $locale tokenizer"
            else
                echo "SUCCESS: $locale tokenizer test completed"
            fi
        else
            echo "WARNING: Test script $test_script not found"
        fi
    else
        echo "WARNING: Library libfts5_icu_${locale}.so not found"
    fi
done

echo ""
echo "=================================================="
echo "All tests completed!"
echo "=================================================="