// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "MOMOCABridge",
  platforms: [
    // specify each minimum deployment requirement,
    // otherwise the platform default minimum is used.
    .macOS(.v14),
  ],
  products: [
    // Products define the executables and libraries a package produces, and make them visible
    // to other packages.
    .library(
      name: "MOMOCABridge",
      targets: ["MOMOCABridge"]
    ),
    .executable(
      name: "MOMOCABridgeShell",
      targets: ["MOMOCABridgeShell"]
    ),
  ],
  dependencies: [
    // Dependencies declare other packages that this package depends on.
    // .package(url: /* package url */, from: "1.0.0"),
    .package(url: "https://github.com/PADL/MOM.git", branch: "main"),
    .package(url: "https://github.com/PADL/SwiftOCA.git", branch: "main"),
  ],
  targets: [
    // Targets are the basic building blocks of a package. A target can define a module or a
    // test suite.
    // Targets can depend on other targets in this package, and on products in packages this
    // package depends on.
    .target(
      name: "MOMOCABridge",
      dependencies: [
        .product(name: "SwiftOCADevice", package: "SwiftOCA"),
        "MOM",
      ]
    ),
    .executableTarget(
      name: "MOMOCABridgeShell",
      dependencies: [
        "MOMOCABridge",
      ]
    ),
  ]
)
