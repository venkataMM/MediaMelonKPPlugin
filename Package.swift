// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MediaMelonKPPlugin",
    platforms: [
        .iOS(.v12),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MediaMelonKPPlugin",
            targets: ["MediaMelonKPPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/kaltura/playkit-ios.git", from: "3.28.0"),
        .package(url: "https://github.com/venkataMM/MMGenericFramework.git", from: "1.0.5")
    ],
    targets: [
        .target(
            name: "MediaMelonKPPlugin",
            dependencies: [
                .product(name: "PlayKit", package: "playkit-ios"),
                .product(name: "MMGenericFramework", package: "MMGenericFramework")
            ],
            path: "Sources/MediaMelonKPPlugin"
        ),
        .testTarget(
            name: "MediaMelonKPPluginTests",
            dependencies: ["MediaMelonKPPlugin"]
        )
    ]
)
