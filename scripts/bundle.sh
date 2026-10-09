#!/bin/sh
# Builds a universal (Apple silicon + Intel) release binary and wraps it in
# "build/Terminal Terminal.app" (LSUIElement, ad-hoc signed).
set -eu
cd "$(dirname "$0")/.."

arches="--arch arm64 --arch x86_64"
# The x86_64 deprecation warning refers to the SDK default; the binary still targets macOS 13.
swift build -c release $arches
app="build/Terminal Terminal.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release $arches --show-bin-path)/TerminalTerminal" "$app/Contents/MacOS/"
cp Support/Info.plist "$app/Contents/"
codesign --force --sign - "$app"
echo "Built $app"
