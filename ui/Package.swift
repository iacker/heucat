// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HermesKeychainMenu",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HermesKeychainMenu", targets: ["HermesKeychainMenu"]),
    ],
    targets: [
        .executableTarget(
            name: "HermesKeychainMenu",
            path: "Sources/HermesKeychainMenu"
        ),
    ]
)
