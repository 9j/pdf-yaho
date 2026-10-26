#!/bin/sh
# Builds Resources/AppIcon.icns from Resources/AppIcon-source.png (1024 px, transparent corners).
# The source was generated with OpenAI gpt-image-2.5-flare; the tile is scaled onto Apple's 824 px grid.
set -eu
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swift - "$tmp/AppIcon-1024.png" <<'SWIFT'
import AppKit
let source = NSImage(contentsOfFile: "Resources/AppIcon-source.png")!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
// The generated tile spans about 790 px; scale it to the 824 px icon grid, centred.
let scale: CGFloat = 1.04
let side = 1024 * scale
source.draw(in: NSRect(x: (1024 - side) / 2, y: (1024 - side) / 2, width: side, height: side))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT
set="$tmp/AppIcon.iconset"
mkdir -p "$set"
for size in 16 32 128 256 512; do
    sips -z $size $size "$tmp/AppIcon-1024.png" --out "$set/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$tmp/AppIcon-1024.png" --out "$set/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
