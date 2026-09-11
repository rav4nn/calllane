// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CallLane",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CallLane",
            path: "Sources/CallLane",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "CallLaneTests",
            dependencies: ["CallLane"],
            path: "Tests/CallLaneTests"
        ),
    ]
)
