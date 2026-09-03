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
swift build -c release

if [[ -e "$APP_PATH" ]]; then
    /bin/rm -rf "$APP_PATH"
fi

/bin/mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
/bin/cp "$PROJECT_DIR/.build/release/Luma" "$APP_PATH/Contents/MacOS/Luma"
/bin/cp "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
/bin/cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --deep --sign - --identifier com.luma.app "$APP_PATH"

echo "$APP_PATH"
