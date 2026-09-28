// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeSidebar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ClaudeSidebar", path: "Sources/ClaudeSidebar")
    ]
)
