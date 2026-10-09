#!/bin/sh
# Builds the universal app and zips it for a GitHub release:
#   build/TerminalTerminal-<version>.zip
# With --publish, also creates a draft GitHub release v<version> with the zip attached
# (needs the gh CLI and a GitHub remote). Bump CFBundleShortVersionString in
# Support/Info.plist before releasing a new version.
set -eu
cd "$(dirname "$0")/.."

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
zip="build/TerminalTerminal-$version.zip"

./scripts/bundle.sh
rm -f "$zip"
# ditto keeps the bundle intact (plain zip can break it); the signature lives in the bundle, so
# extended attributes and resource forks are left out to avoid __MACOSX clutter.
ditto -c -k --norsrc --noextattr --keepParent "build/Terminal Terminal.app" "$zip"
echo "Packaged $zip ($(du -h "$zip" | cut -f1))"

if [ "${1:-}" = "--publish" ]; then
    gh release create "v$version" "$zip" --draft --title "Terminal Terminal $version" --notes "Universal build for macOS 13 or later.

The app isn't notarised, so macOS blocks it on first launch. After the first attempt, open System Settings → Privacy & Security and click **Open Anyway**, or run:

\`\`\`sh
xattr -dr com.apple.quarantine \"/Applications/Terminal Terminal.app\"
\`\`\`"
    echo "Created draft release v$version. Review and publish it on GitHub."
fi
