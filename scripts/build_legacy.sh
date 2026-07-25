#!/bin/bash
# Build script for FTS5 ICU Tokenizer (Legacy API v1)

set -e

echo "Building FTS5 ICU Tokenizer (Legacy API v1) with Zig 0.16.0..."
zig build -Dapi_version=v1
echo "Build completed successfully! Output in zig-out/lib/"