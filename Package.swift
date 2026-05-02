// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MotiSig",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
    ],
    products: [
        .library(name: "MotiSig", targets: ["MotiSig"]),
    ],
    targets: [
        .target(
            name: "MotiSig",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "MotiSigIntegrationTests",
            dependencies: ["MotiSig"],
            path: "Tests/MotiSigIntegrationTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "MotiSigTests",
            dependencies: ["MotiSig"],
            path: "Tests/MotiSigTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
