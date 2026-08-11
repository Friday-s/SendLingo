// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SendLingo",
    platforms: [
        // Programmatic TranslationSession / LanguageAvailability require macOS 15.0+.
        // The delivered .app declares LSMinimumSystemVersion = 15.0 (see Info.plist).
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "SendLingo",
            path: "Sources/OptionNow",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Translation"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security")
            ]
        )
    ]
)
