import Foundation

/// Orchestrates the mention detection → reaction → notification → reminder flow.
actor MentionHandler {
    private let config: Config
    private let slackAPI: SlackAPI
    private let reminderService: ReminderService
    private var socketMode: SlackSocketMode?

    init(config: Config) {
        self.config = config
        self.slackAPI = SlackAPI(botToken: config.slackBotToken)
        self.reminderService = ReminderService(listName: config.reminderListName)
    }

    func start() async {
        // Request Reminders access first
        await reminderService.requestAccess()

        print("👂 Listening for mentions of <@\(config.trackedUserId)>...")

        socketMode = SlackSocketMode(appToken: config.slackAppToken) { [weak self] event in
            await self?.handleEvent(event)
        }

        await socketMode?.start()
    }

    func stop() async {
        await socketMode?.stop()
    }

    private func handleEvent(_ event: SlackEvent) async {
        guard event.isMention(of: config.trackedUserId) else { return }

        print("🔔 Mention detected in \(event.channel) from \(event.user)")

        // 1. React with 👀
        do {
            try await slackAPI.addReaction(channel: event.channel, timestamp: event.ts, emoji: "eyes")
        } catch {
            print("⚠️  Failed to react: \(error)")
        }

        // 2. Fetch context
        var senderName = event.user
        var channelName = event.channel
        var permalink: String?

        do {
            async let userInfoTask = slackAPI.getUserInfo(userId: event.user)
            async let channelInfoTask = slackAPI.getChannelInfo(channelId: event.channel)
            async let permalinkTask = slackAPI.getPermalink(channel: event.channel, timestamp: event.ts)

            let userInfo = try await userInfoTask
            senderName = userInfo.realName ?? userInfo.name
            channelName = try await channelInfoTask ?? event.channel
            permalink = try await permalinkTask
        } catch {
            print("⚠️  Failed to fetch context: \(error)")
        }

        // 3. Create Apple Reminder
        let title = "Slack: \(senderName) in #\(channelName)"
        let notes = permalink != nil
            ? "\(event.text)\n\n\(permalink!)"
            : event.text

        await reminderService.createReminder(title: title, notes: notes)

        // 4. macOS notification
        await sendLocalNotification(title: "Slack mention", body: "\(senderName) in #\(channelName)")
    }

    private func sendLocalNotification(title: String, body: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", """
            display notification "\(body.replacingOccurrences(of: "\"", with: "\\\""))" \
            with title "\(title.replacingOccurrences(of: "\"", with: "\\\""))"
            """]
        try? process.run()
    }
}
