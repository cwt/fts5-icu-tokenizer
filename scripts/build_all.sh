#!/bin/bash
set -e

echo "Building all universal and locale-specific tokenizers with Zig 0.16.0..."
zig build
rm -rf build 2>/dev/null || true
ln -s zig-out/lib build
echo "All tokenizer libraries built in zig-out/lib/ (symlinked to ./build)"