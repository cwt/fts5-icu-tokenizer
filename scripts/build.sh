#!/bin/bash
# Build script for FTS5 ICU Tokenizer

set -e

echo "Building FTS5 ICU Tokenizer"

# Create build directory if it doesn't exist
mkdir -p build
cd build

# Check if a locale was provided as an argument
if [ $# -eq 0 ]; then
    echo "Building universal tokenizer"
    cmake .. 
else
    echo "Building tokenizer for locale: $1"
    cmake .. -DLOCALE=$1
fi

# Build the project
cmake --build .

echo "Build completed successfully!"
echo "Libraries are located in the build directory:"
ls -la libfts5_icu*.so
echo ""
echo "Note: libfts5_icu*.so are the current default libraries"
echo "      libfts5_icu_legacy*.so are the legacy libraries"