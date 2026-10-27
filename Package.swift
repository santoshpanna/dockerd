// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Dockerd",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Dockerd", targets: ["Dockerd"]),
        .library(name: "DockerdCore", targets: ["DockerdCore"]),
    ],
    targets: [
        .target(name: "DockerdCore"),
        .executableTarget(
            name: "Dockerd",
            dependencies: ["DockerdCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "DockerdCoreTests", dependencies: ["DockerdCore"]),
    ]
)
