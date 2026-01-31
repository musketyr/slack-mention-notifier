import AppKit
import ServiceManagement

/// Menu bar app delegate — shows a status item and manages the Slack connection.
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mentionHandler: MentionHandler?
    private var statusMenuItem: NSMenuItem!
    private var authMenuItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var preferencesWindow: PreferencesWindow?
    private var config: Config!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (menu bar only)
        NSApp.setActivationPolicy(.accessory)

        config = Config.load()

        // Observe preference changes for live reload
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePreferencesChanged),
            name: .preferencesDidChange, object: nil
        )

        // Create menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "Slack Mentions")
        statusItem.button?.image?.size = NSSize(width: 18, height: 18)

        // Use text fallback if SF Symbol isn't available
        if statusItem.button?.image == nil {
            statusItem.button?.title = "🔔"
        }

        buildMenu()

        print("📌 Menu bar item created")

        if config.isReady {
            Task { @MainActor in
                statusMenuItem.title = "● Connecting..."
                await startHandler()
            }
        } else if config.isOAuthAvailable {
            statusMenuItem.title = "○ Not connected"
            authMenuItem.title = "Sign in with Slack..."
            authMenuItem.isHidden = false
            print("🔐 OAuth available — click the 🔔 menu bar icon → 'Sign in with Slack...'")
        } else if config.slackAppToken.isEmpty {
            statusMenuItem.title = "⚠ Not configured"
            print("❌ No embedded secrets and no config file found.")
            print("   Create ~/.config/slack-mention-notifier/config.env with your tokens.")
        } else {
            statusMenuItem.title = "⚠ Missing config"
            print("❌ Bot token not configured. Click 'Sign in with Slack...' or set SLACK_BOT_TOKEN in config.")
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Slack Mention Notifier", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        statusMenuItem = NSMenuItem(title: "Connecting...", action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem)

        authMenuItem = NSMenuItem(title: "Sign in with Slack...", action: #selector(signInWithSlack), keyEquivalent: "")
        authMenuItem.target = self
        authMenuItem.isHidden = true
        menu.addItem(authMenuItem)

        menu.addItem(NSMenuItem.separator())

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        let signOutItem = NSMenuItem(title: "Sign Out", action: #selector(signOut), keyEquivalent: "")
        signOutItem.target = self
        menu.addItem(signOutItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Launch at Login

    private var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if isLaunchAtLoginEnabled {
                    try SMAppService.mainApp.unregister()
                    launchAtLoginItem.state = .off
                    print("⏹  Launch at Login disabled")
                } else {
                    try SMAppService.mainApp.register()
                    launchAtLoginItem.state = .on
                    print("✅ Launch at Login enabled")
                }
            } catch {
                print("⚠️  Failed to toggle Launch at Login: \(error)")
            }
        }
    }

    // MARK: - Preferences

    @objc private func openPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow()
        }
        // Load custom emoji if we have a bot token
        if let botToken = config.slackBotToken.isEmpty ? nil : config.slackBotToken {
            preferencesWindow?.loadCustomEmoji(botToken: botToken)
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Preferences Reload

    @objc private func handlePreferencesChanged() {
        Task {
            // Stop existing handler
            await mentionHandler?.stop()
            mentionHandler = nil

            // Reload config from disk
            config = Config.load()
            print("🔄 Config reloaded after preferences change")

            if config.isReady {
                await MainActor.run {
                    statusMenuItem.title = "● Reconnecting..."
                }
                await startHandler()
            }
        }
    }

    // MARK: - Slack Connection

    private func startHandler() async {
        mentionHandler = MentionHandler(config: config)

        await MainActor.run {
            statusMenuItem.title = "● Connected"
            authMenuItem.isHidden = true
        }

        await mentionHandler?.start()
    }

    @objc private func signInWithSlack() {
        guard let clientId = config.slackClientId,
              let clientSecret = config.slackClientSecret else { return }

        statusMenuItem.title = "○ Signing in..."
        authMenuItem.isEnabled = false

        Task {
            do {
                let oauth = OAuthFlow(clientId: clientId, clientSecret: clientSecret)
                let result = try await oauth.authenticate()

                let saved = Config.saveOAuthResult(result)
                let teamName = result.teamName ?? "workspace"
                print("✅ Authenticated with \(teamName)")
                print("   botToken: \(result.botToken.prefix(12))..., userId: \(result.authedUserId ?? "nil")")
                print("   Keychain save: botToken=\(saved.botToken), userId=\(saved.userId), team=\(saved.teamName)")

                // Reload config with new tokens
                config = Config.load()
                print("   Config ready: \(config.isReady) (appToken=\(!config.slackAppToken.isEmpty), botToken=\(!config.slackBotToken.isEmpty), userId=\(!config.trackedUserId.isEmpty))")

                if config.isReady {
                    await MainActor.run {
                        statusMenuItem.title = "● Connected (\(teamName))"
                        authMenuItem.isHidden = true
                    }
                    await startHandler()
                } else {
                    await MainActor.run {
                        statusMenuItem.title = "⚠ Incomplete config"
                        authMenuItem.isEnabled = true

                        var missing: [String] = []
                        if config.slackAppToken.isEmpty { missing.append("App Token (SLACK_APP_TOKEN)") }
                        if config.slackBotToken.isEmpty { missing.append("Bot Token") }
                        if config.trackedUserId.isEmpty { missing.append("User ID") }

                        let alert = NSAlert()
                        alert.messageText = "Sign-in Incomplete"
                        alert.informativeText = "OAuth succeeded but the app still needs: \(missing.joined(separator: ", ")). Check your config.env file."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            } catch {
                print("❌ OAuth failed: \(error)")
                await MainActor.run {
                    statusMenuItem.title = "⚠ Sign-in failed"
                    authMenuItem.isEnabled = true

                    let alert = NSAlert()
                    alert.messageText = "Sign-in Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    @objc private func signOut() {
        Task {
            await mentionHandler?.stop()
            mentionHandler = nil
        }

        Config.clearAuth()
        config = Config.load()

        if config.isOAuthAvailable {
            statusMenuItem.title = "○ Not connected"
            authMenuItem.title = "Sign in with Slack..."
            authMenuItem.isHidden = false
            authMenuItem.isEnabled = true
        } else {
            statusMenuItem.title = "○ Signed out"
        }

        print("👋 Signed out, tokens cleared from Keychain")
    }

    @objc private func quit() {
        Task {
            await mentionHandler?.stop()
        }
        NSApp.terminate(nil)
    }
}
