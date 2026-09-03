#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOYMENT_TARGET="${LUMA_DEPLOYMENT_TARGET:-14.0}"
BUILD_ROOT="${LUMA_UNIVERSAL_BUILD_ROOT:-$PROJECT_DIR/.build/universal}"

if [[ ! "$DEPLOYMENT_TARGET" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "LUMA_DEPLOYMENT_TARGET must be a numeric macOS version" >&2
    exit 2
fi

ARM64_ROOT="$BUILD_ROOT/arm64"
X86_64_ROOT="$BUILD_ROOT/x86_64"
OUTPUT="$BUILD_ROOT/Luma"

cd "$PROJECT_DIR"
swift build -c release \
    --triple "arm64-apple-macosx$DEPLOYMENT_TARGET" \
    --scratch-path "$ARM64_ROOT"
swift build -c release \
    --triple "x86_64-apple-macosx$DEPLOYMENT_TARGET" \
    --scratch-path "$X86_64_ROOT"

ARM64_BINARY="$ARM64_ROOT/arm64-apple-macosx/release/Luma"
X86_64_BINARY="$X86_64_ROOT/x86_64-apple-macosx/release/Luma"

if [[ ! -x "$ARM64_BINARY" || ! -x "$X86_64_BINARY" ]]; then
    echo "One or more architecture builds are missing" >&2
    exit 3
fi

/bin/mkdir -p "$BUILD_ROOT"
/usr/bin/lipo -create "$ARM64_BINARY" "$X86_64_BINARY" -output "$OUTPUT"
/usr/bin/lipo "$OUTPUT" -verify_arch arm64 x86_64

echo "$OUTPUT"
