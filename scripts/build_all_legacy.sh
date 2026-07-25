#!/bin/bash
set -e

echo "Building all legacy (API v1) universal and locale-specific tokenizers with Zig 0.16.0..."
zig build -Dapi_version=v1
echo "All legacy tokenizer libraries built in zig-out/lib/"