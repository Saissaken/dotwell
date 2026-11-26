// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacResourceMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MonitorCore"),
        .target(name: "MonitorUI", dependencies: ["MonitorCore"]),
        .executableTarget(
            name: "MonitorApp",
            dependencies: ["MonitorCore", "MonitorUI"]
        ),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"]),
        .testTarget(name: "MonitorUITests", dependencies: ["MonitorCore", "MonitorUI"]),
    ]
)
