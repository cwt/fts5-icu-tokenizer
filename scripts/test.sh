#!/bin/bash
# Test script for FTS5 ICU Tokenizer

set -e

# Prefer Homebrew sqlite3 (Apple's system sqlite3 lacks .load support)
if command -v brew &>/dev/null && [ -x "$(brew --prefix sqlite)/bin/sqlite3" ]; then
    SQLITE3="$(brew --prefix sqlite)/bin/sqlite3"
elif command -v sqlite3 &> /dev/null; then
    SQLITE3=sqlite3
else
    echo "ERROR: sqlite3 is not installed or not in PATH"
    exit 1
fi

echo "Testing FTS5 ICU Tokenizer"

# Build the project first
echo "Building project..."
./scripts/build.sh

# Test universal tokenizer
echo "Testing universal tokenizer..."
$SQLITE3 < tests/test_universal_tokenizer.sql

# Test Japanese tokenizer
echo "Testing Japanese tokenizer..."
$SQLITE3 < tests/test_ja_tokenizer.sql

echo "All tests completed successfully!"