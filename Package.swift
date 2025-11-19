// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "i2c",
    platforms: [.iOS(.v26), .macOS(.v26)],  // ignored on Linux but editing with Xcode requires it
    products: [
        .library(name: "Ci2c", targets: ["Ci2c"]),
        .library(name: "i2c", targets: ["i2c"]),
    ],
    dependencies: [],
    targets: [
        .systemLibrary(
            name: "Ci2c",
        ),
        .target(
            name: "i2c",
            dependencies: [ .byNameItem(name: "Ci2c", condition: .when(platforms: [.linux])) ],
            swiftSettings: [.strictMemorySafety()],
        ),
    ]
)
