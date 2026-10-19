// swift-tools-version:5.10
// File conversion engine (formats, tools, wheel logic) used by tully's File Converter.
// Ported from the Kumquat project; UI-free and fully unit-tested.
import PackageDescription

let package = Package(
    name: "KumquatCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KumquatCore", targets: ["KumquatCore"]),
    ],
    targets: [
        .target(name: "KumquatCore"),
        .testTarget(name: "KumquatCoreTests", dependencies: ["KumquatCore"]),
    ]
)
