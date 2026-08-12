// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ElevateCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ElevateCore", targets: ["ElevateCore"]),
    ],
    targets: [
        .target(
            name: "ElevateCore",
            path: "Elevate",
            exclude: [
                "Assets.xcassets",
                "ElevateApp.swift",
                "Networking",
                "Parsing/MiniHTML.swift",
                "PrivacyInfo.xcprivacy",
                "Services",
                "Store",
                "Views",
            ],
            sources: [
                "Logic/GradeMath.swift",
                "Models/Models.swift",
                "Parsing/JavaScriptLiteralParser.swift",
            ]
        ),
        .testTarget(
            name: "ElevateCoreTests",
            dependencies: ["ElevateCore"],
            path: "Tests/ElevateCoreTests"
        ),
    ]
)
