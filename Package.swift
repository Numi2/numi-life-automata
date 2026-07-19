// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NumiAutomata",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "NumiAutomata", targets: ["NumiAutomata"])
    ],
    targets: [
        .target(
            name: "AutogenesisCore",
            path: "Sources/AutogenesisCore"
        ),
        .executableTarget(
            name: "NumiAutomata",
            dependencies: ["AutogenesisCore"],
            path: "Sources/AutogenesisMetal",
            resources: [
                .copy("Shaders")
            ]
        ),
        .testTarget(
            name: "AutogenesisCoreTests",
            dependencies: ["AutogenesisCore"],
            path: "Tests/AutogenesisCoreTests"
        )
    ]
)
