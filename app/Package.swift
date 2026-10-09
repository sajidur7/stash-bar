// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StashBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "StashBar", targets: ["StashBar"])
    ],
    targets: [
        .executableTarget(
            name: "StashBar",
            path: "Sources/StashBar"
        ),
        .testTarget(
            name: "StashBarTests",
            dependencies: ["StashBar"],
            path: "Tests/StashBarTests"
        )
    ]
)
