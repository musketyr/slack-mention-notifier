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
                print("✅ Reminders access granted")
            } else {
                print("⚠️  Reminders access denied — reminders will be skipped")
            }
        } catch {
            print("⚠️  Reminders access error: \(error). Reminders will be skipped.")
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
            print("✅ Reminder created: \(title)")
        } catch {
            print("⚠️  Failed to create reminder: \(error)")
        }
    }

    /// Find the target calendar by name, or fall back to the default reminders calendar.
    private func findOrDefaultCalendar() -> EKCalendar {
        let calendars = store.calendars(for: .reminder)

        if let match = calendars.first(where: { $0.title == listName }) {
            return match
        }

        print("⚠️  Reminder list '\(listName)' not found, using default")
        return store.defaultCalendarForNewReminders() ?? calendars.first!
    }

    /// Get all available Reminders list names.
    static func availableLists() -> [String] {
        let store = EKEventStore()
        return store.calendars(for: .reminder).map { $0.title }
    }
}
