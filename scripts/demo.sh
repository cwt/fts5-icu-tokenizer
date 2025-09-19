#!/bin/bash
# Demonstration script for FTS5 ICU Tokenizer

echo "=========================================="
echo "FTS5 ICU Tokenizer Demo"
echo "=========================================="
echo ""

# Check if required tools are available
if ! command -v cmake &> /dev/null; then
    echo "Error: cmake is not installed"
    exit 1
fi

if ! command -v sqlite3 &> /dev/null; then
    echo "Error: sqlite3 is not installed"
    exit 1
fi

echo "1. Building the project..."
echo "--------------------------"
mkdir -p build
cd build
cmake .. -DLOCALE=ja
cmake --build .
cd ..

echo ""
echo "2. Checking built libraries..."
echo "-----------------------------"
ls -la build/libfts5_icu*.so

echo ""
echo "Testing the implementation..."
echo "---------------------------"
echo "Testing Japanese tokenizer..."
sqlite3 < tests/test_ja_tokenizer.sql

echo ""
echo "Testing universal tokenizer..."
sqlite3 < tests/test_universal_tokenizer.sql

echo ""
echo "=========================================="
echo "Demo completed successfully!"
echo "=========================================="
echo ""
echo "To use the implementation in your projects:"
echo "1. Load the library: .load ./build/libfts5_icu_ja.so"
echo "2. Use the same tokenizer name: tokenize = 'icu_ja'"
echo ""