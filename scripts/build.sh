#!/bin/bash
set -e

# Path to zig executable binary
ZIG=${ZIG:-"zig"}

# Build script for FTS5 ICU Tokenizer.
# Supported Zig versions: 0.16.0, 0.17.0, 0.17.1
#
# Usage: ./scripts/build.sh [--rebuild]
#
#   (no options)   clean build of all tokenizers (API v1 and v2, default)
#   --rebuild      skip clearing .cache/.zig-cache/zig-out (reuse cached builds)
#
# Environment variables:
#   ZIG            path to zig executable binary (default: "zig")
#                  e.g. ZIG=/path/to/zig-0.17.1/zig ./scripts/build.sh
#
# The ./build symlink to zig-out/lib is (re)created in all cases.

REBUILD=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --rebuild)
            REBUILD=1
            shift
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Usage: $0 [--rebuild]" >&2
            exit 1
            ;;
    esac
done

if [ "${REBUILD}" -eq 0 ]; then
    rm -rf .cache .zig-cache build zig-out 2>/dev/null || true
fi

echo "Building all FTS5 ICU Tokenizers (API v1 + v2) with Zig $(${ZIG} version)..."
${ZIG} build

ln -sfn zig-out/lib build
echo "Build completed successfully! Output in zig-out/lib/ (symlinked to ./build)"
