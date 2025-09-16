#!/bin/bash

# Build script for the ICU transliterator test program

echo "Building ICU transliterator test programs..."

# Create build directory if it doesn't exist
mkdir -p build
cd build

# Configure with CMake
echo "Configuring with CMake..."
cmake ..

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