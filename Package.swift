// swift-tools-version:5.9
import PackageDescription

// Orion's automated test surface.
//
// The Xcode project (lil-agents.xcodeproj) builds the actual app.
// This Package exists only to compile and run the regression tests
// that protect the pure-logic modules from the kinds of bugs that
// shipped in v0.1.38–v0.1.42 (Slack copy markup, citation
// linkification, sensitive-data leakage, bubble width math).
//
// Why a separate Package and not an XCTest target inside the
// project: adding an XCTest target via direct pbxproj edits is
// non-trivial and risks breaking the app build. SPM is a clean
// adjacent path — `swift test` runs the suite without touching
// the Xcode project, and CI can call it as a one-line step.
//
// What ships in `LilJustinCore` is intentionally a small, pure
// subset of the production source: just the files that have no
// AppKit / SwiftUI / framework-bundle dependencies. UI-layer code
// is tested by hand or via release smoke checks; this surface
// catches the silent-correctness regressions.
let package = Package(
    name: "LilJustinTests",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "LilJustinCore",
            // Reference production source files directly so tests
            // stay in lockstep with what the app actually ships.
            // Adding a new pure-logic file the tests should cover?
            // List it here AND keep it in lil-agents.xcodeproj.
            path: ".",
            exclude: [
                "LICENSE",
                "NEXT_STEPS.md",
                "README.md",
                "Tests",
                "Scripts",
                "dist",
                "lil-agents.xcodeproj",
                "LilAgents"
            ],
            sources: [
                "LilAgents/Session/MarkdownToSlack.swift",
                "LilAgents/Session/MarkdownToHTML.swift",
                "LilAgents/Session/StructuredJSONParser.swift",
                "LilAgents/Memory/MemoryEntry.swift",
                "LilAgents/Memory/SensitivityFilter.swift",
                "LilAgents/App/BusinessContext.swift",
                "LilAgents/Terminal/BubbleWidthMath.swift"
            ]
        ),
        .testTarget(
            name: "LilJustinCoreTests",
            dependencies: ["LilJustinCore"],
            path: "Tests/LilJustinCoreTests"
        )
    ]
)
