// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "QueueItKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "QueueItKit",
            targets: ["QueueItKit"]
        ),
    ],
    targets: [
        .target(
            name: "QueueItKit",
            path: "QueueItKit",
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
                .process("QueueItKit.docc")
            ]
        ),
        .testTarget(
            name: "QueueItKitTests",
            dependencies: ["QueueItKit"],
            path: "QueueItKitTests"
        ),
    ]
)
