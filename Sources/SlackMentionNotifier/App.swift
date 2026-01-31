import AppKit

/// Entry point — launches the menu bar app.
@main
struct SlackMentionNotifierApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
