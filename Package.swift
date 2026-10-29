// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhoStoleMyFocus",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WhoStoleMyFocus", targets: ["WhoStoleMyFocus"]),
    ],
    targets: [
        // Pure logic with no access to other apps or the screen, so it can be tested on its own.
        .target(name: "FocusCore"),
        .executableTarget(name: "WhoStoleMyFocus", dependencies: ["FocusCore"]),
        .testTarget(name: "FocusCoreTests", dependencies: ["FocusCore"]),
        // The app's glue, tested with stand-ins for the system and windows that are never shown.
        .testTarget(name: "WhoStoleMyFocusTests", dependencies: ["WhoStoleMyFocus", "FocusCore"]),
    ]
)
