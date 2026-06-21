// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutopilotCore",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "AutopilotCore", targets: ["AutopilotCore"]),
    ],
    targets: [
        .target(name: "AutopilotCore",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AutopilotCoreTests",
                    dependencies: ["AutopilotCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
