// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexOpenPEHotkey",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OpenPEHotkey", targets: ["CodexOpenPEHotkey"])
    ],
    targets: [
        .target(
            name: "CodexOpenPEHotkeyCore",
            path: "Sources/CodexOpenPEHotkeyCore"
        ),
        .executableTarget(
            name: "CodexOpenPEHotkey",
            dependencies: ["CodexOpenPEHotkeyCore"],
            path: "Sources/CodexOpenPEHotkey",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "CoreSelfTests",
            dependencies: ["CodexOpenPEHotkeyCore"],
            path: "Tests/CoreSelfTests"
        )
    ]
)
