#!/bin/bash
# Test script for FTS5 ICU Tokenizer (Legacy API v1)

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

REBUILD_FLAG=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --rebuild)
            REBUILD_FLAG="--rebuild"
            shift
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Usage: $0 [--rebuild]" >&2
            exit 1
            ;;
    esac
done

echo "Testing FTS5 ICU Tokenizer (Legacy API v1)"

# Build the project first
echo "Building project with Zig..."
./scripts/build.sh ${REBUILD_FLAG}

# Test extension version (legacy API v1)
echo "Testing extension version (legacy API v1)..."
if [ -f "./zig-out/lib/libfts5_icu_legacy.${LIB_EXT}" ]; then
    DETECTED_VERSION=$(${SQLITE3} :memory: ".load ./zig-out/lib/libfts5_icu_legacy" "SELECT fts5_icu_version();" 2>/dev/null)
    echo "Extension version (API v1): ${DETECTED_VERSION} (Expected: ${EXPECTED_VERSION})"
    if [ "${DETECTED_VERSION}" = "${EXPECTED_VERSION}" ]; then
        echo "SUCCESS: Version function test completed (API v1)"
    else
        echo "ERROR: Version mismatch (Got: '${DETECTED_VERSION}', Expected: '${EXPECTED_VERSION}')"
        exit 1
    fi
else
    echo "WARNING: Universal tokenizer library (legacy API v1) not found"
fi

# Test universal tokenizer with legacy API
echo "Testing universal tokenizer (legacy API v1)..."
if [ -f "./zig-out/lib/libfts5_icu_legacy.${LIB_EXT}" ]; then
    # Replace the library name in the SQL file to point to the legacy version in zig-out
    sed -E 's|\./zig-out/lib/libfts5_icu|\./zig-out/lib/libfts5_icu_legacy|g' ./tests/test_universal_tokenizer.sql | $SQLITE3
    echo "SUCCESS: Universal tokenizer test completed (legacy API v1)"
else
    echo "WARNING: Universal tokenizer library (legacy API v1) not found"
fi

# Test Japanese tokenizer with legacy API
echo "Testing Japanese tokenizer (legacy API v1)..."
if [ -f "./zig-out/lib/libfts5_icu_ja_legacy.${LIB_EXT}" ]; then
    # Replace the library name in the SQL file to point to the legacy version in zig-out
    sed -E 's|\./zig-out/lib/libfts5_icu_ja|\./zig-out/lib/libfts5_icu_ja_legacy|g' ./tests/test_ja_tokenizer.sql | $SQLITE3
    echo "SUCCESS: Japanese tokenizer test completed (legacy API v1)"
else
    echo "WARNING: Japanese tokenizer library (legacy API v1) not found"
fi

echo "All legacy API v1 tests completed successfully!"