import Foundation

/// The alarm each calendar event has now, until the event is acknowledged in the app.
///
/// An event first rings `leadMinutes` before it starts. Each time its alarm is stopped, the next one rings a
/// minute later, and so on until the user acknowledges the event. Only the current alarm of each event is kept,
/// so repeats are planned one at a time and nothing is scheduled far ahead.
struct CalendarEventRings: Codable, Hashable, Sendable {
    /// The alarm that is scheduled or ringing now, by occurrence (`SyncedCalendarEvent.id`).
    private(set) var current: [String: CalendarEventAlarm] = [:]
    /// Occurrences acknowledged in the app, with their start, so that they do not ring again.
    private(set) var acknowledged: [String: Date] = [:]

    /// Time between a stop and the next repeat.
    static let repeatInterval: TimeInterval = 60
    /// How long an acknowledgement is remembered after its event starts.
    static let retention: TimeInterval = 2 * 24 * 60 * 60

    /// Brings the alarms up to date with the calendar.
    ///
    /// - Parameters:
    ///   - planned: the first alarm of each upcoming event, from `CalendarEventAlarmPlanner`.
    ///   - events: every event read from the calendar in the window; an occurrence that is no longer there
    ///     (deleted, moved, canceled or declined) drops its alarm.
    ///   - scheduled: the IDs of the alarms the system still holds, or `nil` when they are not known.
    ///     A current alarm that the system no longer holds and whose time has passed was stopped without the app
    ///     hearing about it, so its next repeat is planned from `now`.
    mutating func reconcile(
        planned: [CalendarEventAlarm],
        events: [CalendarEventSnapshot],
        scheduled: Set<UUID>?,
        now: Date
    ) {
        acknowledged = acknowledged.filter { $0.value > now.addingTimeInterval(-Self.retention) }
        let live = Set(events.filter { !$0.isAllDay && !$0.isSkipped }.map(SyncedCalendarEvent.id(for:)))
        current = current.filter { live.contains($0.key) }

        for alarm in planned where acknowledged[alarm.occurrenceID] == nil {
            // An alarm that has already rung keeps its place in the chain; so does a repeat.
            if let existing = current[alarm.occurrenceID], existing.isRepeat || existing.fireDate <= now { continue }
            current[alarm.occurrenceID] = alarm
        }

        guard let scheduled else { return }
        for (occurrenceID, alarm) in current where alarm.fireDate <= now && !scheduled.contains(alarm.id) {
            current[occurrenceID] = alarm.repeated(at: now.addingTimeInterval(Self.repeatInterval))
        }
    }

    /// The user stopped the alarm `alarmID`: its repeat rings a minute after `now`.
    mutating func stopped(_ alarmID: UUID, now: Date) {
        guard let entry = current.first(where: { $0.value.id == alarmID }) else { return }
        current[entry.key] = entry.value.repeated(at: now.addingTimeInterval(Self.repeatInterval))
    }

    /// The user acknowledged the event in the app: its alarm stops, and it does not ring again.
    mutating func acknowledge(_ occurrenceID: String, start: Date) {
        current[occurrenceID] = nil
        acknowledged[occurrenceID] = start
    }
}
