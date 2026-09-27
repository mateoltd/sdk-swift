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
        .testTarget(
            name: "BitwardenSdkTests",
            dependencies: ["BitwardenSdk"]),
        .binaryTarget(
            name: "BitwardenFFI",
            url: "https://raw.githubusercontent.com/mateoltd/sdk-swift/77b19c225a0b3987e45497a0763792d16babb909/BitwardenFFI.xcframework.zip",
            checksum: "1fd23fc79b743ccfb55bb4ceeb35b5c97b2116166e9fb5057be12126b37ca582")
    ]
)
