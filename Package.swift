// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppSelector",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "AppSelector")]
)
