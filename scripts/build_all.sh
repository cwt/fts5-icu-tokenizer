#!/bin/bash

# Build script for all supported locales and the universal tokenizer
# This script builds separate libraries for each locale with optimized rules

echo "Building all supported locales and the universal tokenizer..."

# Create build directory if it doesn't exist
mkdir -p build
cd build

# List of all supported locales (standard ICU codes)
LOCALES=("ar" "el" "he" "ja" "ko" "ru" "th" "zh")

# Build each locale-specific tokenizer
for locale in "${LOCALES[@]}"; do
    echo ""
    echo "=================================================="
    echo "Building tokenizer for locale: $locale"
    echo "=================================================="
    
    # Clean previous build
    make clean >/dev/null 2>&1
    
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
    
    # Rename the library to preserve it
    echo "Renaming library to preserve it..."
    mv libfts5_icu_${locale}.so libfts5_icu_${locale}.so.tmp
    
    echo "Successfully built libfts5_icu_${locale}.so"
done

# Build the universal tokenizer
echo ""
echo "=================================================="
echo "Building universal tokenizer"
echo "=================================================="

# Clean previous build
make clean >/dev/null 2>&1

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

echo "Successfully built libfts5_icu.so"

# Restore all the locale-specific libraries
echo ""
echo "=================================================="
echo "Restoring locale-specific libraries"
echo "=================================================="

for locale in "${LOCALES[@]}"; do
    if [ -f "libfts5_icu_${locale}.so.tmp" ]; then
        mv "libfts5_icu_${locale}.so.tmp" "libfts5_icu_${locale}.so"
        echo "Restored libfts5_icu_${locale}.so"
    fi
done

echo ""
echo "=================================================="
echo "All builds completed successfully!"
echo "=================================================="
echo "Built libraries:"
echo "  - Universal: libfts5_icu.so"
for locale in "${LOCALES[@]}"; do
    echo "  - $locale: libfts5_icu_${locale}.so"
done
echo ""
echo "To run tests, execute: ./scripts/test_all.sh"