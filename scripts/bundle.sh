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
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release $arches --show-bin-path)/TerminalTerminal" "$app/Contents/MacOS/"
cp Support/Info.plist "$app/Contents/"
# Icon Composer icon → Assets.car (Liquid Glass on macOS 26) and Icon.icns (earlier macOS).
xcrun actool Sources/TerminalTerminal/Icon/Icon.icon --compile "$app/Contents/Resources" --app-icon Icon \
    --platform macosx --target-device mac --minimum-deployment-target 13.0 \
    --output-partial-info-plist build/icon-partial.plist >/dev/null
codesign --force --sign - "$app"
echo "Built $app"
