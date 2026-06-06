// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Harmonic",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Harmonic", targets: ["Harmonic"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Harmonic",
            dependencies: [],
            path: "Sources/Harmonic",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
