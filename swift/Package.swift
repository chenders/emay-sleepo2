// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "emay-sleepo2",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "EMAYSleepO2", targets: ["EMAYSleepO2"]),
    ],
    targets: [
        .target(
            name: "EMAYSleepO2",
            dependencies: [],
            path: "Sources/EMAYSleepO2"
        ),
        .testTarget(
            name: "EMAYSleepO2Tests",
            dependencies: ["EMAYSleepO2"],
            path: "Tests/EMAYSleepO2Tests"
        ),
    ]
)
