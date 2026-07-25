#!/bin/bash
echo "Checking Zig source files with 'zig ast-check'..."
zig ast-check src/fts5_icu.zig
zig ast-check src/tokenizer.zig
zig ast-check src/rules.zig
echo "AST check passed!"
