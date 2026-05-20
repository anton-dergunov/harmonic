// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpotifyController",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SpotifyController", targets: ["SpotifyController"]),
    ],
    targets: [
        .systemLibrary(
            name: "CCommonCrypto",
            path: "Sources/CCommonCrypto"
        ),
        .executableTarget(
            name: "SpotifyController",
            dependencies: ["CCommonCrypto"],
            path: "Sources/SpotifyController",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
