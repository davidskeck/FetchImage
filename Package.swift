// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "FetchImage",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(name: "FetchImage", targets: ["FetchImage"])
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Nuke.git", from: "8.0.0")
    ],
    targets: [
        .target(name: "FetchImage", dependencies: ["Nuke"], path: "Source")
    ]
)
