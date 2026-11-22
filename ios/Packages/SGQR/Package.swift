// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SGQR",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "SGQR", targets: ["SGQR"])],
    targets: [
        .target(name: "SGQR"),
        .testTarget(name: "SGQRTests", dependencies: ["SGQR"]),
    ]
)
