// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Luma",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Luma", targets: ["Luma"])
    ],
    targets: [
        .executableTarget(
            name: "Luma",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security")
            ]
        )
    ]
)
