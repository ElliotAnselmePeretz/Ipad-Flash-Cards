// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlashcardsCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FlashcardsCore", targets: ["FlashcardsCore"])
    ],
    targets: [
        .target(name: "FlashcardsCore"),
        .testTarget(name: "FlashcardsCoreTests", dependencies: ["FlashcardsCore"]),
    ]
)
