// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "HPA",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "HPA",
            path: "Sources/HPA"
        )
    ]
)
