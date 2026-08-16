// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BitwardenSdk",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "BitwardenSdk",
            targets: ["BitwardenSdk", "BitwardenFFI"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "BitwardenSdk",
            dependencies: ["BitwardenFFI", "BitwardenSdkSupport"],
            swiftSettings: [.unsafeFlags(["-suppress-warnings"])]),
        .target(name: "BitwardenSdkSupport"),
        .binaryTarget(
            name: "BitwardenFFI",
            url: "https://raw.githubusercontent.com/mateoltd/sdk-swift/8e036f70967f8a8daa1c186d5446ad6a5d07584e/BitwardenFFI.xcframework.zip",
            checksum: "95ae5e88f53c5b6f24ac56a259c0472b12f24d10b722706e4b70a93fd49c315f"),
        .testTarget(
            name: "BitwardenSdkTests",
            dependencies: ["BitwardenSdk"])
    ]
)
