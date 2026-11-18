// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "Ory",
    platforms: [
        .iOS(.v14),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Ory",
            targets: ["Ory"]
        ),
        .library(
            name: "OryTestDoubles",
            targets: ["OryTestDoubles"]
        ),
        // Simulator-only relaxed device attestation. Depend on this product only for
        // Simulator or test builds; its code compiles to nothing on device builds, and
        // its swift-certificates dependency is linked only when this product is used.
        .library(
            name: "OrySimulator",
            targets: ["OrySimulator"]
        ),
    ],
    dependencies: [
        // Used only by the OrySimulator target to build a self-signed attestation
        // chain for the Simulator. Not a dependency of the Ory product.
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.19.2"),
        .package(url: "https://github.com/jedisct1/swift-sodium.git", exact: "0.11.0"),
    ],
    targets: [
        .target(
            name: "_OryGeneratedAPI"
        ),
        .target(
            name: "Ory",
            dependencies: [
                "_OryGeneratedAPI",
                .product(name: "Sodium", package: "swift-sodium"),
            ]
        ),
        .target(
            name: "OryTestDoubles",
            dependencies: [
                "Ory",
            ]
        ),
        .target(
            name: "OrySimulator",
            dependencies: [
                "Ory",
                .product(name: "X509", package: "swift-certificates"),
            ]
        ),
        .testTarget(
            name: "OryClientTests",
            dependencies: [
                "Ory",
                "OryTestDoubles",
                "_OryGeneratedAPI",
            ],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
