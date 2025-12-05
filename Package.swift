// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DebugProbe",
    platforms: [
        .iOS(.v14),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "DebugProbe",
            targets: ["DebugProbe"]
        ),
    ],
    dependencies: [
        // 可选：如果项目使用 CocoaLumberjack
         .package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack.git",  .upToNextMinor(from: "3.8.5")),
    ],
    targets: [
        .target(
            name: "DebugProbe",
            dependencies: [
                "CocoaLumberjack",
                .product(name: "CocoaLumberjackSwift", package: "CocoaLumberjack"),
            ],
            path: "Sources"
        ),
    ]
)
