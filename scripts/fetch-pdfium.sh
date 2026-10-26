#!/bin/sh
# Downloads the prebuilt PDFium (bblanchon/pdfium-binaries, BSD/Apache licensed) used for editing page content.
# Pinned and checksummed; installs into Vendor/pdfium. Re-run after changing the version.
set -e
version="chromium/8111"
sha256="043638ac3d7830ff43a7cdbf0623e6b73d70d5cbff9e12e9531d5be7e03b8e9d"
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/Vendor/pdfium"
[ -f "$dest/lib/libpdfium.dylib" ] && [ "$(cat "$dest/PINNED" 2>/dev/null)" = "$version" ] && exit 0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/pdfium.tgz" "https://github.com/bblanchon/pdfium-binaries/releases/download/$(echo "$version" | sed 's|/|%2F|')/pdfium-mac-univ.tgz"
echo "$sha256  $tmp/pdfium.tgz" | shasum -a 256 -c - >/dev/null
rm -rf "$dest"; mkdir -p "$dest"
tar -xzf "$tmp/pdfium.tgz" -C "$dest"
rm -f "$dest/include/fpdfview.h.orig"
# Load it from the app's Frameworks folder (or the rpath set for development builds).
install_name_tool -id @rpath/libpdfium.dylib "$dest/lib/libpdfium.dylib" 2>/dev/null
codesign --force --sign - "$dest/lib/libpdfium.dylib" >/dev/null 2>&1
echo "$version" > "$dest/PINNED"
echo "PDFium $version installed in Vendor/pdfium"
