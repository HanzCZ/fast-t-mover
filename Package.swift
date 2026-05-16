// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "FastTMover",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FastTMover",
            path: "Sources/FastTMover"
        )
    ]
)
