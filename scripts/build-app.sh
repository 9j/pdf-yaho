#!/bin/sh
# Builds "PDF Yaho.app" into ./build. Usage: scripts/build-app.sh [debug|release]
# Set ARCHS="arm64" for a faster single-architecture build.
set -eu
cd "$(dirname "$0")/.."

config="${1:-release}"
# PDFium powers editing page text and images; without it the app builds with that feature off.
[ "${NO_PDFIUM:-}" = "1" ] || scripts/fetch-pdfium.sh
version="0.3.3"
arch_flags=""
for arch in ${ARCHS:-arm64 x86_64}; do arch_flags="$arch_flags --arch $arch"; done
# shellcheck disable=SC2086
swift build -c "$config" $arch_flags
# shellcheck disable=SC2086
bin="$(swift build -c "$config" $arch_flags --show-bin-path)/PDFYaho"

app="build/PDF Yaho.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/PDFYaho"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
if otool -L "$app/Contents/MacOS/PDFYaho" | grep -q libpdfium; then
    mkdir -p "$app/Contents/Frameworks" "$app/Contents/Resources/Licenses/PDFium"
    cp Vendor/pdfium/lib/libpdfium.dylib "$app/Contents/Frameworks/"
    cp Vendor/pdfium/LICENSE Vendor/pdfium/licenses/* "$app/Contents/Resources/Licenses/PDFium/"
    # Drop the development rpath into Vendor/ so the app only loads its own copy.
    install_name_tool -delete_rpath "$(pwd)/Vendor/pdfium/lib" "$app/Contents/MacOS/PDFYaho" 2>/dev/null || true
fi

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>PDFYaho</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string></array>
    <key>CFBundleIdentifier</key><string>org.pdfyaho.PDFYaho</string>
    <key>CFBundleName</key><string>PDF Yaho</string>
    <key>CFBundleDisplayName</key><string>PDF Yaho</string>
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
            <key>NSUbiquitousDocumentUserActivityType</key><string>org.pdfyaho.editing</string>
        </dict>
    </array>
</dict>
</plist>
PLIST

[ -d "$app/Contents/Frameworks" ] && codesign --force --sign - "$app/Contents/Frameworks/libpdfium.dylib"
codesign --force --sign - "$app"
echo "Built $app"
