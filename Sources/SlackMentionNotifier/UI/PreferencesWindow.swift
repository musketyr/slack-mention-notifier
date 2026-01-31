import AppKit
import EventKit

extension Notification.Name {
    /// Posted when the user saves preferences; AppDelegate observes this to reload.
    static let preferencesDidChange = Notification.Name("PreferencesDidChange")
}

/// Preferences window for configuring the app.
class PreferencesWindow: NSWindow {
    private var reminderListPopup: NSPopUpButton!
    private var emojiField: NSComboBox!
    private var autoJoinCheckbox: NSButton!
    private var customEmojis: [String] = []
    private var loadingSpinner: NSProgressIndicator!

    /// Common standard Slack emoji names with their Unicode glyphs.
    private static let standardEmojis: [(name: String, glyph: String)] = [
        ("eyes", "👀"), ("white_check_mark", "✅"), ("heavy_check_mark", "✔️"),
        ("thumbsup", "👍"), ("thumbsdown", "👎"), ("raised_hands", "🙌"),
        ("pray", "🙏"), ("wave", "👋"), ("bell", "🔔"), ("bookmark", "🔖"),
        ("bulb", "💡"), ("dart", "🎯"), ("memo", "📝"), ("pushpin", "📌"),
        ("round_pushpin", "📍"), ("star", "⭐"), ("sparkles", "✨"), ("fire", "🔥"),
        ("heart", "❤️"), ("100", "💯"), ("ok_hand", "👌"), ("muscle", "💪"),
        ("brain", "🧠"), ("mag", "🔍"), ("hourglass", "⏳"), ("rotating_light", "🚨"),
        ("warning", "⚠️"), ("speech_balloon", "💬"), ("thought_balloon", "💭"),
        ("inbox_tray", "📥")
    ]

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.title = "Slack Mention Notifier — Preferences"
        self.isReleasedWhenClosed = false
        self.center()

