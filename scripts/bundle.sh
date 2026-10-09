#!/bin/sh
# Builds a release binary and wraps it in "build/Terminal Terminal.app" (LSUIElement, ad-hoc signed).
set -eu
cd "$(dirname "$0")/.."

swift build -c release
app="build/Terminal Terminal.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/TerminalTerminal" "$app/Contents/MacOS/"
cp Support/Info.plist "$app/Contents/"
codesign --force --sign - "$app"
echo "Built $app"
