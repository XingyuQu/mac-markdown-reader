// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarkdownReader",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "MarkdownReader", targets: ["MarkdownReader"]),
    ],
    targets: [
        .executableTarget(
            name: "MarkdownReader",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
    
