// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HanSearch",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HanSearch", targets: ["HanSearch"])],
    targets: [
        .target(name: "HanSearchCore"),
        .executableTarget(name: "HanSearch", dependencies: ["HanSearchCore"]),
        .executableTarget(name: "HanSearchChecks", dependencies: ["HanSearchCore"], path: "Tests/HanSearchCoreTests")
    ]
)
