// swift-tools-version:5.10
import Foundation
import PackageDescription

// PDFium (for editing page text and images) is optional: run scripts/fetch-pdfium.sh to enable it.
let vendor = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Vendor/pdfium/lib").path
let hasPDFium = FileManager.default.fileExists(atPath: vendor + "/libpdfium.dylib")

let package = Package(
    name: "PDFYaho",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PDFYaho", targets: ["PDFYaho"]),
        .library(name: "PDFYahoCore", targets: ["PDFYahoCore"]),
    ],
    targets: [
        .systemLibrary(name: "CPDFium"),
        .target(
            name: "PDFYahoCore",
            dependencies: hasPDFium ? ["CPDFium"] : [],
            swiftSettings: hasPDFium ? [.define("PDFIUM")] : [],
            linkerSettings: hasPDFium ? [.unsafeFlags([
                "-L", vendor,
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                "-Xlinker", "-rpath", "-Xlinker", vendor,
            ])] : []
        ),
        .executableTarget(name: "PDFYaho", dependencies: ["PDFYahoCore"],
                          swiftSettings: hasPDFium ? [.define("PDFIUM")] : []),
        .testTarget(name: "PDFYahoCoreTests", dependencies: ["PDFYahoCore"],
                    swiftSettings: hasPDFium ? [.define("PDFIUM")] : []),
    ]
)
