#!/bin/bash
# Test script for FTS5 ICU Tokenizer

set -e

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

echo "Testing FTS5 ICU Tokenizer"

# Build the project first
echo "Building project with Zig..."
./scripts/build.sh

# Test extension version
echo "Testing extension version..."
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
    echo "ERROR: Universal tokenizer library not found in ./zig-out/lib/"
    exit 1
fi

# Test universal tokenizer
echo "Testing universal tokenizer..."
$SQLITE3 < tests/test_universal_tokenizer.sql

# Test Japanese tokenizer
echo "Testing Japanese tokenizer..."
$SQLITE3 < tests/test_ja_tokenizer.sql

echo "All tests completed successfully!"