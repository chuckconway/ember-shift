// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Ember",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "EmberCore"),
        .target(
            name: "EmberKit",
            dependencies: ["EmberCore"],
            // Lets EmberKitChecks use @testable import in debug builds.
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .executableTarget(name: "Ember", dependencies: ["EmberKit"]),
        // Command Line Tools ship neither XCTest nor a usable Swift Testing, so checks run as an executable.
        .executableTarget(name: "EmberChecks", dependencies: ["EmberCore"]),
        .executableTarget(name: "EmberKitChecks", dependencies: ["EmberKit"]),
        // Renders the UI to PNGs offscreen, so layout can be reviewed without Screen Recording access.
        .executableTarget(name: "EmberSnapshot", dependencies: ["EmberKit"]),
    ],
    swiftLanguageModes: [.v5]
)
