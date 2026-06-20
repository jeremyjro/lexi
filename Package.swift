// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lexi",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Lexi",
            targets: ["Lexi"]
        )
    ],
    dependencies: [
        // Add dependencies here as needed
    ],
    targets: [
        .executableTarget(
            name: "Lexi",
            dependencies: [],
            path: "Sources/Lexi"
        )
    ]
)