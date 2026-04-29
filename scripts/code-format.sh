#!/bin/bash

if ! command -v clang-format &>/dev/null; then
    echo "ERROR: clang-format not found. Install it:"
    echo "  macOS:  brew install clang-format"
    echo "  Linux:  apt install clang-format / dnf install clang-tools-extra"
    exit 1
fi

clang-format --verbose -i src/*.c src/*.h

# Remove trailing whitespace in all .c and .h files (perl -i works on both macOS and Linux)
find src -name "*.[ch]" -exec perl -i -pe 's/[[:space:]]+$//' {} \;
