import Foundation
import Network
#if canImport(AppKit)
import AppKit
#endif

/// Handles the Slack OAuth 2.0 flow using a local HTTP server for the redirect.
actor OAuthFlow {
    private let clientId: String
    private let clientSecret: String
    private let scopes: [String]

    /// Bot scopes required by the app.
    static let requiredScopes = [
        "channels:history",
        "channels:read",
        "chat:write",
        "groups:history",
        "groups:read",
        "im:history",
        "im:read",
        "mpim:history",
        "mpim:read",
        "reactions:write",
        "users:read"
    ]

    init(clientId: String, clientSecret: String, scopes: [String] = OAuthFlow.requiredScopes) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.scopes = scopes
    }

    /// Run the full OAuth flow: start local server → open browser → wait for code → exchange for token.
    /// Returns (botToken, teamName, authedUserId).
    func authenticate() async throws -> OAuthResult {
        // 1. Start local callback server
        let server = CallbackServer()
        let port = try await server.start()
        let redirectUri = "http://localhost:\(port)/callback"

        print("🔐 OAuth callback server listening on port \(port)")

        // 2. Open Slack authorization page in browser
        let scopeString = scopes.joined(separator: ",")
        let authUrl = "https://slack.com/oauth/v2/authorize"
            + "?client_id=\(clientId)"
            + "&scope=\(scopeString)"
            + "&redirect_uri=\(redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"

        print("🌐 Opening Slack authorization page...")
        await openInBrowser(url: authUrl)

        // 3. Wait for the callback with the authorization code
        let code = try await server.waitForCode()
        await server.stop()

        print("✅ Authorization code received, exchanging for token...")

        // 4. Exchange code for bot token
        let result = try await exchangeCode(code: code, redirectUri: redirectUri)
        return result
    }

    /// Exchange the authorization code for a bot token.
    private func exchangeCode(code: String, redirectUri: String) async throws -> OAuthResult {
        var components = URLComponents(string: "https://slack.com/api/oauth.v2.access")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectUri)
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.invalidResponse
        }

        guard json["ok"] as? Bool == true else {
            let error = json["error"] as? String ?? "unknown"
            throw OAuthError.slackError(error)
        }

        guard let accessToken = json["access_token"] as? String else {
            throw OAuthError.missingToken
        }

        let teamName = (json["team"] as? [String: Any])?["name"] as? String
        let authedUserId = (json["authed_user"] as? [String: Any])?["id"] as? String

        return OAuthResult(
            botToken: accessToken,
            teamName: teamName,
            authedUserId: authedUserId
        )
    }

    private func openInBrowser(url: String) async {
        #if canImport(AppKit)
        await MainActor.run {
            if let nsUrl = URL(string: url) {
                NSWorkspace.shared.open(nsUrl)
            }
        }
        #endif
    }
}

// MARK: - Models

struct OAuthResult {
    let botToken: String
    let teamName: String?
    let authedUserId: String?
}

enum OAuthError: Error, LocalizedError {
    case serverStartFailed
    case timeout
    case invalidResponse
    case slackError(String)
    case missingToken
    case denied(String)

    var errorDescription: String? {
        switch self {
        case .serverStartFailed: return "Failed to start local OAuth server"
        case .timeout: return "OAuth flow timed out"
        case .invalidResponse: return "Invalid response from Slack"
        case .slackError(let msg): return "Slack error: \(msg)"
        case .missingToken: return "No access token in response"
        case .denied(let msg): return "Authorization denied: \(msg)"
        }
    }
}

// MARK: - Local Callback Server

/// Minimal HTTP server that listens on localhost for the OAuth redirect callback.
private actor CallbackServer {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?

    /// Start the server and return the port it's listening on.
    func start() throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        // Use a class wrapper to safely capture in the Sendable closure
        final class PortBox: @unchecked Sendable {
            var port: UInt16 = 0
        }
        let portBox = PortBox()
        let ready = DispatchSemaphore(value: 0)

        listener.stateUpdateHandler = { state in
            if case .ready = state {
                portBox.port = listener.port?.rawValue ?? 0
                ready.signal()
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleConnection(connection) }
        }

        listener.start(queue: DispatchQueue(label: "oauth-callback"))

        // Wait up to 5 seconds for listener to be ready
        guard ready.wait(timeout: .now() + 5) == .success, portBox.port > 0 else {
            throw OAuthError.serverStartFailed
        }

        return portBox.port
    }

    /// Wait for the authorization code from the callback.
    func waitForCode() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            // Timeout after 5 minutes
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                if self.continuation != nil {
                    self.continuation?.resume(throwing: OAuthError.timeout)
                    self.continuation = nil
                }
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Handle an incoming HTTP connection.
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "oauth-connection"))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            Task { await self?.processRequest(data: data, connection: connection) }
        }
    }

    private func processRequest(data: Data?, connection: NWConnection) {
        guard let data = data,
              let request = String(data: data, encoding: .utf8) else {
            connection.cancel()
            return
        }

        // Parse the GET request for the code parameter
        guard let firstLine = request.split(separator: "\r\n").first,
              let path = firstLine.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: String(path)) else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Bad request")
            return
        }

        let params = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )

        if let error = params["error"] {
            sendResponse(connection: connection, status: "200 OK",
                        body: "Authorization denied: \(error). You can close this tab.")
            continuation?.resume(throwing: OAuthError.denied(error))
            continuation = nil
        } else if let code = params["code"] {
            sendResponse(connection: connection, status: "200 OK",
                        body: successHTML())
            continuation?.resume(returning: code)
            continuation = nil
        } else {
            sendResponse(connection: connection, status: "400 Bad Request",
                        body: "Missing authorization code.")
        }
    }

    private func sendResponse(connection: NWConnection, status: String, body: String) {
        let response = """
            HTTP/1.1 \(status)\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func successHTML() -> String {
        return """
        <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding: 60px;">
        <h1>✅ Authorized!</h1>
        <p>Slack Mention Notifier is now connected. You can close this tab.</p>
        </body></html>
        """
    }
}
