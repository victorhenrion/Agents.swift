// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Agents",

    platforms: [
        .iOS(.v17),
        .macCatalyst(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .visionOS(.v1),
        .watchOS(.v10),
    ],

    products: [
        .library(
            name: "Agents",
            targets: ["Agents"]
        )
    ],

    dependencies: [
        .package(url: "https://github.com/daangn/KarrotCodableKit.git", from: "1.4.0"),
        .package(url: "https://github.com/gohanlon/swift-memberwise-init-macro.git", from: "0.5.2"),
    ],

    targets: [
        .target(
            name: "Agents",
            dependencies: [
                .product(name: "KarrotCodableKit", package: "KarrotCodableKit"),
                .product(name: "MemberwiseInit", package: "swift-memberwise-init-macro"),
            ]
        )
    ],
)
