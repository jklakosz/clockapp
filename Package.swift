// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clockapp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Clockapp",
            path: "Sources/Clockapp"
        )
    ]
)
