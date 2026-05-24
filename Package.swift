// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mia",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Mia",
            path: "Sources/Mia"
        )
    ]
)
