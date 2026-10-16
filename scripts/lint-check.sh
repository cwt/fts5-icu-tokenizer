#!/bin/bash
set -e

echo "Checking Zig source files with 'zig ast-check'..."
zig ast-check build.zig
zig ast-check src/fts5_icu.zig
zig ast-check src/tokenizer.zig
zig ast-check src/rules.zig
zig ast-check src/c_icu.zig
zig ast-check src/compat.zig
zig ast-check src/test_transliterator.zig
zig ast-check src/locale_specific_tests.zig
zig ast-check src/test_locale_tokenizer.zig
echo "AST check passed!"
