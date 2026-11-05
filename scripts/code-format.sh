#!/bin/bash
# Path to zig executable binary
ZIG=${ZIG:-"zig"}

echo "Formatting Zig source code with '${ZIG} fmt .'..."
${ZIG} fmt .
