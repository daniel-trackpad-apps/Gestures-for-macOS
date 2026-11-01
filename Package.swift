// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GesturesForMacOS",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "GesturesForMacOS", path: "Sources/GesturesForMacOS")
    ]
)
