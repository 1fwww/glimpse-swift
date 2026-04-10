// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Glimpse",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Glimpse",
            path: "Glimpse",
            resources: [
                .copy("swift-shim.js"),
            ]
        ),
    ]
)