        setupUI()
        loadCurrentValues()
        requestRemindersAccessIfNeeded()
    }

    private func setupUI() {
        let contentView = NSView(frame: self.contentRect(forFrameRect: self.frame))
        self.contentView = contentView

        let margin: CGFloat = 24
        let labelWidth: CGFloat = 120
        let fieldX = margin + labelWidth + 8
        let fieldWidth: CGFloat = contentView.bounds.width - fieldX - margin
        var y: CGFloat = contentView.bounds.height - 52

        // --- Reminders List ---
        let reminderLabel = makeLabel("Reminders list:", x: margin, y: y)
        contentView.addSubview(reminderLabel)

        reminderListPopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 26))
        reminderListPopup.removeAllItems()
        populateReminderLists()
        contentView.addSubview(reminderListPopup)

        y -= 40

        // --- Reaction Emoji ---
        let emojiLabel = makeLabel("Reaction emoji:", x: margin, y: y)
        contentView.addSubview(emojiLabel)

        emojiField = NSComboBox(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 26))
        emojiField.isEditable = true
        emojiField.completes = true
        emojiField.numberOfVisibleItems = 12
        populateStandardEmoji()
        contentView.addSubview(emojiField)

        // Spinner for loading custom emoji
        loadingSpinner = NSProgressIndicator()
        loadingSpinner.style = .spinning
        loadingSpinner.controlSize = .small
        loadingSpinner.frame = NSRect(x: fieldX + fieldWidth + 4, y: y, width: 16, height: 16)
        loadingSpinner.isHidden = true
        contentView.addSubview(loadingSpinner)

        y -= 24
        let emojiHint = NSTextField(labelWithString: "Slack emoji name without colons (e.g. eyes, thumbsup)")
        emojiHint.font = NSFont.systemFont(ofSize: 11)
        emojiHint.textColor = .secondaryLabelColor
        emojiHint.frame = NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 16)
        contentView.addSubview(emojiHint)

        y -= 32

        // --- Auto-join ---
        autoJoinCheckbox = NSButton(checkboxWithTitle: "Automatically join all public channels", target: nil, action: nil)
        autoJoinCheckbox.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 22)
        contentView.addSubview(autoJoinCheckbox)

        y -= 48

        // --- Buttons ---
        let saveButton = NSButton(title: "Save", target: self, action: #selector(savePreferences))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: contentView.bounds.width - margin - 80, y: margin, width: 80, height: 32)
        contentView.addSubview(saveButton)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelPreferences))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.frame = NSRect(x: contentView.bounds.width - margin - 170, y: margin, width: 80, height: 32)
        contentView.addSubview(cancelButton)
    }

    private func populateReminderLists() {
        reminderListPopup.removeAllItems()
        let lists = ReminderService.availableLists()
        if lists.isEmpty {
            reminderListPopup.addItem(withTitle: "Reminders")
        } else {
            reminderListPopup.addItems(withTitles: lists)
        }
    }

    private func populateStandardEmoji() {
        emojiField.removeAllItems()
        let items = Self.standardEmojis.map { "\($0.glyph)  \($0.name)" }
        emojiField.addItems(withObjectValues: items)
    }

    /// Request Reminders access so the list dropdown is populated even before the handler starts.
    private func requestRemindersAccessIfNeeded() {
        let store = EKEventStore()
        Task {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = (try? await store.requestFullAccessToReminders()) ?? false
            } else {
                granted = (try? await store.requestAccess(to: .reminder)) ?? false
            }
            if granted {
                await MainActor.run {
                    let config = Config.load()
                    populateReminderLists()
                    if reminderListPopup.itemTitles.contains(config.reminderListName) {
                        reminderListPopup.selectItem(withTitle: config.reminderListName)
                    }
                }
            }
        }
    }

    private func makeLabel(_ text: String, x: CGFloat, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.alignment = .right
        label.frame = NSRect(x: x, y: y, width: 120, height: 20)
        return label
    }

    private func loadCurrentValues() {
        let config = Config.load()

        // Select current reminders list
        if reminderListPopup.itemTitles.contains(config.reminderListName) {
            reminderListPopup.selectItem(withTitle: config.reminderListName)
        }

        // Set current emoji
        emojiField.stringValue = config.reactionEmoji

        // Set auto-join
        autoJoinCheckbox.state = config.autoJoinChannels ? .on : .off
    }

    /// Load custom emoji from Slack (call after sign-in).
    func loadCustomEmoji(botToken: String) {
        loadingSpinner.isHidden = false
        loadingSpinner.startAnimation(nil)

        Task {
            let api = SlackAPI(botToken: botToken)
            let custom = try? await api.listEmoji()
            await MainActor.run {
                loadingSpinner.stopAnimation(nil)
                loadingSpinner.isHidden = true

                if let custom = custom, !custom.isEmpty {
                    self.customEmojis = custom
                    // Save the current value before rebuilding
                    let currentValue = self.emojiField.stringValue
                    self.emojiField.removeAllItems()
                    // Custom emoji first (prefixed with ✦ to distinguish)
                    let customItems = custom.map { "✦  \($0)" }
                    let standardItems = Self.standardEmojis.map { "\($0.glyph)  \($0.name)" }
                    self.emojiField.addItems(withObjectValues: customItems + standardItems)
                    // Restore the field value
                    self.emojiField.stringValue = currentValue
                }
            }
        }
    }

    @objc private func savePreferences() {
        let reminderList = reminderListPopup.titleOfSelectedItem ?? "Reminders"
        var emoji = emojiField.stringValue.trimmingCharacters(in: .whitespaces)
        let autoJoin = autoJoinCheckbox.state == .on

        // Strip glyph prefix if user selected from dropdown (e.g. "👀  eyes" → "eyes", "✦  custom" → "custom")
        if let spaceRange = emoji.range(of: "  ") {
            emoji = String(emoji[spaceRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        // Write to config file
        var lines: [String] = []

        // Read existing config to preserve other values
        if let contents = try? String(contentsOf: Config.envFilePath, encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Skip lines we're going to rewrite
                if trimmed.hasPrefix("APPLE_REMINDERS_LIST=") ||
                   trimmed.hasPrefix("REACTION_EMOJI=") ||
                   trimmed.hasPrefix("AUTO_JOIN_CHANNELS=") {
                    continue
                }
                lines.append(line)
            }
        }

        // Remove trailing empty lines
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }

        // Add our settings
        lines.append("")
        lines.append("APPLE_REMINDERS_LIST=\(reminderList)")
        if !emoji.isEmpty {
            lines.append("REACTION_EMOJI=\(emoji)")
        }
        lines.append("AUTO_JOIN_CHANNELS=\(autoJoin)")

        let content = lines.joined(separator: "\n") + "\n"
        try? content.write(to: Config.envFilePath, atomically: true, encoding: .utf8)

        print("💾 Preferences saved: list=\(reminderList), emoji=\(emoji), autoJoin=\(autoJoin)")
        self.close()

        // Notify AppDelegate to reload config and reconnect
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @objc private func cancelPreferences() {
        self.close()
    }
}
