// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "OryClient",
    platforms: [
        .iOS(.v14),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "OryClient",
            targets: ["OryClient"]
        ),
        .library(
            name: "OryClientTestDoubles",
            targets: ["OryClientTestDoubles"]
        ),
        // Simulator-only relaxed device attestation. Depend on this product only for
        // Simulator or test builds; its code compiles to nothing on device builds, and
        // its swift-certificates dependency is linked only when this product is used.
        .library(
            name: "OryClientSimulator",
            targets: ["OryClientSimulator"]
        ),
    ],
    dependencies: [
        // Used only by the OryClientSimulator target to build a self-signed attestation
        // chain for the Simulator. Not a dependency of the OryClient product.
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.19.2"),
        .package(url: "https://github.com/jedisct1/swift-sodium.git", exact: "0.11.0"),
    ],
    targets: [
        .target(
            name: "OrySDK"
        ),
        .target(
            name: "OryClient",
            dependencies: [
                "OrySDK",
                .product(name: "Sodium", package: "swift-sodium"),
            ]
        ),
        .target(
            name: "OryClientTestDoubles",
            dependencies: [
                "OryClient",
            ]
        ),
        .target(
            name: "OryClientSimulator",
            dependencies: [
                "OryClient",
                .product(name: "X509", package: "swift-certificates"),
            ]
        ),
        .testTarget(
            name: "OryClientTests",
            dependencies: [
                "OryClient",
                "OryClientTestDoubles",
                "OrySDK",
            ],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
