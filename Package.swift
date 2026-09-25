// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bellwether",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Bellwether", targets: ["Bellwether"])
    ],
    targets: [
        .target(name: "Bellwether"),
        .testTarget(name: "BellwetherTests", dependencies: ["Bellwether"]),
    ]
)
