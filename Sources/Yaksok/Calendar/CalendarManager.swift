import EventKit
import AppKit

/// EventKit wrapper for calendar access and event creation
/// Adapted from MakeSchedule/CalendarManager.swift with @Observable
@Observable
@MainActor
final class CalendarManager {
    let store = EKEventStore()
    var calendars: [EKCalendar] = []
    var accessGranted = false
    var authorizationChecked = false
    var errorMessage: String?

    // MARK: - Lifecycle

    init() {
        // 외부 앱에서 캘린더 변경 시 자동 갱신
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.accessGranted else { return }
                self.loadCalendars()
            }
        }
    }

    // MARK: - Access

    func requestAccess() {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.handleAccessResult(granted: granted, error: error)
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.handleAccessResult(granted: granted, error: error)
                }
            }
        }
    }

    private func handleAccessResult(granted: Bool, error: Error?) {
        accessGranted = granted
        authorizationChecked = true
        if granted {
            loadCalendars()
        } else {
            errorMessage = error?.localizedDescription
                ?? String(localized: "캘린더 접근 권한이 거부되었습니다.", comment: "Calendar permission")
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Calendars

    private func loadCalendars() {
        let allCalendars = store.calendars(for: .event)
        calendars = allCalendars
            .filter { $0.allowsContentModifications }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    // MARK: - Event creation

    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        location: String,
        notes: String,
        calendar: EKCalendar
    ) throws {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay
        event.location = location.isEmpty ? nil : location
        event.notes = notes.isEmpty ? nil : notes
        event.calendar = calendar
        try store.save(event, span: .thisEvent)
        Log.calendar.info("Event created: \(title)")
    }

    // MARK: - Event Query (Conflict Check)

    /// Fetch events for a given date from specified calendars
    func fetchEvents(for date: Date, calendarIDs: Set<String>) -> [EKEvent] {
        guard accessGranted, !calendarIDs.isEmpty else { return [] }

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let allCalendars = store.calendars(for: .event)
        let targetCalendars = allCalendars.filter {
            calendarIDs.contains($0.calendarIdentifier) && $0.type != .birthday
        }
        guard !targetCalendars.isEmpty else { return [] }

        Log.debug("[Conflict] Querying \(targetCalendars.count) calendars for \(dayStart)")
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: targetCalendars)
        let events = store.events(matching: predicate)
            .filter { event in
                // Exclude birthday events (from any calendar)
                if event.birthdayContactIdentifier != nil { return false }
                // Exclude calendars with birthday-like titles
                let title = event.calendar?.title.lowercased() ?? ""
                if title.contains("생일") || title.contains("birthday") { return false }
                return true
            }
            .sorted { $0.startDate < $1.startDate }
        Log.debug("[Conflict] Found \(events.count) events")
        return events
    }

    /// All calendars (including read-only) for conflict check selection
    func allCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    // MARK: - Last calendar persistence

    private static let lastCalendarKey = "lastCalendarName"

    static func loadLastCalendarName() -> String? {
        UserDefaults.standard.string(forKey: lastCalendarKey)
    }

    static func saveLastCalendarName(_ name: String) {
        UserDefaults.standard.set(name, forKey: lastCalendarKey)
    }

    static func clearLastCalendarName() {
        UserDefaults.standard.removeObject(forKey: lastCalendarKey)
    }
}
