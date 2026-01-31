import Foundation

/// Simple file logger that also mirrors to stdout.
/// Log file: ~/.config/slack-mention-notifier/app.log
enum Logger {
    /// Maximum log file size before rotation (1 MB).
    private static let maxLogSize: UInt64 = 1_000_000

    static let logFileURL: URL = Config.configDir.appendingPathComponent("app.log")

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let fileHandle: FileHandle? = {
        let url = logFileURL
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        return try? FileHandle(forWritingTo: url)
    }()

    /// Initialize: rotate if needed, seek to end.
    static func setup() {
        rotateIfNeeded()
        fileHandle?.seekToEndOfFile()
        log("--- App started ---")
    }

    /// Log a message to both stdout and the log file.
    static func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        // stdout
        print(message)

        // File
        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }

    /// Rotate log file if it exceeds maxLogSize.
    private static func rotateIfNeeded() {
        let url = logFileURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              size > maxLogSize else { return }

        let oldURL = url.deletingLastPathComponent().appendingPathComponent("app.log.old")
        try? FileManager.default.removeItem(at: oldURL)
        try? FileManager.default.moveItem(at: url, to: oldURL)
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    /// Flush pending writes.
    static func flush() {
        fileHandle?.synchronizeFile()
    }
}
