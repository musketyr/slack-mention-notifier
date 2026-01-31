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
        let result = try await get("chat.getPermalink", params: [
            "channel": channel,
            "message_ts": timestamp
        ])
        return result["permalink"] as? String
    }

    /// Get user display info.
    func getUserInfo(userId: String) async throws -> (name: String, realName: String?) {
        let result = try await get("users.info", params: ["user": userId])

        if result["ok"] as? Bool != true {
            print("⚠️  users.info failed: \(result["error"] as? String ?? "unknown")")
            return (userId, nil)
        }

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
        let result = try await get("conversations.info", params: ["channel": channelId])

        if result["ok"] as? Bool != true {
            print("⚠️  conversations.info failed: \(result["error"] as? String ?? "unknown")")
            return nil
        }

        return (result["channel"] as? [String: Any])?["name"] as? String
    }

    /// List conversations the bot is a member of.
    func listConversations() async throws -> [(id: String, name: String)] {
        var allChannels: [(id: String, name: String)] = []
        var cursor: String? = nil

        repeat {
            var params: [String: String] = [
                "types": "public_channel,private_channel,mpim,im",
                "limit": "200"
            ]
            if let cursor = cursor {
                params["cursor"] = cursor
            }

            let result = try await get("users.conversations", params: params)

            if result["ok"] as? Bool != true {
                print("⚠️  users.conversations failed: \(result["error"] as? String ?? "unknown")")
                break
            }

            if let channels = result["channels"] as? [[String: Any]] {
                for ch in channels {
                    if let id = ch["id"] as? String {
                        let name = ch["name"] as? String ?? id
                        allChannels.append((id: id, name: name))
                    }
                }
            }

            cursor = (result["response_metadata"] as? [String: Any])?["next_cursor"] as? String
            if cursor?.isEmpty == true { cursor = nil }
        } while cursor != nil

        return allChannels
    }

    /// Fetch messages from a channel since a given timestamp.
    func conversationsHistory(channel: String, oldest: String, limit: Int = 200) async throws -> [[String: Any]] {
        let result = try await get("conversations.history", params: [
            "channel": channel,
            "oldest": oldest,
            "limit": String(limit),
            "inclusive": "false"
        ])

        if result["ok"] as? Bool != true {
            let error = result["error"] as? String ?? "unknown"
            if error != "not_in_channel" && error != "channel_not_found" {
                print("⚠️  conversations.history(\(channel)) failed: \(error)")
            }
            return []
        }

        return result["messages"] as? [[String: Any]] ?? []
    }

    // MARK: - HTTP

    /// POST with JSON body (for write methods like reactions.add).
    private func post(_ method: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://slack.com/api/\(method)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(botToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// GET with query parameters (for read methods like users.info, conversations.info).
    private func get(_ method: String, params: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(string: "https://slack.com/api/\(method)")!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(botToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
