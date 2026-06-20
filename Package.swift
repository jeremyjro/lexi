// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CursorAssistant",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CursorAssistant",
            targets: ["CursorAssistant"]
        )
    ],
    dependencies: [
        // Add dependencies here as needed
    ],
    targets: [
        .executableTarget(
            name: "CursorAssistant",
            dependencies: [],
            path: "Sources/CursorAssistant"
        )
    ]
)