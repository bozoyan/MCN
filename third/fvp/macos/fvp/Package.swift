// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Adapted from wang-bin/fvp v0.39.0 darwin/fvp/Package.swift.
import PackageDescription

let package = Package(
    name: "fvp",
    platforms: [
        .macOS("10.13"),
    ],
    products: [
        .library(name: "fvp", type: .dynamic, targets: ["fvp"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "fvp",
            dependencies: [
                .target(name: "mdk"),
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: ".",
            sources: [
                "Sources/fvp/FvpPlugin.mm",
                "Sources/fvp/callbacks.cpp",
            ],
            resources: [
                .process("Resources/PrivacyInfo.xcprivacy"),
            ],
            publicHeadersPath: "Sources/fvp",
            cSettings: [
                .headerSearchPath("Sources/fvp"),
            ],
            cxxSettings: [
                .unsafeFlags(["-Wno-documentation"]),
            ],
            linkerSettings: [
                .linkedFramework("FlutterMacOS", .when(platforms: [.macOS])),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Metal"),
            ]
        ),
        .binaryTarget(
            name: "mdk",
            // setup.sh preserves the local MDK build without its optional FFmpeg runtime.
            path: "Binaries/mdk.xcframework.zip"
        ),
    ],
    cxxLanguageStandard: .cxx20
)
