import EventKit
import Foundation

/// Creates Apple Reminders via EventKit.
///
/// Uses a single shared EKEventStore for all operations. A fresh store
/// may not see calendars immediately after authorization — the shared
/// instance avoids this race by persisting across the app lifetime.
class ReminderService {
    private let listName: String
    private var hasAccess = false

    /// Single shared store for all EventKit operations.
    private static let store = EKEventStore()
    private static var storeHasAccess = false

    init(listName: String) {
        self.listName = listName
    }

    /// Request access to Reminders (macOS will show a permission dialog on first use).
    func requestAccess() async {
        let granted = await Self.ensureAccess()
        hasAccess = granted
        if granted {
            Logger.log("✅ Reminders access granted")
        } else {
            Logger.log("⚠️  Reminders access denied — reminders will be skipped")
        }
    }

    /// Create a reminder in the configured list.
    func createReminder(title: String, notes: String?) async {
        guard hasAccess else { return }

        let store = Self.store
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = findOrDefaultCalendar()

        do {
            try store.save(reminder, commit: true)
            Logger.log("✅ Reminder created: \(title)")
        } catch {
            Logger.log("⚠️  Failed to create reminder: \(error)")
        }
    }

    /// Find the target calendar by name, or fall back to the default reminders calendar.
    private func findOrDefaultCalendar() -> EKCalendar {
        let store = Self.store
        let calendars = store.calendars(for: .reminder)
        let defaultCalendar = store.defaultCalendarForNewReminders()

        Logger.log("📋 Available Reminders lists: \(calendars.map { $0.title }.joined(separator: ", "))")
        Logger.log("📋 System default list: \(defaultCalendar?.title ?? "none")")

        // If user hasn't explicitly configured a list, use system default
        if listName == Config.defaultReminderListName {
            if let cal = defaultCalendar {
                Logger.log("📋 Using system default list: \(cal.title)")
                return cal
            }
        }

        // Try to find by exact name
        if let match = calendars.first(where: { $0.title == listName }) {
            return match
        }

        // Try case-insensitive match
        if let match = calendars.first(where: { $0.title.lowercased() == listName.lowercased() }) {
            Logger.log("📋 Found list '\(match.title)' (case-insensitive match for '\(listName)')")
            return match
        }

        Logger.log("⚠️  Reminder list '\(listName)' not found, using default")
        if let cal = defaultCalendar ?? calendars.first {
            return cal
        }
        // No calendars at all — create a fallback (shouldn't happen, but don't crash)
        Logger.log("⚠️  No Reminders calendars found, creating fallback")
        let fallback = EKCalendar(for: .reminder, eventStore: store)
        fallback.title = "Reminders"
        if let source = store.sources.first(where: { $0.sourceType == .local }) ?? store.sources.first {
            fallback.source = source
            try? store.saveCalendar(fallback, commit: true)
        }
        return fallback
    }

    // MARK: - Shared Access (used by Preferences and instance)

    /// Ensure access on the shared store. Safe to call multiple times.
    static func ensureAccess() async -> Bool {
        if storeHasAccess { return true }
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await store.requestFullAccessToReminders()
            } else {
                granted = try await store.requestAccess(to: .reminder)
            }
            storeHasAccess = granted
            return granted
        } catch {
            return false
        }
    }

    /// Request access on the shared store (convenience alias for Preferences).
    static func requestSharedAccess() async -> Bool {
        return await ensureAccess()
    }

    /// Get all available Reminders list names.
    static func availableLists() -> [String] {
        return store.calendars(for: .reminder).map { $0.title }
    }
}
