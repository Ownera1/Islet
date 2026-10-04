// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "NotchIntegrations", platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodeIslandCore", targets: ["CodeIslandCore"]),
        .library(name: "NotchIntegrationCore", targets: ["NotchIntegrationCore"]),
        .executable(name: "notch-agent-bridge", targets: ["NotchAgentBridge"])
    ],
    targets: [
        .target(name: "CodeIslandCore"),
        .target(name: "NotchIntegrationCore", dependencies: ["CodeIslandCore"]),
        .executableTarget(name: "NotchAgentBridge", dependencies: ["CodeIslandCore"]),
        .testTarget(name: "NotchIntegrationCoreTests", dependencies: ["NotchIntegrationCore", "CodeIslandCore"])
    ]
)
