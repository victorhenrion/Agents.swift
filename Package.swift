// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Agents.swift",

    platforms: [
        .iOS(.v17),
        .macCatalyst(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .visionOS(.v1),
        .watchOS(.v10),
    ],

    products: [
        .library(name: "AI", targets: ["AI"]),
        .library(name: "Agents", targets: ["Agents"]),
    ],

    dependencies: [
        .package(url: "https://github.com/daangn/KarrotCodableKit.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.2.1"),
        .package(url: "https://github.com/gohanlon/swift-memberwise-init-macro.git", from: "0.5.2"),
    ],

    targets: [
        .target(
            name: "ISO8601JSON",
        ),
        .target(
            name: "AI",
            dependencies: [
                "ISO8601JSON",
                .product(name: "KarrotCodableKit", package: "KarrotCodableKit"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "MemberwiseInit", package: "swift-memberwise-init-macro"),
            ]
        ),
        .target(
            name: "Agents",
            dependencies: [
                "AI",
                "ISO8601JSON",
                .product(name: "KarrotCodableKit", package: "KarrotCodableKit"),
                .product(name: "MemberwiseInit", package: "swift-memberwise-init-macro"),
            ]
        ),
    ],
)
