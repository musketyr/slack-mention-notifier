import AppKit

/// Menu bar app delegate — shows a status item and manages the Slack connection.
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mentionHandler: MentionHandler?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (menu bar only)
        NSApp.setActivationPolicy(.accessory)

        // Create menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "Slack Mentions")
        statusItem.button?.image?.size = NSSize(width: 18, height: 18)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Slack Mention Notifier", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let statusMenuItem = NSMenuItem(title: "Connecting...", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 1
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        // Start the mention handler
        Task {
            await startHandler(statusMenuItem: statusMenuItem)
        }
    }

    private func startHandler(statusMenuItem: NSMenuItem) async {
        let config = Config.load()
        mentionHandler = MentionHandler(config: config)

        // Update status in menu
        await MainActor.run {
            statusMenuItem.title = "● Connected"
        }

        await mentionHandler?.start()
    }

    @objc private func quit() {
        Task {
            await mentionHandler?.stop()
        }
        NSApp.terminate(nil)
    }
}
