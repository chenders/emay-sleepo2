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
        .library(name: "EMAYSleepO2CSV", targets: ["EMAYSleepO2CSV"]),
    ],
    targets: [
        .target(
            name: "EMAYSleepO2",
            dependencies: [],
            path: "Sources/EMAYSleepO2"
        ),
        .target(
            name: "EMAYSleepO2CSV",
            dependencies: [],
            path: "Sources/EMAYSleepO2CSV"
        ),
        .testTarget(
            name: "EMAYSleepO2Tests",
            dependencies: ["EMAYSleepO2"],
            path: "Tests/EMAYSleepO2Tests"
        ),
        .testTarget(
            name: "EMAYSleepO2CSVTests",
            dependencies: ["EMAYSleepO2CSV"],
            path: "Tests/EMAYSleepO2CSVTests"
        ),
    ]
)
