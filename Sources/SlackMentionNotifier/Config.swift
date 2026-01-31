import Foundation

/// App configuration loaded from environment variables or a .env file.
struct Config {
    let slackAppToken: String       // xapp-... (Socket Mode token)
    let slackBotToken: String       // xoxb-... (Bot token for API calls)
    let trackedUserId: String       // U... (Slack user ID to track mentions for)
    let reminderListName: String    // Apple Reminders list name (default: "Reminders")

    /// Base directory for all app data: ~/.config/slack-mention-notifier/
    static let configDir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/slack-mention-notifier")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Path to the .env config file.
    static var envFilePath: URL { configDir.appendingPathComponent("config.env") }

    /// Path to persistent state (last-seen timestamp, etc.).
    static var stateDir: URL {
        let dir = configDir.appendingPathComponent("state")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Load configuration from environment variables, falling back to config file.
    static func load() -> Config {
        loadDotEnv()

        guard let appToken = env("SLACK_APP_TOKEN") else {
            fatalError("SLACK_APP_TOKEN is required (xapp-... Socket Mode token)")
        }
        guard let botToken = env("SLACK_BOT_TOKEN") else {
            fatalError("SLACK_BOT_TOKEN is required (xoxb-... Bot token)")
        }
        guard let userId = env("SLACK_TRACKED_USER_ID") else {
            fatalError("SLACK_TRACKED_USER_ID is required (U... user ID)")
        }

        return Config(
            slackAppToken: appToken,
            slackBotToken: botToken,
            trackedUserId: userId,
            reminderListName: env("APPLE_REMINDERS_LIST") ?? "Reminders"
        )
    }

    private static func env(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key]
        return value?.isEmpty == true ? nil : value
    }

    /// Load key=value pairs from config file, with fallback to legacy location.
    private static func loadDotEnv() {
        let legacyPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".slack-mention-notifier.env")

        // Migrate legacy config file if it exists and new one doesn't
        if FileManager.default.fileExists(atPath: legacyPath.path),
           !FileManager.default.fileExists(atPath: envFilePath.path) {
            try? FileManager.default.moveItem(at: legacyPath, to: envFilePath)
            print("📦 Migrated config from \(legacyPath.path) → \(envFilePath.path)")
        }

        let path = FileManager.default.fileExists(atPath: envFilePath.path) ? envFilePath : legacyPath
        guard let contents = try? String(contentsOf: path, encoding: .utf8) else { return }

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)

            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }

            setenv(key, value, 0) // 0 = don't overwrite existing env vars
        }
    }
}
