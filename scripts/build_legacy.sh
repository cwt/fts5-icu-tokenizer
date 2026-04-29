#!/bin/bash
# Build script for FTS5 ICU Tokenizer (Legacy API v1)

set -e

echo "Building FTS5 ICU Tokenizer (Legacy API v1)"

# Detect Homebrew ICU prefix (macOS keg-only workaround)
if command -v brew &>/dev/null; then
    ICU_PREFIX=$(brew --prefix icu4c 2>/dev/null || brew --prefix icu4c@78 2>/dev/null || echo "")
    if [ -n "$ICU_PREFIX" ]; then
        BREW_CMAKE_FLAGS="-DICU_ROOT=$ICU_PREFIX -DICU_INCLUDE_DIR=$ICU_PREFIX/include -DSQLite3_ROOT=$(brew --prefix sqlite)"
        echo "Using Homebrew ICU at: $ICU_PREFIX"
        echo "Using Homebrew SQLite at: $(brew --prefix sqlite)"
    fi
fi

# Detect shared library extension
case "$(uname -s)" in
    Darwin) LIB_EXT=dylib ;;
    *)      LIB_EXT=so ;;
esac

# Create build directory if it doesn't exist
mkdir -p build
cd build

# Check if a locale was provided as an argument
if [ $# -eq 0 ]; then
    echo "Building universal tokenizer (legacy API v1)"
    cmake .. $BREW_CMAKE_FLAGS -DAPI_VERSION=v1
else
    echo "Building tokenizer for locale: $1 (legacy API v1)"
    cmake .. $BREW_CMAKE_FLAGS -DAPI_VERSION=v1 -DLOCALE=$1
fi

# Build the project
cmake --build .

echo "Build completed successfully!"
echo "Libraries are located in the build directory:"
ls -la libfts5_icu*.${LIB_EXT}
echo ""
echo "Note: libfts5_icu*_legacy.${LIB_EXT} are the legacy API v1 libraries"