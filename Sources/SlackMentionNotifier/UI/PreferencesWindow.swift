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
    private var titleTemplateCombo: NSComboBox!
    private var notesTemplateCombo: NSComboBox!
    private var customEmojis: [String] = []
    private var loadingSpinner: NSProgressIndicator!
    private var previewLabel: NSTextField!

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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
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
        var y: CGFloat = contentView.bounds.height - 44

        // --- Section: General ---
        let generalHeader = makeSectionHeader("General", x: margin, y: y)
        contentView.addSubview(generalHeader)
        y -= 30

        // --- Reminders List ---
        let reminderLabel = makeLabel("Reminders list:", x: margin, y: y)
        contentView.addSubview(reminderLabel)

        reminderListPopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 26))
        reminderListPopup.removeAllItems()
        populateReminderLists()
        contentView.addSubview(reminderListPopup)

        y -= 34

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

        y -= 20
        let emojiHint = NSTextField(labelWithString: "Slack emoji name without colons (e.g. eyes, thumbsup)")
        emojiHint.font = NSFont.systemFont(ofSize: 11)
        emojiHint.textColor = .secondaryLabelColor
        emojiHint.frame = NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 16)
        contentView.addSubview(emojiHint)

        y -= 28

        // --- Auto-join ---
        autoJoinCheckbox = NSButton(checkboxWithTitle: "Automatically join all public channels", target: nil, action: nil)
        autoJoinCheckbox.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 22)
        contentView.addSubview(autoJoinCheckbox)

        y -= 40

        // --- Section: Reminder Templates ---
        let templateHeader = makeSectionHeader("Reminder Templates", x: margin, y: y)
        contentView.addSubview(templateHeader)
        y -= 22
        let templateHint = NSTextField(labelWithString: "Use \\n for newlines. Placeholders: {sender} {channel} {message} {permalink} {date}")
        templateHint.font = NSFont.systemFont(ofSize: 11)
        templateHint.textColor = .tertiaryLabelColor
        templateHint.frame = NSRect(x: margin, y: y, width: contentView.bounds.width - margin * 2, height: 16)
        contentView.addSubview(templateHint)
        y -= 30

        // --- Title Template ---
        let titleLabel = makeLabel("Title:", x: margin, y: y)
        contentView.addSubview(titleLabel)

        titleTemplateCombo = NSComboBox(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 26))
        titleTemplateCombo.isEditable = true
        titleTemplateCombo.completes = false
        titleTemplateCombo.numberOfVisibleItems = 6
        titleTemplateCombo.addItems(withObjectValues: Config.titlePresets.map { $0.template })
        titleTemplateCombo.target = self
        titleTemplateCombo.action = #selector(templateChanged)
        contentView.addSubview(titleTemplateCombo)

        y -= 34

        // --- Notes Template ---
        let notesLabel = makeLabel("Notes:", x: margin, y: y)
        contentView.addSubview(notesLabel)

        notesTemplateCombo = NSComboBox(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 26))
        notesTemplateCombo.isEditable = true
        notesTemplateCombo.completes = false
        notesTemplateCombo.numberOfVisibleItems = 6
        notesTemplateCombo.addItems(withObjectValues: Config.notesPresets.map { $0.template })
        notesTemplateCombo.target = self
        notesTemplateCombo.action = #selector(templateChanged)
        contentView.addSubview(notesTemplateCombo)

        y -= 30

        // --- Preview ---
        let previewBox = NSBox(frame: NSRect(x: fieldX - 8, y: y - 64, width: fieldWidth + 16, height: 80))
        previewBox.boxType = .custom
        previewBox.borderColor = .separatorColor
        previewBox.borderWidth = 1
        previewBox.cornerRadius = 6
        previewBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5)
        previewBox.titlePosition = .noTitle
        contentView.addSubview(previewBox)

        previewLabel = NSTextField(wrappingLabelWithString: "")
        previewLabel.font = NSFont.systemFont(ofSize: 11)
        previewLabel.textColor = .labelColor
        previewLabel.frame = NSRect(x: fieldX, y: y - 60, width: fieldWidth, height: 72)
        previewLabel.maximumNumberOfLines = 6
        previewLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(previewLabel)

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

    private func makeSectionHeader(_ text: String, x: CGFloat, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        label.textColor = .labelColor
        label.frame = NSRect(x: x, y: y, width: 300, height: 18)
        return label
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

        // Set templates
        titleTemplateCombo.stringValue = config.reminderTitleTemplate
        notesTemplateCombo.stringValue = config.reminderNotesTemplate

        updatePreview()
    }

    @objc private func templateChanged() {
        updatePreview()
    }

    private func updatePreview() {
        let titleTemplate = titleTemplateCombo.stringValue
        let notesTemplate = notesTemplateCombo.stringValue

        let title = Config.applyTemplate(titleTemplate,
                                          sender: "Jane Doe", channel: "general",
                                          message: "Hey @you, can you review this PR?",
                                          permalink: "https://slack.com/archives/C01/p1234")
        let notes = Config.applyTemplate(notesTemplate,
                                          sender: "Jane Doe", channel: "general",
                                          message: "Hey @you, can you review this PR?",
                                          permalink: "https://slack.com/archives/C01/p1234")

        previewLabel.stringValue = "📌 \(title)\n📝 \(notes)"
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
        let titleTemplate = titleTemplateCombo.stringValue.trimmingCharacters(in: .whitespaces)
        let notesTemplate = notesTemplateCombo.stringValue.trimmingCharacters(in: .whitespaces)

        // Strip glyph prefix if user selected from dropdown (e.g. "👀  eyes" → "eyes", "✦  custom" → "custom")
        if let spaceRange = emoji.range(of: "  ") {
            emoji = String(emoji[spaceRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        // Config keys managed by preferences
        let managedKeys: Set<String> = [
            "APPLE_REMINDERS_LIST", "REACTION_EMOJI", "AUTO_JOIN_CHANNELS",
            "REMINDER_TITLE_TEMPLATE", "REMINDER_NOTES_TEMPLATE"
        ]

        // Write to config file
        var lines: [String] = []

        // Read existing config to preserve other values
        if let contents = try? String(contentsOf: Config.envFilePath, encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let key = trimmed.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
                if managedKeys.contains(key) { continue }
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
        if titleTemplate != Config.defaultTitleTemplate {
            lines.append("REMINDER_TITLE_TEMPLATE=\(titleTemplate)")
        }
        if notesTemplate != Config.defaultNotesTemplate {
            lines.append("REMINDER_NOTES_TEMPLATE=\(notesTemplate)")
        }

        let content = lines.joined(separator: "\n") + "\n"
        try? content.write(to: Config.envFilePath, atomically: true, encoding: .utf8)

        print("💾 Preferences saved: list=\(reminderList), emoji=\(emoji), autoJoin=\(autoJoin), titleTemplate=\(titleTemplate)")
        self.close()

        // Notify AppDelegate to reload config and reconnect
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @objc private func cancelPreferences() {
        self.close()
    }
}
