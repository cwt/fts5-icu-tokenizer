#!/bin/bash
# Test script for FTS5 ICU Tokenizer

set -e

echo "Testing FTS5 ICU Tokenizer"

# Build the project first
echo "Building project..."
./scripts/build_v2.sh

# Test universal tokenizer
echo "Testing universal tokenizer..."
sqlite3 < tests/test_universal_tokenizer.sql

# Test Japanese tokenizer
echo "Testing Japanese tokenizer..."
sqlite3 < tests/test_ja_tokenizer.sql

echo "All tests completed successfully!"