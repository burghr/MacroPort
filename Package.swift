// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacroPort",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacroPort",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
