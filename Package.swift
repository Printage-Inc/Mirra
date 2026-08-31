// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Mirra",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Mirra", targets: ["CableMirror"]),
        .executable(name: "MirraDeviceWatcher", targets: ["CableMirrorDeviceWatcher"])
    ],
    targets: [
        .binaryTarget(
            name: "AirPlayMacBridge",
            path: ".build/MirraAirPlay.xcframework"
        ),
        .executableTarget(
            name: "CableMirror",
            dependencies: ["AirPlayMacBridge"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("c++")
            ]
        ),
        .executableTarget(
            name: "CableMirrorDeviceWatcher",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "CableMirrorTests",
            dependencies: ["CableMirror"]
        )
    ],
    cxxLanguageStandard: .cxx20
)
