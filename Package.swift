// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "WorkflowGenerator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WorkflowGenerator", targets: ["WorkflowGenerator"])
    ],
    targets: [
        .executableTarget(
            name: "WorkflowGenerator",
            path: "Sources/WorkflowGenerator"
        ),
        .testTarget(
            name: "WorkflowGeneratorTests",
            dependencies: ["WorkflowGenerator"],
            path: "Tests/WorkflowGeneratorTests"
        )
    ]
)
