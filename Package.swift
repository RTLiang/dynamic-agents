// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DynamicAgents",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "DynamicAgents", targets: ["DynamicAgents"])],
    targets: [
        .target(name: "AgentCore", resources: [.process("Resources")]),
        .executableTarget(name: "DynamicAgents", dependencies: ["AgentCore"]),
        .testTarget(name: "AgentCoreTests", dependencies: ["AgentCore"])
    ]
)
