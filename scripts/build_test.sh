#!/bin/bash

# Build script for the ICU transliterator test program

echo "Building ICU transliterator test programs..."

# Detect Homebrew ICU prefix (macOS keg-only workaround)
if command -v brew &>/dev/null; then
    ICU_PREFIX=$(brew --prefix icu4c 2>/dev/null || brew --prefix icu4c@78 2>/dev/null || echo "")
    if [ -n "$ICU_PREFIX" ]; then
        BREW_CMAKE_FLAGS="-DICU_ROOT=$ICU_PREFIX -DICU_INCLUDE_DIR=$ICU_PREFIX/include -DSQLite3_ROOT=$(brew --prefix sqlite)"
        echo "Using Homebrew ICU at: $ICU_PREFIX"
        echo "Using Homebrew SQLite at: $(brew --prefix sqlite)"
    fi
fi

# Create build directory if it doesn't exist
mkdir -p build
cd build

# Configure with CMake
echo "Configuring with CMake..."
cmake .. $BREW_CMAKE_FLAGS

# Build the project
echo "Building the project..."
make

# Check if build was successful
if [ $? -eq 0 ]; then
    echo "Build successful!"
    echo ""
    echo "To run the original test program, execute:"
    echo "  ./build/test_transliterator"
    echo ""
    echo "To run the locale-specific test program, execute:"
    echo "  ./build/locale_specific_tests"
else
    echo "Build failed!"
    exit 1
fi