// swift-tools-version:5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KeyValueStorage",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .watchOS(.v6),
        .tvOS(.v13)
    ],
    products: [
        .library(
            name: "KeyValueStorage",
            targets: ["KeyValueStorage"]),

//        .library(
//            name: "KeyValueStorageLegacy",
//            targets: ["KeyValueStorageLegacy"]),
//        .library(
//            name: "KeyValueStorageLegacyWrapper",
//            targets: ["KeyValueStorageLegacyWrapper"]),
//        .library(
//            name: "KeyValueStorageLegacySwiftUI",
//            targets: ["KeyValueStorageLegacySwiftUI"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "KeyValueStorage",
            dependencies: [],
            resources: [.process("Resources/PrivacyInfo.xcprivacy")],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]),
        .testTarget(
            name: "KeyValueStorageTests",
            dependencies: ["KeyValueStorage"]),
        
//        .target(
//            name: "KeyValueStorageLegacy",
//            dependencies: []),
//        .target(
//            name: "KeyValueStorageLegacyWrapper",
//            dependencies: [.target(name: "KeyValueStorageLegacy")]),
//        .target(
//            name: "KeyValueStorageLegacySwiftUI",
//            dependencies: [.target(name: "KeyValueStorageLegacyWrapper")]),
//        .testTarget(
//            name: "KeyValueStorageLegacyTests",
//            dependencies: ["KeyValueStorageLegacy", "KeyValueStorageLegacyWrapper", "KeyValueStorageLegacySwiftUI"]),
    ]
)
