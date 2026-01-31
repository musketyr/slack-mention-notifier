// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SlackMentionNotifier",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SlackMentionNotifier",
            path: "Sources/SlackMentionNotifier"
        )
    ]
)
