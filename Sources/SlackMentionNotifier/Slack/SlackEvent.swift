import Foundation

/// A parsed Slack message event.
struct SlackEvent {
    let type: String
    let text: String
    let user: String
    let channel: String
    let ts: String
    let subtype: String?

    /// Parse a Slack event dictionary into a SlackEvent.
    static func parse(_ dict: [String: Any]) -> SlackEvent? {
        guard let type = dict["type"] as? String,
              let text = dict["text"] as? String,
              let user = dict["user"] as? String,
              let channel = dict["channel"] as? String,
              let ts = dict["ts"] as? String else { return nil }

        return SlackEvent(
            type: type,
            text: text,
            user: user,
            channel: channel,
            ts: ts,
            subtype: dict["subtype"] as? String
        )
    }

    /// Check if this event is a message mentioning a specific user.
    func isMention(of userId: String) -> Bool {
        return type == "message" && subtype == nil && text.contains("<@\(userId)>")
    }
}
