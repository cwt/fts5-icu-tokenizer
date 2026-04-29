#!/bin/bash

# Build script for all supported locales and the universal tokenizer (Legacy API v1 only)
# This script builds separate libraries for each locale with optimized rules
# Builds only the legacy API v1 implementation

echo "=================================================="
echo "Building all supported locales and the universal tokenizer..."
echo "Building only legacy API v1 implementation..."
echo "=================================================="

# Create build directory if it doesn't exist
mkdir -p build
cd build

# Clean any previous build artifacts
echo "Cleaning previous build artifacts..."
make clean >/dev/null 2>&1
rm -f libfts5_icu*.so

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
    cmake .. -DAPI_VERSION=v1 -DLOCALE="$locale"

    if [ $? -ne 0 ]; then
        echo "ERROR: CMake configuration failed for locale $locale (legacy v1 API)"
        exit 1
    fi

    # Build the project
    echo "Building the project (legacy v1 API)..."
    make

    if [ $? -ne 0 ]; then
        echo "ERROR: Build failed for locale $locale (legacy v1 API)"
        exit 1
    fi

    # Keep track of what we built
    BUILT_LIBRARIES+=("$locale")

    echo "Successfully built legacy v1 API libraries for locale: $locale"
done

# Build the universal tokenizer for legacy v1 API
echo ""
echo "--------------------------------------------------"
echo "Building universal tokenizer (legacy v1 API)"
echo "--------------------------------------------------"

# Configure with CMake (no locale specified, legacy v1 API)
echo "Configuring with CMake for legacy v1 API..."
cmake .. -DAPI_VERSION=v1 -DLOCALE=""

if [ $? -ne 0 ]; then
        echo "ERROR: CMake configuration failed for universal tokenizer (legacy v1 API)"
        exit 1
    fi

# Build the project
echo "Building the project (legacy v1 API)..."
make

if [ $? -ne 0 ]; then
    echo "ERROR: Build failed for universal tokenizer (legacy v1 API)"
    exit 1
fi

echo "Successfully built universal legacy v1 API libraries"

echo ""
echo "=================================================="
echo "All builds completed successfully!"
echo "=================================================="
echo "Built libraries:"
echo "  - Universal: libfts5_icu_legacy.so (legacy API v1 implementation)"
for locale in "${LOCALES[@]}"; do
    echo "  - $locale: libfts5_icu_${locale}_legacy.so (legacy API v1 implementation)"
done
echo ""
echo "To run tests, execute: ./scripts/test_all_legacy.sh"