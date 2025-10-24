#!/bin/bash

clang-format --verbose -i src/*.c src/*.h

# Remove trailing whitespace in all .c and .h files
find src -name "*.[ch]" -exec sed -i 's/[[:space:]]*$//' {} \;
