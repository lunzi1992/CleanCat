// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleanCat",
    platforms: [
        .iOS(.v16)  // 实际需 16.1+（fontDesign API）
    ],
    products: [
        .library(
            name: "CleanCat",
            targets: ["CleanCat"]
        )
    ],
    targets: [
        .target(
            name: "CleanCat",
            path: ".",
            exclude: [
                "deliverables",
                ".workbuddy",
                "README.md",
                "SETUP.md",
                "PRD_CleanCat_V1.0.md",
                "Package.swift"
            ]
        )
    ]
)
