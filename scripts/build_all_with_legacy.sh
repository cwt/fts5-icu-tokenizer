#!/bin/bash
# Build script for all supported locales and the universal tokenizer
# This script builds separate libraries for each locale with optimized rules
# Can build for both legacy v1 and v2 API versions

echo "=================================================="
echo "Building all supported locales and the universal tokenizer..."
echo "Building both legacy v1 and v2 API implementations..."
echo "=================================================="

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

# Clean any previous build artifacts
echo "Cleaning previous build artifacts..."
make clean >/dev/null 2>&1
rm -f libfts5_icu*.so libfts5_icu*.dylib

# List of all supported locales (standard ICU codes)
LOCALES=("ar" "el" "he" "ja" "ko" "ru" "th" "zh")

# Array to store built libraries
BUILT_LIBRARIES=()

# Build each locale-specific tokenizer for legacy v1 API
for locale in "${LOCALES[@]}"; do
    echo ""
    echo "--------------------------------------------------"
    echo "Building legacy v1 API libraries for locale: $locale"
    echo "--------------------------------------------------"

    # Configure with CMake for legacy v1 API
    echo "Configuring with CMake for legacy v1 API..."
    cmake .. $BREW_CMAKE_FLAGS -DAPI_VERSION=v1 -DLOCALE="$locale"

    if [ $? -ne 0 ]; then
        echo "ERROR: CMake configuration failed for locale $locale (legacy v1 API)"
        exit 1
    fi

    # Build the project
    echo "Building the project (legacy v1 API)..."
    rm -f CMakeFiles/fts5_icu.dir/src/fts5_icu.c.o
    make

    if [ $? -ne 0 ]; then
        echo "ERROR: Build failed for locale $locale (legacy v1 API)"
        exit 1
    fi

    # Keep track of what we built
    BUILT_LIBRARIES+=("$locale-v1")

    echo "Successfully built legacy v1 API libraries for locale: $locale"
done

# Build each locale-specific tokenizer for v2 API
for locale in "${LOCALES[@]}"; do
    echo ""
    echo "--------------------------------------------------"
    echo "Building v2 API libraries for locale: $locale"
    echo "--------------------------------------------------"

    # Configure with CMake for v2 API
    echo "Configuring with CMake for v2 API..."
    cmake .. $BREW_CMAKE_FLAGS -DAPI_VERSION=v2 -DLOCALE="$locale"

    if [ $? -ne 0 ]; then
        echo "ERROR: CMake configuration failed for locale $locale (v2 API)"
        exit 1
    fi

    # Build the project
    echo "Building the project (v2 API)..."
    rm -f CMakeFiles/fts5_icu.dir/src/fts5_icu.c.o
    make

    if [ $? -ne 0 ]; then
        echo "ERROR: Build failed for locale $locale (v2 API)"
        exit 1
    fi

    # Keep track of what we built
    BUILT_LIBRARIES+=("$locale-v2")

    echo "Successfully built v2 API libraries for locale: $locale"
done

# Build the universal tokenizer for legacy v1 API
echo ""
echo "--------------------------------------------------"
echo "Building universal tokenizer (legacy v1 API)"
echo "--------------------------------------------------"

# Configure with CMake (no locale specified, legacy v1 API)
echo "Configuring with CMake for legacy v1 API..."
cmake .. $BREW_CMAKE_FLAGS -DAPI_VERSION=v1 -DLOCALE=""

if [ $? -ne 0 ]; then
    echo "ERROR: CMake configuration failed for universal tokenizer (legacy v1 API)"
    exit 1
fi

# Build the project
echo "Building the project (legacy v1 API)..."
rm -f CMakeFiles/fts5_icu.dir/src/fts5_icu.c.o
make

if [ $? -ne 0 ]; then
    echo "ERROR: Build failed for universal tokenizer (legacy v1 API)"
    exit 1
fi

echo "Successfully built universal legacy v1 API libraries"

# Build the universal tokenizer for v2 API
echo ""
echo "--------------------------------------------------"
echo "Building universal tokenizer (v2 API)"
echo "--------------------------------------------------"

# Configure with CMake (no locale specified, v2 API)
echo "Configuring with CMake for v2 API..."
cmake .. $BREW_CMAKE_FLAGS -DAPI_VERSION=v2 -DLOCALE=""

if [ $? -ne 0 ]; then
    echo "ERROR: CMake configuration failed for universal tokenizer (v2 API)"
    exit 1
fi

# Build the project
echo "Building the project (v2 API)..."
rm -f CMakeFiles/fts5_icu.dir/src/fts5_icu.c.o
make

if [ $? -ne 0 ]; then
    echo "ERROR: Build failed for universal tokenizer (v2 API)"
    exit 1
fi

echo "Successfully built universal v2 API libraries"

echo ""
echo "=================================================="
echo "All builds completed successfully!"
echo "=================================================="
echo "Built libraries:"
echo "  - Universal legacy v1: libfts5_icu_legacy.${LIB_EXT} (legacy API v1 implementation)"
echo "  - Universal v2: libfts5_icu.${LIB_EXT} (current API v2 implementation)"
for locale in "${LOCALES[@]}"; do
    echo "  - $locale legacy v1: libfts5_icu_${locale}_legacy.${LIB_EXT} (legacy API v1 implementation)"
    echo "  - $locale v2: libfts5_icu_${locale}.${LIB_EXT} (current API v2 implementation)"
done
echo ""
echo "To run tests, execute: ./scripts/test_all.sh"