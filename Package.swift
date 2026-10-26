// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClipIslandCore",
            path: "Sources/ClipIslandCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "ClipIsland",
            dependencies: ["ClipIslandCore"],
            path: "Sources/ClipIsland",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "SelfTest",
            dependencies: ["ClipIslandCore"],
            path: "Sources/SelfTest",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
