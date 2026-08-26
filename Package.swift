// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FilesServer",
    platforms: [.macOS(.v11), .macCatalyst(.v14), .iOS(.v14), .tvOS(.v17), .visionOS(.v1)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "FilesServer",
            targets: ["FilesServer"]
        ),
    ],
    dependencies: [
        .package(path: "../../Geralt888/KSPlayer"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "FilesServer", dependencies: [
            "KSPlayer",
        ]),
        .testTarget(name: "FilesProviderTests", dependencies: [
            "FilesServer",
        ]),
    ],
    swiftLanguageModes: [.v6]
)
