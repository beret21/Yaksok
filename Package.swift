// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Yaksok",
    defaultLocalization: "ko",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Yaksok",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Yaksok",
            resources: [
                .copy("../../Resources")
            ]
        )
    ]
)
