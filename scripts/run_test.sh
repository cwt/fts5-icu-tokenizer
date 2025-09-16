#!/bin/bash

# Script to build and run the ICU transliterator test programs

echo "Building and running ICU transliterator test programs..."

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
    echo "Running the original test program..."
    echo "=========================="
    ./test_transliterator
    
    echo ""
    echo "Running the locale-specific test program..."
    echo "=========================="
    ./locale_specific_tests
else
    echo "Build failed!"
    exit 1
fi