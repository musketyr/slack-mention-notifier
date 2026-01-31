import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Slack Web API client for reactions, user info, channel info, and permalinks.
struct SlackAPI {
    let botToken: String

    /// Add a reaction to a message.
    func addReaction(channel: String, timestamp: String, emoji: String) async throws {
        let body: [String: Any] = [
            "channel": channel,
            "timestamp": timestamp,
            "name": emoji
        ]
        let result = try await post("reactions.add", body: body)
        if result["ok"] as? Bool != true {
            let error = result["error"] as? String ?? "unknown"
            // "already_reacted" is fine
            if error != "already_reacted" {
                print("⚠️  Failed to add reaction: \(error)")
            }
        }
    }

    /// Get a permalink for a message.
    func getPermalink(channel: String, timestamp: String) async throws -> String? {
        let body: [String: Any] = [
            "channel": channel,
            "message_ts": timestamp
        ]
        let result = try await post("chat.getPermalink", body: body)
        return result["permalink"] as? String
    }

    /// Get user display info.
    func getUserInfo(userId: String) async throws -> (name: String, realName: String?) {
        let body: [String: Any] = ["user": userId]
        let result = try await post("users.info", body: body)

        if let user = result["user"] as? [String: Any] {
            let name = user["name"] as? String ?? userId
            let realName = (user["real_name"] as? String) ??
                           (user["profile"] as? [String: Any])?["real_name"] as? String
            return (name, realName)
        }
        return (userId, nil)
    }

    /// Get channel name.
    func getChannelInfo(channelId: String) async throws -> String? {
        let body: [String: Any] = ["channel": channelId]
        let result = try await post("conversations.info", body: body)
        return (result["channel"] as? [String: Any])?["name"] as? String
    }

    // MARK: - HTTP

    private func post(_ method: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://slack.com/api/\(method)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(botToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
