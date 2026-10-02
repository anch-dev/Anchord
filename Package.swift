// This package exposes the shared Anchord code for tests and future modularization.
// The iOS application target is defined in Anchord.xcodeproj.

import PackageDescription

let package = Package(
    name: "AnchordCore",
    platforms: [
        .iOS(.v27),
        .macOS(.v26)
    ],
    products: [
        .library(name: "AnchordCore", targets: ["AnchordCore"])
    ],
    targets: [
        .target(
            name: "AnchordCore",
            path: ".",
            exclude: ["Anchord.xcodeproj", "Anchord.entitlements"]
        )
    ]
)
