#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_OUTPUT="$(cd "$PROJECT_DIR/.." && pwd)/outputs/Luma.app"
APP_PATH="${1:-$DEFAULT_OUTPUT}"

case "$APP_PATH" in
    *.app) ;;
    *)
        echo "Output must end in .app" >&2
        exit 2
        ;;
esac

cd "$PROJECT_DIR"

if [[ -n "${LUMA_BINARY_PATH:-}" ]]; then
    case "$LUMA_BINARY_PATH" in
        /*) BINARY_PATH="$LUMA_BINARY_PATH" ;;
        *) BINARY_PATH="$PROJECT_DIR/$LUMA_BINARY_PATH" ;;
    esac
else
    swift build -c release
    BINARY_PATH="$PROJECT_DIR/.build/release/Luma"
fi

if [[ ! -x "$BINARY_PATH" ]]; then
    echo "Luma executable not found: $BINARY_PATH" >&2
    exit 3
fi

if [[ -e "$APP_PATH" ]]; then
    /bin/rm -rf "$APP_PATH"
fi

/bin/mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
/bin/cp "$BINARY_PATH" "$APP_PATH/Contents/MacOS/Luma"
/bin/cp "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
/bin/cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"

if [[ -n "${LUMA_VERSION:-}" ]]; then
    if [[ ! "$LUMA_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
        echo "LUMA_VERSION must contain two or three numeric components" >&2
        exit 4
    fi
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $LUMA_VERSION" "$APP_PATH/Contents/Info.plist"
fi

if [[ -n "${LUMA_BUILD_NUMBER:-}" ]]; then
    if [[ ! "$LUMA_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
        echo "LUMA_BUILD_NUMBER must be numeric" >&2
        exit 5
    fi
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $LUMA_BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"
fi

SIGN_IDENTITY="${LUMA_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign --force --deep --sign - --identifier com.luma.app "$APP_PATH"
else
    /usr/bin/codesign --force --deep --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" --identifier com.luma.app "$APP_PATH"
fi

echo "$APP_PATH"
