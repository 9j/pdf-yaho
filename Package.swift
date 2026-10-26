// swift-tools-version:5.10
import Foundation
import PackageDescription

// PDFium (for editing page text and images) is optional: run scripts/fetch-pdfium.sh to enable it.
let vendor = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Vendor/pdfium/lib").path
let hasPDFium = FileManager.default.fileExists(atPath: vendor + "/libpdfium.dylib")

let package = Package(
    name: "Pagecraft",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pagecraft", targets: ["Pagecraft"]),
        .library(name: "PagecraftCore", targets: ["PagecraftCore"]),
    ],
    targets: [
        .systemLibrary(name: "CPDFium"),
        .target(
            name: "PagecraftCore",
            dependencies: hasPDFium ? ["CPDFium"] : [],
            swiftSettings: hasPDFium ? [.define("PDFIUM")] : [],
            linkerSettings: hasPDFium ? [.unsafeFlags([
                "-L", vendor,
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                "-Xlinker", "-rpath", "-Xlinker", vendor,
            ])] : []
        ),
        .executableTarget(name: "Pagecraft", dependencies: ["PagecraftCore"],
                          swiftSettings: hasPDFium ? [.define("PDFIUM")] : []),
        .testTarget(name: "PagecraftCoreTests", dependencies: ["PagecraftCore"],
                    swiftSettings: hasPDFium ? [.define("PDFIUM")] : []),
    ]
)
