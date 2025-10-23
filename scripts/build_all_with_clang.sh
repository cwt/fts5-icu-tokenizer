#!/bin/bash

# Build script for all supported locales and the universal tokenizer
# This script builds separate libraries for each locale with optimized rules
# Builds the single v2 API implementation
# Using clang for compilation to check portability

echo "=================================================="
echo "Building all supported locales and the universal tokenizer..."
echo "Building the single v2 API implementation..."
echo "Using clang compiler for portability check..."
echo "=================================================="

# Create build directory if it doesn't exist
mkdir -p build
cd build

# Clean any previous build artifacts
echo "Cleaning previous build artifacts..."
make clean >/dev/null 2>&1
rm -f libfts5_icu*.so

# Set environment variables to use clang instead of gcc
export CC=clang
export CXX=clang++

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
    cmake .. -DLOCALE="$locale"
    
    if [ $? -ne 0 ]; then
        echo "ERROR: CMake configuration failed for locale $locale"
        exit 1
    fi
    
    # Build the project
    echo "Building the project..."
    make
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Build failed for locale $locale"
        exit 1
    fi
    
    # Libraries are already named correctly by CMake:
    # - libfts5_icu_legacy_${locale}.so (legacy implementation)
    # - libfts5_icu_${locale}.so (default/v2 implementation)
    # - libfts5_icu_${locale}_v2.so (v2 implementation)
    
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
cmake .. -DLOCALE=""

if [ $? -ne 0 ]; then
    echo "ERROR: CMake configuration failed for universal tokenizer"
    exit 1
fi

# Build the project
echo "Building the project..."
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
echo "  - Universal: libfts5_icu.so (v2 implementation)"
for locale in "${LOCALES[@]}"; do
    echo "  - $locale: libfts5_icu_${locale}.so (v2 implementation)"
done
echo ""
echo "To run tests, execute: ./scripts/test_all.sh"