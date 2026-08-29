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
        .executableTarget(
            name: "CableMirror",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("ServiceManagement")
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
    ]
)
