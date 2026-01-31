import Foundation

/// App configuration loaded from environment variables, config file, or Keychain (OAuth).
struct Config {
    let slackAppToken: String       // xapp-... (Socket Mode token)
    let slackBotToken: String       // xoxb-... (Bot token for API calls)
    let trackedUserId: String       // U... (Slack user ID to track mentions for)
    let reminderListName: String    // Apple Reminders list name (default: "Reminders")
    let reactionEmoji: String       // Emoji to react with (default: "eyes")
    let autoJoinChannels: Bool      // Automatically join all public channels (default: false)

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

    /// Save OAuth tokens to Keychain. Returns success status for each field.
    @discardableResult
    static func saveOAuthResult(_ result: OAuthResult) -> (botToken: Bool, userId: Bool, teamName: Bool) {
        let botSaved = KeychainHelper.save(key: keychainBotToken, value: result.botToken)
        var userSaved = false
        if let userId = result.authedUserId {
            userSaved = KeychainHelper.save(key: keychainAuthedUser, value: userId)
        }
        var teamSaved = false
        if let teamName = result.teamName {
            teamSaved = KeychainHelper.save(key: keychainTeamName, value: teamName)
        }
        return (botSaved, userSaved, teamSaved)
    }

    /// Clear stored OAuth tokens.
    static func clearAuth() {
        KeychainHelper.delete(key: keychainBotToken)
        KeychainHelper.delete(key: keychainAuthedUser)
        KeychainHelper.delete(key: keychainTeamName)
    }

    /// Load configuration. Priorities:
    /// 1. Environment variables → config file values (freshly read)
    /// 2. Keychain for bot token (from OAuth) — falls back to config file
    /// 3. Embedded Secrets as final fallback
    static func load() -> Config {
        let file = loadConfigFile()

        // App token: env/config → embedded secret
        let appToken = env("SLACK_APP_TOKEN", fileValues: file) ?? nonEmpty(Secrets.slackAppToken)

        // Bot token: env/config → Keychain (OAuth)
        let botToken = env("SLACK_BOT_TOKEN", fileValues: file) ?? KeychainHelper.load(key: keychainBotToken)

        // Tracked user: env/config → Keychain (OAuth authed user)
        let trackedUser = env("SLACK_TRACKED_USER_ID", fileValues: file) ?? KeychainHelper.load(key: keychainAuthedUser)

        // OAuth credentials: env/config → embedded secrets
        let clientId = env("SLACK_CLIENT_ID", fileValues: file) ?? nonEmpty(Secrets.slackClientId)
        let clientSecret = env("SLACK_CLIENT_SECRET", fileValues: file) ?? nonEmpty(Secrets.slackClientSecret)

        return Config(
            slackAppToken: appToken ?? "",
            slackBotToken: botToken ?? "",
            trackedUserId: trackedUser ?? "",
            reminderListName: env("APPLE_REMINDERS_LIST", fileValues: file) ?? "Reminders",
            reactionEmoji: env("REACTION_EMOJI", fileValues: file) ?? "eyes",
            autoJoinChannels: env("AUTO_JOIN_CHANNELS", fileValues: file)?.lowercased() == "true",
            slackClientId: clientId,
            slackClientSecret: clientSecret
        )
    }

    /// Returns nil for empty strings.
    private static func nonEmpty(_ s: String) -> String? {
        return s.isEmpty ? nil : s
    }

    /// Whether the config has enough info to start listening.
    var isReady: Bool {
        return !slackAppToken.isEmpty && !slackBotToken.isEmpty && !trackedUserId.isEmpty
    }

    /// Read a config value. Priority: real env vars → config file → nil.
    private static func env(_ key: String, fileValues: [String: String]) -> String? {
        // 1. Real environment variables (set before process started)
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }
        // 2. Config file values (freshly read each time)
        if let value = fileValues[key], !value.isEmpty {
            return value
        }
        return nil
    }

    /// Parse the config file and return key-value pairs.
    private static func loadConfigFile() -> [String: String] {
        let legacyPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".slack-mention-notifier.env")

        // Migrate legacy config file if it exists and new one doesn't
        if FileManager.default.fileExists(atPath: legacyPath.path),
           !FileManager.default.fileExists(atPath: envFilePath.path) {
            try? FileManager.default.moveItem(at: legacyPath, to: envFilePath)
            print("📦 Migrated config from \(legacyPath.path) → \(envFilePath.path)")
        }

        let path = FileManager.default.fileExists(atPath: envFilePath.path) ? envFilePath : legacyPath
        guard let contents = try? String(contentsOf: path, encoding: .utf8) else { return [:] }

        var values: [String: String] = [:]
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

            values[key] = value
        }
        return values
    }
}
