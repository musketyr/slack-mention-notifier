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
    private var titlePresetPopup: NSPopUpButton!
    private var notesPresetPopup: NSPopUpButton!
    private var titleCustomField: NSTextField!
    private var notesCustomField: NSTextField!
    private var customEmojis: [String] = []
    private var loadingSpinner: NSProgressIndicator!
    private var previewLabel: NSTextField!
    private var errorLabel: NSTextField!
    private var saveButton: NSButton!

    /// Known template placeholders.
    private static let validPlaceholders: Set<String> = [
        "sender", "channel", "message", "permalink", "date"
    ]

    /// Standard Slack emoji names with their Unicode glyphs, grouped by category.
    /// Comprehensive list covering the most commonly used emojis.
    private static let standardEmojis: [(name: String, glyph: String)] = [
        // --- Reactions / Acknowledgement ---
        ("eyes", "👀"), ("thumbsup", "👍"), ("thumbsdown", "👎"),
        ("+1", "👍"), ("-1", "👎"),
        ("white_check_mark", "✅"), ("heavy_check_mark", "✔️"),
        ("ballot_box_with_check", "☑️"),
        ("ok_hand", "👌"), ("raised_hands", "🙌"), ("clap", "👏"),
        ("pray", "🙏"), ("handshake", "🤝"), ("wave", "👋"),
        ("muscle", "💪"), ("brain", "🧠"), ("saluting_face", "🫡"),
        ("100", "💯"), ("fire", "🔥"), ("star", "⭐"), ("sparkles", "✨"),
        ("tada", "🎉"), ("confetti_ball", "🎊"), ("trophy", "🏆"),
        ("medal", "🏅"), ("crown", "👑"),

        // --- Emotions ---
        ("heart", "❤️"), ("heart_eyes", "😍"), ("smiling_face_with_3_hearts", "🥰"),
        ("blush", "😊"), ("smile", "😄"), ("grinning", "😀"),
        ("joy", "😂"), ("rofl", "🤣"), ("laughing", "😆"),
        ("wink", "😉"), ("relieved", "😌"), ("sunglasses", "😎"),
        ("thinking_face", "🤔"), ("face_with_monocle", "🧐"),
        ("exploding_head", "🤯"), ("open_mouth", "😮"),
        ("hushed", "😯"), ("astonished", "😲"),
        ("cry", "😢"), ("sob", "😭"),
        ("scream", "😱"), ("face_with_rolling_eyes", "🙄"),
        ("unamused", "😒"), ("grimacing", "😬"), ("sweat_smile", "😅"),
        ("sweat", "😓"), ("facepalm", "🤦"), ("shrug", "🤷"),
        ("skull", "💀"), ("ghost", "👻"), ("see_no_evil", "🙈"),
        ("hear_no_evil", "🙉"), ("speak_no_evil", "🙊"),
        ("nerd_face", "🤓"), ("robot_face", "🤖"),
        ("hugging_face", "🤗"), ("zipper_mouth_face", "🤐"),

        // --- Hands / Gestures ---
        ("point_up", "☝️"), ("point_up_2", "👆"), ("point_down", "👇"),
        ("point_left", "👈"), ("point_right", "👉"),
        ("raised_hand", "✋"), ("v", "✌️"), ("crossed_fingers", "🤞"),
        ("call_me_hand", "🤙"), ("metal", "🤘"), ("love_you_gesture", "🤟"),
        ("writing_hand", "✍️"), ("raising_hand", "🙋"),

        // --- Objects / Symbols ---
        ("bell", "🔔"), ("bookmark", "🔖"), ("pushpin", "📌"),
        ("round_pushpin", "📍"), ("bulb", "💡"), ("dart", "🎯"),
        ("memo", "📝"), ("clipboard", "📋"),
        ("mag", "🔍"), ("mag_right", "🔎"),
        ("hourglass", "⏳"), ("hourglass_flowing_sand", "⏳"),
        ("alarm_clock", "⏰"), ("stopwatch", "⏱"),
        ("calendar", "📅"), ("date", "📅"),
        ("inbox_tray", "📥"), ("outbox_tray", "📤"),
        ("envelope", "✉️"), ("email", "📧"),
        ("link", "🔗"), ("paperclip", "📎"),
        ("key", "🔑"), ("lock", "🔒"), ("unlock", "🔓"),
        ("hammer", "🔨"), ("wrench", "🔧"), ("gear", "⚙️"),
        ("package", "📦"), ("gift", "🎁"),

        // --- Status / Alerts ---
        ("rotating_light", "🚨"), ("warning", "⚠️"),
        ("no_entry_sign", "🚫"), ("x", "❌"), ("o", "⭕"),
        ("red_circle", "🔴"), ("large_blue_circle", "🔵"),
        ("large_green_circle", "🟢"), ("yellow_circle", "🟡"),
        ("white_circle", "⚪"), ("black_circle", "⚫"),
        ("question", "❓"), ("exclamation", "❗"),
        ("bangbang", "‼️"), ("interrobang", "⁉️"),
        ("speech_balloon", "💬"), ("thought_balloon", "💭"),
        ("mega", "📣"), ("loudspeaker", "📢"),
        ("triangular_flag_on_post", "🚩"),

        // --- Arrows / Movement ---
        ("arrow_up", "⬆️"), ("arrow_down", "⬇️"),
        ("arrow_left", "⬅️"), ("arrow_right", "➡️"),
        ("arrow_heading_up", "⤴️"), ("arrow_heading_down", "⤵️"),
        ("recycle", "♻️"), ("repeat", "🔁"), ("back", "🔙"),
        ("soon", "🔜"), ("top", "🔝"),

        // --- Nature / Weather ---
        ("sunny", "☀️"), ("cloud", "☁️"), ("rainbow", "🌈"),
        ("zap", "⚡"), ("snowflake", "❄️"),
        ("herb", "🌿"), ("four_leaf_clover", "🍀"),
        ("seedling", "🌱"), ("evergreen_tree", "🌲"),
        ("deciduous_tree", "🌳"), ("cactus", "🌵"),
        ("cherry_blossom", "🌸"), ("sunflower", "🌻"), ("rose", "🌹"),

        // --- Animals ---
        ("dog", "🐶"), ("cat", "🐱"), ("bear", "🐻"),
        ("unicorn_face", "🦄"), ("butterfly", "🦋"),
        ("bee", "🐝"), ("bug", "🐛"), ("snail", "🐌"),
        ("owl", "🦉"), ("eagle", "🦅"), ("parrot", "🦜"),
        ("penguin", "🐧"), ("fox_face", "🦊"), ("wolf", "🐺"),
        ("gorilla", "🦍"), ("monkey_face", "🐵"),
        ("rabbit", "🐰"), ("turtle", "🐢"), ("snake", "🐍"),
        ("octopus", "🐙"), ("shark", "🦈"),

        // --- Food / Drink ---
        ("coffee", "☕"), ("tea", "🍵"), ("beer", "🍺"), ("beers", "🍻"),
        ("wine_glass", "🍷"), ("champagne", "🍾"), ("cocktail", "🍸"),
        ("pizza", "🍕"), ("hamburger", "🍔"), ("taco", "🌮"),
        ("cake", "🎂"), ("cookie", "🍪"), ("doughnut", "🍩"),
        ("apple", "🍎"), ("banana", "🍌"), ("avocado", "🥑"),
        ("hot_pepper", "🌶"), ("popcorn", "🍿"), ("ice_cream", "🍦"),

        // --- Tech ---
        ("computer", "💻"), ("keyboard", "⌨️"), ("desktop_computer", "🖥"),
        ("mobile_phone", "📱"), ("battery", "🔋"),
        ("electric_plug", "🔌"), ("satellite", "📡"),
        ("floppy_disk", "💾"), ("cd", "💿"),

        // --- Travel / Places ---
        ("rocket", "🚀"), ("airplane", "✈️"), ("car", "🚗"),
        ("ship", "🛳"), ("earth_americas", "🌎"),
        ("house", "🏠"), ("office", "🏢"),

        // --- Sports / Activities ---
        ("soccer", "⚽"), ("basketball", "🏀"), ("football", "🏈"),
        ("tennis", "🎾"), ("bowling", "🎳"),
        ("video_game", "🎮"), ("game_die", "🎲"),
        ("musical_note", "🎵"), ("headphones", "🎧"),
        ("art", "🎨"), ("performing_arts", "🎭"),

        // --- Hearts ---
        ("orange_heart", "🧡"), ("yellow_heart", "💛"),
        ("green_heart", "💚"), ("blue_heart", "💙"),
        ("purple_heart", "💜"), ("black_heart", "🖤"),
        ("white_heart", "🤍"), ("brown_heart", "🤎"),
        ("broken_heart", "💔"), ("heartbeat", "💓"),
        ("heartpulse", "💗"), ("sparkling_heart", "💖"),
        ("revolving_hearts", "💞"), ("two_hearts", "💕"),

        // --- Misc popular ---
        ("money_with_wings", "💸"), ("moneybag", "💰"),
        ("gem", "💎"), ("boom", "💥"), ("dizzy", "💫"),
        ("poop", "💩"), ("thumbsup_all", "👍"),
        ("rainbow_flag", "🏳️‍🌈"), ("checkered_flag", "🏁"),
        ("pirate_flag", "🏴‍☠️"), ("white_flag", "🏳️"),
        ("construction", "🚧"), ("stop_sign", "🛑"),
    ]

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 540),
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

        // ═══════════════════ Section: General ═══════════════════
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
        emojiField.numberOfVisibleItems = 20
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

        // ═══════════════════ Section: Reminder Templates ═══════════════════
        let templateHeader = makeSectionHeader("Reminder Templates", x: margin, y: y)
        contentView.addSubview(templateHeader)
        y -= 30

        // --- Title Template ---
        let titleLabel = makeLabel("Title:", x: margin, y: y)
        contentView.addSubview(titleLabel)

        titlePresetPopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 26))
        for preset in Config.titlePresets {
            titlePresetPopup.addItem(withTitle: preset.name)
        }
        titlePresetPopup.addItem(withTitle: "Custom")
        titlePresetPopup.target = self
        titlePresetPopup.action = #selector(titlePresetChanged)
        contentView.addSubview(titlePresetPopup)

        y -= 30

        titleCustomField = NSTextField(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 24))
        titleCustomField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        titleCustomField.placeholderString = "e.g. Slack: {sender} in #{channel}"
        titleCustomField.isHidden = true
        titleCustomField.target = self
        titleCustomField.action = #selector(customTemplateEdited)
        contentView.addSubview(titleCustomField)

        y -= 34

        // --- Notes Template ---
        let notesLabel = makeLabel("Notes:", x: margin, y: y)
        contentView.addSubview(notesLabel)

        notesPresetPopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 26))
        for preset in Config.notesPresets {
            notesPresetPopup.addItem(withTitle: preset.name)
        }
        notesPresetPopup.addItem(withTitle: "Custom")
        notesPresetPopup.target = self
        notesPresetPopup.action = #selector(notesPresetChanged)
        contentView.addSubview(notesPresetPopup)

        y -= 30

        notesCustomField = NSTextField(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 24))
        notesCustomField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        notesCustomField.placeholderString = #"e.g. {message}\n\n{permalink}"#
        notesCustomField.isHidden = true
        notesCustomField.target = self
        notesCustomField.action = #selector(customTemplateEdited)
        contentView.addSubview(notesCustomField)

        y -= 14
        let templateHint = NSTextField(labelWithString: #"Use \n for newlines. Placeholders: {sender} {channel} {message} {permalink} {date}"#)
        templateHint.font = NSFont.systemFont(ofSize: 11)
        templateHint.textColor = .tertiaryLabelColor
        templateHint.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 16)
        contentView.addSubview(templateHint)

        y -= 28

        // --- Error Label ---
        errorLabel = NSTextField(labelWithString: "")
        errorLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        errorLabel.textColor = .systemRed
        errorLabel.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 16)
        errorLabel.isHidden = true
        contentView.addSubview(errorLabel)

        y -= 8

        // --- Preview ---
        let previewBox = NSBox(frame: NSRect(x: fieldX - 8, y: y - 80, width: fieldWidth + 16, height: 86))
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
        previewLabel.frame = NSRect(x: fieldX, y: y - 76, width: fieldWidth, height: 78)
        previewLabel.maximumNumberOfLines = 6
        previewLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(previewLabel)

        // --- Buttons ---
        saveButton = NSButton(title: "Save", target: self, action: #selector(savePreferences))
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

    // MARK: - Template Preset Handlers

    @objc private func titlePresetChanged() {
        let isCustom = titlePresetPopup.titleOfSelectedItem == "Custom"
        titleCustomField.isHidden = !isCustom
        if !isCustom {
            titleCustomField.stringValue = ""
        }
        validateAndPreview()
    }

    @objc private func notesPresetChanged() {
        let isCustom = notesPresetPopup.titleOfSelectedItem == "Custom"
        notesCustomField.isHidden = !isCustom
        if !isCustom {
            notesCustomField.stringValue = ""
        }
        validateAndPreview()
    }

    @objc private func customTemplateEdited() {
        validateAndPreview()
    }

    /// Get the effective title template based on current selection.
    private func effectiveTitleTemplate() -> String {
        if titlePresetPopup.titleOfSelectedItem == "Custom" {
            return titleCustomField.stringValue
        }
        let selectedName = titlePresetPopup.titleOfSelectedItem ?? ""
        return Config.titlePresets.first { $0.name == selectedName }?.template ?? Config.defaultTitleTemplate
    }

    /// Get the effective notes template based on current selection.
    private func effectiveNotesTemplate() -> String {
        if notesPresetPopup.titleOfSelectedItem == "Custom" {
            return notesCustomField.stringValue
        }
        let selectedName = notesPresetPopup.titleOfSelectedItem ?? ""
        return Config.notesPresets.first { $0.name == selectedName }?.template ?? Config.defaultNotesTemplate
    }

    /// Find unknown placeholders in a template string.
    private func unknownPlaceholders(in template: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\{([a-zA-Z_]+)\\}") else { return [] }
        let nsTemplate = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: nsTemplate.length))
        var unknown: [String] = []
        for match in matches {
            if match.numberOfRanges > 1 {
                let name = nsTemplate.substring(with: match.range(at: 1))
                if !Self.validPlaceholders.contains(name) {
                    unknown.append("{\(name)}")
                }
            }
        }
        return unknown
    }

    /// Validate templates and update preview. Returns true if valid.
    @discardableResult
    private func validateAndPreview() -> Bool {
        let titleTemplate = effectiveTitleTemplate()
        let notesTemplate = effectiveNotesTemplate()

        let unknownTitle = unknownPlaceholders(in: titleTemplate)
        let unknownNotes = unknownPlaceholders(in: notesTemplate)
        let allUnknown = unknownTitle + unknownNotes

        if !allUnknown.isEmpty {
            let unique = Array(Set(allUnknown)).sorted()
            errorLabel.stringValue = "⚠ Unknown placeholder\(unique.count > 1 ? "s" : ""): \(unique.joined(separator: ", "))"
            errorLabel.isHidden = false
            saveButton.isEnabled = false
            previewLabel.stringValue = ""
            return false
        }

        errorLabel.isHidden = true
        saveButton.isEnabled = true

        // Render preview
        let title = Config.applyTemplate(titleTemplate,
                                          sender: "Jane Doe", channel: "general",
                                          message: "Hey @you, can you review this PR?",
                                          permalink: "https://slack.com/archives/C01/p1234")
        let notes = Config.applyTemplate(notesTemplate,
                                          sender: "Jane Doe", channel: "general",
                                          message: "Hey @you, can you review this PR?",
                                          permalink: "https://slack.com/archives/C01/p1234")

        previewLabel.stringValue = "📌 \(title)\n📝 \(notes)"
        return true
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

        // Set title template
        if let match = Config.titlePresets.first(where: { $0.template == config.reminderTitleTemplate }) {
            titlePresetPopup.selectItem(withTitle: match.name)
            titleCustomField.isHidden = true
        } else {
            titlePresetPopup.selectItem(withTitle: "Custom")
            titleCustomField.isHidden = false
            titleCustomField.stringValue = config.reminderTitleTemplate
        }

        // Set notes template
        if let match = Config.notesPresets.first(where: { $0.template == config.reminderNotesTemplate }) {
            notesPresetPopup.selectItem(withTitle: match.name)
            notesCustomField.isHidden = true
        } else {
            notesPresetPopup.selectItem(withTitle: "Custom")
            notesCustomField.isHidden = false
            notesCustomField.stringValue = config.reminderNotesTemplate
        }

        validateAndPreview()
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
        guard validateAndPreview() else { return }

        let reminderList = reminderListPopup.titleOfSelectedItem ?? "Reminders"
        var emoji = emojiField.stringValue.trimmingCharacters(in: .whitespaces)
        let autoJoin = autoJoinCheckbox.state == .on
        let titleTemplate = effectiveTitleTemplate()
        let notesTemplate = effectiveNotesTemplate()

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

        Logger.log("💾 Preferences saved: list=\(reminderList), emoji=\(emoji), autoJoin=\(autoJoin), titleTemplate=\(titleTemplate)")
        self.close()

        // Notify AppDelegate to reload config and reconnect
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @objc private func cancelPreferences() {
        self.close()
    }
}
