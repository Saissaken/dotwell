// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacResourceMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MonitorCore"),
        .executableTarget(
            name: "MonitorApp",
            dependencies: ["MonitorCore"]
        ),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"]),
    ]
)
