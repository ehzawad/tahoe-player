// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TahoePlayer",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "TahoePlayer", targets: ["TahoePlayer"])
    ],
    targets: [
        .executableTarget(name: "TahoePlayer")
    ]
)
