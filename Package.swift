// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacResourceMonitor",
    platforms: [.macOS(.v13)],
    dependencies: [
        // The only third-party dependency: Sparkle powers in-app updates (see docs/RELEASING.md).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(name: "MonitorCore"),
        .target(name: "MonitorUI", dependencies: ["MonitorCore"]),
        .executableTarget(
            name: "MonitorApp",
            dependencies: [
                "MonitorCore",
                "MonitorUI",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"]),
        .testTarget(name: "MonitorUITests", dependencies: ["MonitorCore", "MonitorUI"]),
    ]
)
