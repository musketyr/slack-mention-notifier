import Foundation

/// Orchestrates the mention detection → reaction → notification → reminder flow.
actor MentionHandler {
    private let config: Config
    private let slackAPI: SlackAPI
    private let reminderService: ReminderService
    private var socketMode: SlackSocketMode?
    private var lastSeenTs: String

    /// File to persist last-seen timestamp across restarts.
    private static var tsFilePath: URL {
        Config.stateDir.appendingPathComponent("last-seen-ts")
    }

    init(config: Config) {
        self.config = config
        self.slackAPI = SlackAPI(botToken: config.slackBotToken)
        self.reminderService = ReminderService(listName: config.reminderListName)
        self.lastSeenTs = (try? String(contentsOf: Self.tsFilePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
    }

    private var channelScanTask: Task<Void, Never>?

    func start() async {
        // Request Reminders access first
        await reminderService.requestAccess()

        // Auto-join all public channels if configured
        if config.autoJoinChannels {
            await joinAllPublicChannels()
            startPeriodicChannelScan()
        }

        print("👂 Listening for mentions of <@\(config.trackedUserId)>...")

        socketMode = SlackSocketMode(appToken: config.slackAppToken,
                                     onEvent: { [weak self] event in await self?.handleEvent(event) },
                                     onConnect: { [weak self] in await self?.catchUp() })

        await socketMode?.start()
    }

    func stop() async {
        channelScanTask?.cancel()
        channelScanTask = nil
        await socketMode?.stop()
    }

    /// Periodically scan for new public channels and join them (every hour).
    private func startPeriodicChannelScan() {
        channelScanTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3600 * 1_000_000_000) // 1 hour
                guard !Task.isCancelled else { break }
                await self?.joinAllPublicChannels()
            }
        }
    }

    /// Join all public channels the bot isn't already a member of.
    private func joinAllPublicChannels() async {
        do {
            let channels = try await slackAPI.listAllPublicChannels()
            let toJoin = channels.filter { !$0.isMember }

            if toJoin.isEmpty {
                print("✅ Already in all \(channels.count) public channels")
                return
            }

            print("📢 Joining \(toJoin.count) public channel(s)...")
            for channel in toJoin {
                try await slackAPI.joinChannel(channelId: channel.id)
            }
            print("✅ Joined \(toJoin.count) channel(s), now in \(channels.count) total")
        } catch {
            print("⚠️  Auto-join failed: \(error)")
        }
    }

    /// Catch up on missed mentions since last seen timestamp.
    private func catchUp() async {
        guard !lastSeenTs.isEmpty else {
            // First run — no baseline, just start tracking from now
            updateLastSeen(ts: String(Date().timeIntervalSince1970))
            print("📌 First run — tracking mentions from now")
            return
        }

        print("🔄 Catching up on missed mentions since \(lastSeenTs)...")

        do {
            let channels = try await slackAPI.listConversations()
            var catchUpCount = 0

            for channel in channels {
                let messages = try await slackAPI.conversationsHistory(channel: channel.id, oldest: lastSeenTs)
                for msg in messages {
                    guard let text = msg["text"] as? String,
                          let user = msg["user"] as? String,
                          let ts = msg["ts"] as? String,
                          text.contains("<@\(config.trackedUserId)>"),
                          msg["subtype"] == nil else { continue }

                    let event = SlackEvent(type: "message", text: text, user: user,
                                           channel: channel.id, ts: ts, subtype: nil)
                    updateLastSeen(ts: ts)
                    await processEvent(event)
                    catchUpCount += 1
                }
            }

            if catchUpCount > 0 {
                print("✅ Caught up on \(catchUpCount) missed mention(s)")
            } else {
                print("✅ No missed mentions")
            }
        } catch {
            print("⚠️  Catch-up failed: \(error)")
        }
    }

    private func updateLastSeen(ts: String) {
        if ts > lastSeenTs {
            lastSeenTs = ts
            try? ts.write(to: Self.tsFilePath, atomically: true, encoding: .utf8)
        }
    }

    private func handleEvent(_ event: SlackEvent) async {
        guard event.isMention(of: config.trackedUserId) else { return }
        updateLastSeen(ts: event.ts)
        await processEvent(event)
    }

    /// Shared processing for both real-time and catch-up events.
    private func processEvent(_ event: SlackEvent) async {
        print("🔔 Mention detected in \(event.channel) from \(event.user)")

        // 1. React with 👀
        do {
            try await slackAPI.addReaction(channel: event.channel, timestamp: event.ts, emoji: config.reactionEmoji)
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

        // 3. Resolve user mentions in message text
        let resolvedText = await resolveMentions(in: event.text)

        // 4. Create Apple Reminder using templates
        let title = Config.applyTemplate(config.reminderTitleTemplate,
                                          sender: senderName, channel: channelName,
                                          message: resolvedText, permalink: permalink)
        let notes = Config.applyTemplate(config.reminderNotesTemplate,
                                          sender: senderName, channel: channelName,
                                          message: resolvedText, permalink: permalink)

        await reminderService.createReminder(title: title, notes: notes)

        // 5. macOS notification
        await sendLocalNotification(title: "Slack mention", body: "\(senderName) in #\(channelName)")
    }

    /// Cache of resolved user IDs → display names.
    private var userNameCache: [String: String] = [:]

    /// Replace <@U...> mentions in text with @displayName.
    private func resolveMentions(in text: String) async -> String {
        guard let regex = try? NSRegularExpression(pattern: "<@(U[A-Z0-9]+)>") else { return text }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var result = text

        // Collect unique user IDs
        var userIds = Set<String>()
        for match in matches {
            if match.numberOfRanges > 1 {
                userIds.insert(nsText.substring(with: match.range(at: 1)))
            }
        }

        // Resolve each user ID
        for userId in userIds {
            let displayName: String
            if let cached = userNameCache[userId] {
                displayName = cached
            } else {
                do {
                    let info = try await slackAPI.getUserInfo(userId: userId)
                    let name = info.realName ?? info.name
                    userNameCache[userId] = name
                    displayName = name
                } catch {
                    displayName = userId
                }
            }
            result = result.replacingOccurrences(of: "<@\(userId)>", with: "@\(displayName)")
        }

        return result
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
