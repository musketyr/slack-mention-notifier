import EventKit
import Foundation

/// Creates Apple Reminders via EventKit.
class ReminderService {
    private let store = EKEventStore()
    private let listName: String
    private var hasAccess = false

    init(listName: String) {
        self.listName = listName
    }

    /// Request access to Reminders (macOS will show a permission dialog on first use).
    func requestAccess() async {
        do {
            if #available(macOS 14.0, *) {
                hasAccess = try await store.requestFullAccessToReminders()
            } else {
                hasAccess = try await store.requestAccess(to: .reminder)
            }
            if hasAccess {
                Logger.log("✅ Reminders access granted")
            } else {
                Logger.log("⚠️  Reminders access denied — reminders will be skipped")
            }
        } catch {
            Logger.log("⚠️  Reminders access error: \(error). Reminders will be skipped.")
        }
    }

    /// Create a reminder in the configured list.
    func createReminder(title: String, notes: String?) async {
        guard hasAccess else { return }

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
        return defaultCalendar ?? calendars.first!
    }

    /// Shared store for listing calendars (persists across calls so calendars are available).
    private static let sharedStore = EKEventStore()
    private static var sharedStoreHasAccess = false

    /// Request access on the shared store (call once before using availableLists).
    static func requestSharedAccess() async -> Bool {
        if sharedStoreHasAccess { return true }
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await sharedStore.requestFullAccessToReminders()
            } else {
                granted = try await sharedStore.requestAccess(to: .reminder)
            }
            sharedStoreHasAccess = granted
            return granted
        } catch {
            return false
        }
    }

    /// Get all available Reminders list names.
    static func availableLists() -> [String] {
        return sharedStore.calendars(for: .reminder).map { $0.title }
    }
}
