// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftGrok",
    platforms: [
        .macOS(.v14),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "GrokClient",
            targets: ["GrokClient"]),
        .executable(
            name: "grok",
            targets: ["GrokCLI"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/onevcat/Rainbow", from: "4.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "GrokClient",
            dependencies: []),
        .executableTarget(
            name: "GrokCLI",
            dependencies: [
                "GrokClient",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Rainbow"
            ]),
        .testTarget(
            name: "GrokClientTests",
            dependencies: ["GrokClient"]),
    ],
    swiftLanguageModes: [.v5]
) 