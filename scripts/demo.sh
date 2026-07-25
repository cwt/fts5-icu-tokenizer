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

# Prefer Homebrew sqlite3 (Apple's system sqlite3 lacks .load support)
if command -v brew &>/dev/null && [ -x "$(brew --prefix sqlite)/bin/sqlite3" ]; then
    SQLITE3="$(brew --prefix sqlite)/bin/sqlite3"
else
    SQLITE3=sqlite3
fi

# Detect Homebrew packages for cmake (macOS keg-only workaround)
if command -v brew &>/dev/null; then
    ICU_PREFIX=$(brew --prefix icu4c 2>/dev/null || brew --prefix icu4c@78 2>/dev/null || echo "")
    if [ -n "$ICU_PREFIX" ]; then
        BREW_CMAKE_FLAGS="-DICU_ROOT=$ICU_PREFIX -DICU_INCLUDE_DIR=$ICU_PREFIX/include -DSQLite3_ROOT=$(brew --prefix sqlite)"
    fi
fi

# Detect shared library extension
case "$(uname -s)" in
    Darwin) LIB_EXT=dylib ;;
    *)      LIB_EXT=so ;;
esac

echo "1. Building the project..."
echo "--------------------------"
mkdir -p build
cd build
cmake .. $BREW_CMAKE_FLAGS -DLOCALE=ja
cmake --build .
cd ..

echo ""
echo "2. Checking built libraries..."
echo "-----------------------------"
ls -la build/libfts5_icu*.${LIB_EXT}

echo ""
echo "Testing the implementation..."
echo "---------------------------"
echo "Testing Japanese tokenizer..."
$SQLITE3 < tests/test_ja_tokenizer.sql

echo ""
echo "Testing universal tokenizer..."
$SQLITE3 < tests/test_universal_tokenizer.sql

echo ""
echo "=========================================="
echo "Demo completed successfully!"
echo "=========================================="
echo ""
echo "To use the implementation in your projects:"
echo "1. Load the library: .load ./zig-out/lib/libfts5_icu_ja.${LIB_EXT}"
echo "2. Use the same tokenizer name: tokenize = 'icu_ja'"
echo ""