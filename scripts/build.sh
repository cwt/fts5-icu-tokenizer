#!/bin/bash
set -e

echo "Building FTS5 ICU Tokenizers with Zig 0.16.0..."
zig build "$@"
rm -rf build 2>/dev/null || true
ln -s zig-out/lib build
echo "Build completed successfully! Output in zig-out/lib/ (symlinked to ./build)"