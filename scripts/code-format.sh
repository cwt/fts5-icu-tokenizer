#!/bin/bash

if ! command -v clang-format &>/dev/null; then
    echo "ERROR: clang-format not found. Install it:"
    echo "  macOS:  brew install clang-format"
    echo "  Linux:  apt install clang-format / dnf install clang-tools-extra"
    exit 1
fi

clang-format --verbose -i src/*.c src/*.h

# Remove trailing whitespace in all .c and .h files
if [[ "$OSTYPE" == "darwin"* ]]; then
    find src -name "*.[ch]" -exec sed -i '' -e 's/[[:space:]]*$//' {} \;
else
    find src -name "*.[ch]" -exec sed -i -e 's/[[:space:]]*$//' {} \;
fi
