// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OhhLens",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OhhLensCore", targets: ["OhhLensCore"]),
        .executable(name: "OhhLensApp", targets: ["OhhLensApp"])
    ],
    targets: [
        .target(
            name: "OhhLensCore",
            path: "Sources/OhhLensCore"
        ),
        .executableTarget(
            name: "OhhLensApp",
            dependencies: ["OhhLensCore"],
            path: "Sources/OhhLensApp"
        ),
        .testTarget(
            name: "OhhLensCoreTests",
            dependencies: ["OhhLensCore"],
            path: "Tests/OhhLensCoreTests"
        )
    ]
)
