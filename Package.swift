// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clipper",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Clipper", targets: ["Clipper"])],
    targets: [
        .executableTarget(name: "Clipper"),
        .testTarget(name: "ClipperTests", dependencies: ["Clipper"])
    ],
    swiftLanguageModes: [.v5]
)
