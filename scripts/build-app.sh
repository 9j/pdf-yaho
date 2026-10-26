#!/bin/sh
# Builds Pagecraft.app into ./build. Usage: scripts/build-app.sh [debug|release]
# Set ARCHS="arm64" for a faster single-architecture build.
set -eu
cd "$(dirname "$0")/.."

config="${1:-release}"
version="0.2.0"
arch_flags=""
for arch in ${ARCHS:-arm64 x86_64}; do arch_flags="$arch_flags --arch $arch"; done
# shellcheck disable=SC2086
swift build -c "$config" $arch_flags
# shellcheck disable=SC2086
bin="$(swift build -c "$config" $arch_flags --show-bin-path)/Pagecraft"

app="build/Pagecraft.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Pagecraft"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Pagecraft</string>
    <key>CFBundleIdentifier</key><string>org.pagecraft.Pagecraft</string>
    <key>CFBundleName</key><string>Pagecraft</string>
    <key>CFBundleDisplayName</key><string>Pagecraft</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>PDF Document</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>com.adobe.pdf</string></array>
            <key>NSUbiquitousDocumentUserActivityType</key><string>org.pagecraft.editing</string>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
echo "Built $app"
