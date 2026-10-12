// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HoverShot",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "HoverShotMac",
            targets: ["HoverShotMacApp"]
        )
    ],
    targets: [
        .testTarget(
            name: "HoverShotUXTests",
            dependencies: ["Library", "Capture", "Editing"],
            path: "Tests/HoverShotUXTests"
        ),
        .target(
            name: "Shared",
            path: "Apps/HoverShotMac/Shared"
        ),
        .target(
            name: "Library",
            dependencies: ["Shared"],
            path: "Apps/HoverShotMac/Library"
        ),
        .target(
            name: "Analysis",
            dependencies: ["Shared"],
            path: "Apps/HoverShotMac/Analysis"
        ),
        .target(
            name: "Export",
            dependencies: ["Library"],
            path: "Apps/HoverShotMac/Export"
        ),
        .target(
            name: "Editing",
            dependencies: ["Library"],
            path: "Apps/HoverShotMac/Editing"
        ),
        .target(
            name: "Capture",
            dependencies: [
                "Shared",
                "Library",
                "Analysis"
            ],
            path: "Apps/HoverShotMac/Capture"
        ),
        .target(
            name: "FloatingShots",
            dependencies: ["Library"],
            path: "Apps/HoverShotMac/FloatingShots"
        ),
        .target(
            name: "MenuBar",
            dependencies: ["Shared"],
            path: "Apps/HoverShotMac/MenuBar"
        ),
        .executableTarget(
            name: "HoverShotMacApp",
            dependencies: [
                "Shared",
                "Library",
                "Capture",
                "Editing",
                "Export",
                "FloatingShots",
                "MenuBar"
            ],
            path: "Apps/HoverShotMac/App"
        )
    ]
)
