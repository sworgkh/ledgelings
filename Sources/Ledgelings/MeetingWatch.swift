import EventKit
import Foundation

/// The Mac's calendar, read for one thing only: a meeting about to start, for Clock ticking (SPEC §7.19).
/// Nothing is asked for until the owner switches "Look at my calendar" on and allows it.
@MainActor
final class MeetingWatch {
    private lazy var store = EKEventStore()

    static var allowed: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Asks the Mac for the calendar; true once it is allowed.
    func ask() async -> Bool {
        if Self.allowed { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Meetings (not all-day events) starting after `now` and within `minutes`: their identifiers and titles.
    func startingSoon(at now: Date, within minutes: Double = 5) -> [(id: String, title: String)] {
        guard Self.allowed else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(minutes * 60), calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate > now }
            .map { ("\($0.calendarItemIdentifier)@\($0.startDate.timeIntervalSince1970)", $0.title ?? "") }
    }
}
