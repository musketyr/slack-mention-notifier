import Foundation

/// App configuration loaded from environment variables, config file, or Keychain (OAuth).
struct Config {
    let slackAppToken: String       // xapp-... (Socket Mode token)
    let slackBotToken: String       // xoxb-... (Bot token for API calls)
    let trackedUserId: String       // U... (Slack user ID to track mentions for)
    let reminderListName: String    // Apple Reminders list name (default: "Reminders")

    // OAuth settings (optional — only needed for "Sign in with Slack" flow)
    let slackClientId: String?
    let slackClientSecret: String?

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

    // MARK: - Keychain keys

    static let keychainBotToken = "slack-bot-token"
    static let keychainAuthedUser = "slack-authed-user-id"
    static let keychainTeamName = "slack-team-name"

    /// Whether OAuth has been completed (bot token stored in Keychain).
    static var isAuthenticated: Bool {
        return KeychainHelper.exists(key: keychainBotToken)
    }

    /// Whether OAuth flow is available (client ID and secret configured).
    var isOAuthAvailable: Bool {
        return slackClientId != nil && slackClientSecret != nil && !slackClientId!.isEmpty
    }

    /// Save OAuth tokens to Keychain.
    static func saveOAuthResult(_ result: OAuthResult) {
        _ = KeychainHelper.save(key: keychainBotToken, value: result.botToken)
        if let userId = result.authedUserId {
            _ = KeychainHelper.save(key: keychainAuthedUser, value: userId)
        }
        if let teamName = result.teamName {
            _ = KeychainHelper.save(key: keychainTeamName, value: teamName)
        }
    }

    /// Clear stored OAuth tokens.
    static func clearAuth() {
        KeychainHelper.delete(key: keychainBotToken)
        KeychainHelper.delete(key: keychainAuthedUser)
        KeychainHelper.delete(key: keychainTeamName)
    }

    /// Load configuration. Priorities:
    /// 1. Environment variables / config file for app token, client ID/secret
    /// 2. Keychain for bot token (from OAuth) — falls back to config file
    /// 3. Config file for tracked user ID — falls back to Keychain authed user
    static func load() -> Config {
        loadDotEnv()

        guard let appToken = env("SLACK_APP_TOKEN") else {
            fatalError("SLACK_APP_TOKEN is required (xapp-... Socket Mode token)")
        }

        // Bot token: prefer config/env, fall back to Keychain (OAuth)
        let botToken = env("SLACK_BOT_TOKEN") ?? KeychainHelper.load(key: keychainBotToken)

        // Tracked user: prefer config/env, fall back to OAuth authed user
        let trackedUser = env("SLACK_TRACKED_USER_ID") ?? KeychainHelper.load(key: keychainAuthedUser)

        return Config(
            slackAppToken: appToken,
            slackBotToken: botToken ?? "",
            trackedUserId: trackedUser ?? "",
            reminderListName: env("APPLE_REMINDERS_LIST") ?? "Reminders",
            slackClientId: env("SLACK_CLIENT_ID"),
            slackClientSecret: env("SLACK_CLIENT_SECRET")
        )
    }

    /// Whether the config has enough info to start listening.
    var isReady: Bool {
        return !slackAppToken.isEmpty && !slackBotToken.isEmpty && !trackedUserId.isEmpty
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
