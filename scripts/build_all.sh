#!/bin/bash

# Build script for all supported locales and the universal tokenizer
# This script builds separate libraries for each locale with optimized rules
# Builds the single v2 API implementation

echo "=================================================="
echo "Building all supported locales and the universal tokenizer..."
echo "Building the single v2 API implementation..."
echo "=================================================="

# Detect Homebrew packages (macOS keg-only workaround)
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

# Build each locale-specific tokenizer
for locale in "${LOCALES[@]}"; do
    echo ""
    echo "--------------------------------------------------"
    echo "Building libraries for locale: $locale"
    echo "--------------------------------------------------"
    
    # Don't clean previous build - we want to accumulate all libraries
    # make clean >/dev/null 2>&1
    
    # Configure with CMake
    echo "Configuring with CMake..."
    cmake .. -DAPI_VERSION=v2 $BREW_CMAKE_FLAGS -DLOCALE="$locale"
    
    if [ $? -ne 0 ]; then
        echo "ERROR: CMake configuration failed for locale $locale"
        exit 1
    fi
    
    # Build the project
    echo "Building the project..."
    rm -f CMakeFiles/fts5_icu.dir/src/fts5_icu.c.o
    make
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Build failed for locale $locale"
        exit 1
    fi
    
    # Libraries are already named correctly by CMake:
    # - libfts5_icu_legacy_${locale}.${LIB_EXT} (legacy implementation)
    # - libfts5_icu_${locale}.${LIB_EXT} (default/v2 implementation)
    # - libfts5_icu_${locale}_v2.${LIB_EXT} (v2 implementation)
    
    # Keep track of what we built
    BUILT_LIBRARIES+=("$locale")
    
    echo "Successfully built libraries for locale: $locale"
done

# Build the universal tokenizer
echo ""
echo "--------------------------------------------------"
echo "Building universal tokenizer"
echo "--------------------------------------------------"

# Don't clean - we want to keep all the locale-specific libraries we've built
# make clean >/dev/null 2>&1

# Configure with CMake (no locale specified)
echo "Configuring with CMake..."
cmake .. -DAPI_VERSION=v2 $BREW_CMAKE_FLAGS -DLOCALE=""

if [ $? -ne 0 ]; then
    echo "ERROR: CMake configuration failed for universal tokenizer"
    exit 1
fi

# Build the project
echo "Building the project..."
rm -f CMakeFiles/fts5_icu.dir/src/fts5_icu.c.o
make

if [ $? -ne 0 ]; then
    echo "ERROR: Build failed for universal tokenizer"
    exit 1
fi

echo "Successfully built universal libraries"

echo ""
echo "=================================================="
echo "All builds completed successfully!"
echo "=================================================="
echo "Built libraries:"
echo "  - Universal: libfts5_icu.${LIB_EXT} (v2 implementation)"
for locale in "${LOCALES[@]}"; do
    echo "  - $locale: libfts5_icu_${locale}.${LIB_EXT} (v2 implementation)"
done
echo ""
echo "To run tests, execute: ./scripts/test_all.sh"