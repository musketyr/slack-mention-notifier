import EventKit
import Foundation

/// Creates Apple Reminders via EventKit.
///
/// Uses a single shared EKEventStore for all operations. After authorization,
/// the store may not immediately see calendars — we call refreshSourcesIfNecessary()
/// and wait for EKEventStoreChanged to ensure calendars are loaded.
class ReminderService {
    private let listName: String
    private var hasAccess = false

    /// Single shared store for all EventKit operations.
    private static let store = EKEventStore()
    private static var storeHasAccess = false
    private static var storeReady = false  // true once calendars are confirmed available

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

        // If calendars aren't available yet, try refreshing
        if store.calendars(for: .reminder).isEmpty {
            Logger.log("📋 Calendars empty, refreshing sources...")
            await Self.refreshAndWait()
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes

        guard let calendar = findOrDefaultCalendar() else {
            Logger.log("⚠️  Cannot create reminder — no calendars available")
            return
        }
        reminder.calendar = calendar

        do {
            try store.save(reminder, commit: true)
            Logger.log("✅ Reminder created: \(title)")
        } catch {
            Logger.log("⚠️  Failed to create reminder: \(error)")
        }
    }

    /// Find the target calendar by name, or fall back to the default reminders calendar.
    private func findOrDefaultCalendar() -> EKCalendar? {
        let store = Self.store
        let calendars = store.calendars(for: .reminder)
        let defaultCalendar = store.defaultCalendarForNewReminders()

        Logger.log("📋 Available Reminders lists: \(calendars.map { $0.title }.joined(separator: ", "))")
        Logger.log("📋 System default list: \(defaultCalendar?.title ?? "none")")

        if calendars.isEmpty && defaultCalendar == nil {
            return nil
        }

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
        return defaultCalendar ?? calendars.first
    }

    // MARK: - Shared Access

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

            if granted {
                // Trigger source refresh so calendars become available
                await refreshAndWait()
            }

            return granted
        } catch {
            return false
        }
    }

    /// Refresh the store's sources and wait for calendars to become available.
    private static func refreshAndWait() async {
        store.refreshSourcesIfNecessary()

        // Wait for EKEventStoreChanged or up to 5 seconds
        let startTime = Date()
        let timeout: TimeInterval = 5.0

        // Check immediately first
        if !store.calendars(for: .reminder).isEmpty {
            Logger.log("📋 Calendars available immediately after refresh")
            storeReady = true
            return
        }

        // Poll with small delays (EKEventStoreChanged is posted on the default notification center
        // but we're in an async context, so polling is simpler and reliable)
        while Date().timeIntervalSince(startTime) < timeout {
            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms
            let calendars = store.calendars(for: .reminder)
            if !calendars.isEmpty {
                Logger.log("📋 Calendars available after \(String(format: "%.1f", Date().timeIntervalSince(startTime)))s: \(calendars.map { $0.title }.joined(separator: ", "))")
                storeReady = true
                return
            }
        }

        Logger.log("⚠️  Calendars still empty after \(timeout)s timeout")
    }

    /// Convenience alias for Preferences.
    static func requestSharedAccess() async -> Bool {
        return await ensureAccess()
    }

    /// Get all available Reminders list names.
    static func availableLists() -> [String] {
        return store.calendars(for: .reminder).map { $0.title }
    }
}
