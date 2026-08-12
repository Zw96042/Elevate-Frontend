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
                "Networking/SkywardAuthAPI.swift",
                "PrivacyInfo.xcprivacy",
                "Services/DataService.swift",
                "Services/SampleData.swift",
                "Services/WhatIfStore.swift",
                "Services/WidgetSnapshotBuilder.swift",
                "Store",
                "Views",
            ],
            sources: [
                "Logic/GradeMath.swift",
                "Models/Models.swift",
                "Networking/SkywardGradesAPI.swift",
                "Networking/SkywardHistoryAPI.swift",
                "Networking/SkywardHTTP.swift",
                "Networking/SkywardMessagesAPI.swift",
                "Parsing/JavaScriptLiteralParser.swift",
                "Parsing/MiniHTML.swift",
                "Services/Storage.swift",
            ]
        ),
        .testTarget(
            name: "ElevateCoreTests",
            dependencies: ["ElevateCore"],
            path: "Tests/ElevateCoreTests"
        ),
    ]
)
