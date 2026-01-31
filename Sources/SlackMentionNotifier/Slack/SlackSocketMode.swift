import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Slack Socket Mode client — connects via WebSocket to receive events in real-time.
/// No public HTTP endpoint needed.
actor SlackSocketMode {
    private let appToken: String
    private let onEvent: (SlackEvent) async -> Void
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var isRunning = false
    private var reconnectDelay: TimeInterval = 1.0

    init(appToken: String, onEvent: @escaping (SlackEvent) async -> Void) {
        self.appToken = appToken
        self.onEvent = onEvent
    }

    /// Start the Socket Mode connection loop (reconnects automatically).
    func start() async {
        isRunning = true
        while isRunning {
            do {
                try await connect()
            } catch {
                print("⚠️  Socket Mode error: \(error). Reconnecting in \(reconnectDelay)s...")
                try? await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
                reconnectDelay = min(reconnectDelay * 2, 30.0) // exponential backoff, max 30s
            }
        }
    }

    func stop() {
        isRunning = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    /// Request a WebSocket URL from Slack and connect.
    private func connect() async throws {
        let wsUrl = try await requestWebSocketUrl()
        print("🔌 Connecting to Slack Socket Mode...")

        let session = URLSession(configuration: .default)
        self.session = session

        let task = session.webSocketTask(with: URL(string: wsUrl)!)
        self.webSocketTask = task
        task.resume()

        reconnectDelay = 1.0 // reset on successful connect
        print("✅ Connected to Slack Socket Mode")

        // Read messages until disconnected
        while isRunning {
            let message = try await task.receive()
            switch message {
            case .string(let text):
                await handleMessage(text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    await handleMessage(text)
                }
            @unknown default:
                break
            }
        }
    }

    /// POST to apps.connections.open to get a WebSocket URL.
    private func requestWebSocketUrl() async throws -> String {
        var request = URLRequest(url: URL(string: "https://slack.com/api/apps.connections.open")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        guard json["ok"] as? Bool == true, let url = json["url"] as? String else {
            let error = json["error"] as? String ?? "unknown"
            throw SlackError.connectionFailed(error)
        }

        return url
    }

    /// Parse and dispatch a Socket Mode message.
    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Acknowledge the envelope
        if let envelopeId = json["envelope_id"] as? String {
            await acknowledge(envelopeId)
        }

        let type = json["type"] as? String ?? ""

        switch type {
        case "events_api":
            guard let payload = json["payload"] as? [String: Any],
                  let event = payload["event"] as? [String: Any] else { return }
            if let slackEvent = SlackEvent.parse(event) {
                await onEvent(slackEvent)
            }

        case "disconnect":
            print("🔌 Slack requested disconnect, will reconnect...")
            webSocketTask?.cancel(with: .goingAway, reason: nil)

        case "hello":
            print("👋 Slack Socket Mode handshake complete")

        default:
            break
        }
    }

    /// Acknowledge a Socket Mode envelope (required to prevent retries).
    private func acknowledge(_ envelopeId: String) async {
        let ack = ["envelope_id": envelopeId]
        guard let data = try? JSONSerialization.data(withJSONObject: ack),
              let text = String(data: data, encoding: .utf8) else { return }

        try? await webSocketTask?.send(.string(text))
    }
}

enum SlackError: Error {
    case connectionFailed(String)
    case apiError(String)
}
