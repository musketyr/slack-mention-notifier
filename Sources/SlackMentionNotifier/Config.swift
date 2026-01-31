import Foundation

/// App configuration loaded from environment variables or a .env file.
struct Config {
    let slackAppToken: String       // xapp-... (Socket Mode token)
    let slackBotToken: String       // xoxb-... (Bot token for API calls)
    let trackedUserId: String       // U... (Slack user ID to track mentions for)
    let telegramBotToken: String?   // Optional: Telegram bot token
    let telegramChatId: String?     // Optional: Telegram chat ID
    let reminderListName: String    // Apple Reminders list name (default: "Reminders")

    var isTelegramEnabled: Bool {
        telegramBotToken != nil && telegramChatId != nil
    }

    /// Load configuration from environment variables, falling back to ~/.slack-mention-notifier.env
    static func load() -> Config {
        // Try loading .env file first
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
            telegramBotToken: env("TELEGRAM_BOT_TOKEN"),
            telegramChatId: env("TELEGRAM_CHAT_ID"),
            reminderListName: env("APPLE_REMINDERS_LIST") ?? "Reminders"
        )
    }

    private static func env(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key]
        return value?.isEmpty == true ? nil : value
    }

    /// Load key=value pairs from ~/.slack-mention-notifier.env
    private static func loadDotEnv() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let envFile = home.appendingPathComponent(".slack-mention-notifier.env")

        guard let contents = try? String(contentsOf: envFile, encoding: .utf8) else { return }

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
