#!/bin/bash
set -e

# Path to zig executable binary
ZIG=${ZIG:-"zig"}

echo "Checking Zig source files with '${ZIG} ast-check'..."
${ZIG} ast-check build.zig
${ZIG} ast-check src/fts5_icu.zig
${ZIG} ast-check src/tokenizer.zig
${ZIG} ast-check src/rules.zig
${ZIG} ast-check src/c_icu.zig
${ZIG} ast-check src/compat.zig
${ZIG} ast-check src/test_transliterator.zig
${ZIG} ast-check src/locale_specific_tests.zig
${ZIG} ast-check src/test_locale_tokenizer.zig
echo "AST check passed!"
