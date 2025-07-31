// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "BNotify",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "BNotify",
            targets: ["BNotify"]
        )
    ],
    targets: [
        .target(
            name: "BNotify",
            dependencies: [],
            path: "Sources/BNotify"
        ),
        .testTarget(
            name: "BNotifyTests",
            dependencies: ["BNotify"]
        )
    ]
)
