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
        .executableTarget(
            name: "TahoePlayer",
            dependencies: ["CMpv"]
        ),
        .testTarget(
            name: "TahoePlayerTests",
            dependencies: ["TahoePlayer"]
        ),
        .systemLibrary(
            name: "CMpv",
            pkgConfig: "mpv",
            providers: [
                .brew(["mpv"])
            ]
        )
    ]
)
