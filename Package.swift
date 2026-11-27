// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyFlag",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "KeyFlag", targets: ["KeyFlag"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // All app logic lives here so it can be unit tested.
        .target(
            name: "KeyFlagCore",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // Thin entry point; Scripts/build-app.sh wraps it into KeyFlag.app.
        .executableTarget(
            name: "KeyFlag",
            dependencies: ["KeyFlagCore"],
            // build-app.sh puts Sparkle.framework in KeyFlag.app/Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "KeyFlagCoreTests",
            dependencies: ["KeyFlagCore"]
        ),
    ]
)
