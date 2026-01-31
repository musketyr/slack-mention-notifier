import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends notifications via Telegram Bot API.
struct TelegramNotifier {
    let botToken: String
    let chatId: String

    /// Send a text message (Markdown V2 format).
    func send(_ text: String) async {
        let url = URL(string: "https://api.telegram.org/bot\(botToken)/sendMessage")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "chat_id": chatId,
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": true
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("⚠️  Telegram send failed: HTTP \(httpResponse.statusCode)")
            }
        } catch {
            print("⚠️  Telegram send error: \(error)")
        }
    }
}
