import Foundation

/// Calendars of the Apple Calendar app whose events ring an alarm before they start.
struct CalendarAlarmSettings: Codable, Hashable, Sendable {
    /// `EKCalendar.calendarIdentifier` of each selected calendar; empty means the feature is off.
    var calendarIDs: [String]

    static let `default` = CalendarAlarmSettings(calendarIDs: [])

    var isEnabled: Bool { !calendarIDs.isEmpty }
}

/// An event read from the Apple Calendar app, without any EventKit type so it can be tested anywhere.
struct CalendarEventSnapshot: Hashable, Sendable {
    /// `EKEvent.calendarItemIdentifier`; every occurrence of a recurring event shares it.
    var eventID: String
    var title: String
    var startDate: Date
    var isAllDay: Bool
    /// Canceled, or declined by the user: it does not ring.
    var isSkipped: Bool

    init(eventID: String, title: String, startDate: Date, isAllDay: Bool = false, isSkipped: Bool = false) {
        self.eventID = eventID
        self.title = title
        self.startDate = startDate
        self.isAllDay = isAllDay
        self.isSkipped = isSkipped
    }
}

/// One alarm that rings some minutes before a calendar event.
struct CalendarEventAlarm: Identifiable, Hashable, Sendable {
    /// Stable for the same event occurrence, lead time and signature (see `UUID(stableFrom:)`).
    var id: UUID
    var eventTitle: String
    var eventStart: Date
    var leadMinutes: Int
    var fireDate: Date

    /// Text shown by the alarm, e.g. "Junta · en 5 min".
    var alarmTitle: String {
        let title = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(title.isEmpty ? "Evento" : title) · en \(leadMinutes) min"
    }
}

enum CalendarEventAlarmPlanner {
    /// Minutes before the start of each event at which an alarm rings.
    static let leadMinutes = [5, 1]
    /// How far ahead event alarms are scheduled.
    static let lookAheadDays = 7

    /// The alarms of `events` whose fire date falls in `from...through`, sorted by fire date.
    ///
    /// All-day and skipped events are left out. `signature` changes when anything the alarm shows or does
    /// changes, so that the alarm gets a new identity and is scheduled again.
    static func alarms(
        for events: [CalendarEventSnapshot],
        from start: Date,
        through end: Date,
        signature: String,
        leadMinutes: [Int] = leadMinutes
    ) -> [CalendarEventAlarm] {
        var seen = Set<UUID>()
        var alarms: [CalendarEventAlarm] = []
        for event in events where !event.isAllDay && !event.isSkipped {
            for lead in leadMinutes {
                let fireDate = event.startDate.addingTimeInterval(-TimeInterval(lead * 60))
                guard fireDate >= start, fireDate <= end else { continue }
                let key = "\(event.eventID)|\(Int(event.startDate.timeIntervalSince1970))|\(lead)|\(event.title)|\(signature)"
                let id = UUID(stableFrom: key)
                guard seen.insert(id).inserted else { continue }
                alarms.append(CalendarEventAlarm(
                    id: id, eventTitle: event.title, eventStart: event.startDate, leadMinutes: lead, fireDate: fireDate
                ))
            }
        }
        return alarms.sorted { ($0.fireDate, $0.id.uuidString) < ($1.fireDate, $1.id.uuidString) }
    }
}
