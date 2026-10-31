// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [SwiftSetting] = [.enableUpcomingFeature("ExistentialAny")]

let package = Package(
    name: "KeyValueStorage",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .watchOS(.v6),
        .tvOS(.v13),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "KeyValueStorage",
            targets: ["KeyValueStorage"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "KeyValueStorage",
            dependencies: [],
            resources: [.process("Resources/PrivacyInfo.xcprivacy")],
            swiftSettings: swiftSettings),
        .testTarget(
            name: "KeyValueStorageTests",
            dependencies: ["KeyValueStorage"],
            swiftSettings: swiftSettings),
        .testTarget(
            name: "KeyValueStoragePublicAPITests",
            dependencies: ["KeyValueStorage"],
            swiftSettings: swiftSettings),
        .testTarget(
            name: "KeyValueStorageIntegrationTests",
            dependencies: ["KeyValueStorage"],
            swiftSettings: swiftSettings),
    ]
)
