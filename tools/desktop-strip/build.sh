#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
output="$root/.build/Terminal Kit Work Strip.app"
mkdir -p "$output/Contents/MacOS" "$root/.build/module-cache"
xcrun swiftc "$root/main.swift" -O -module-cache-path "$root/.build/module-cache" -o "$output/Contents/MacOS/WorkStrip"
cat > "$output/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.terminal-kit.work-strip</string>
<key>CFBundleName</key><string>Terminal Kit Work Strip</string>
<key>CFBundleExecutable</key><string>WorkStrip</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$output"
printf '%s\n' "$output"
