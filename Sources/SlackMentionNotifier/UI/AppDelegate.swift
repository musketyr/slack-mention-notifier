import AppKit

/// Menu bar app delegate — shows a status item and manages the Slack connection.
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mentionHandler: MentionHandler?
    private var statusMenuItem: NSMenuItem!
    private var authMenuItem: NSMenuItem!
    private var config: Config!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (menu bar only)
        NSApp.setActivationPolicy(.accessory)

        config = Config.load()

        // Create menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "Slack Mentions")
        statusItem.button?.image?.size = NSSize(width: 18, height: 18)

        buildMenu()

        // Use text fallback if SF Symbol isn't available
        if statusItem.button?.image == nil {
            statusItem.button?.title = "🔔"
        }

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
        
        } else {
            statusMenuItem.title = "⚠ Missing config"
            print("❌ Bot token not configured. Set SLACK_BOT_TOKEN in config or add SLACK_CLIENT_ID + SLACK_CLIENT_SECRET for OAuth.")
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

        let signOutItem = NSMenuItem(title: "Sign Out", action: #selector(signOut), keyEquivalent: "")
        signOutItem.target = self
        menu.addItem(signOutItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

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

                Config.saveOAuthResult(result)
                let teamName = result.teamName ?? "workspace"
                print("✅ Authenticated with \(teamName)")

                // Reload config with new tokens
                config = Config.load()

                if config.isReady {
                    await MainActor.run {
                        statusMenuItem.title = "● Connected (\(teamName))"
                        authMenuItem.isHidden = true
                    }
                    await startHandler()
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
