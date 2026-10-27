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
    /// `EKCalendar.calendarIdentifier` of the calendar the event belongs to.
    var calendarID: String
    var endDate: Date?
    var location: String?
    var notes: String?

    init(
        eventID: String,
        title: String,
        startDate: Date,
        isAllDay: Bool = false,
        isSkipped: Bool = false,
        calendarID: String = "",
        endDate: Date? = nil,
        location: String? = nil,
        notes: String? = nil
    ) {
        self.eventID = eventID
        self.title = title
        self.startDate = startDate
        self.isAllDay = isAllDay
        self.isSkipped = isSkipped
        self.calendarID = calendarID
        self.endDate = endDate
        self.location = location
        self.notes = notes
    }
}

/// One alarm that rings some minutes before a calendar event.
struct CalendarEventAlarm: Identifiable, Hashable, Sendable {
    /// Stable for the same event occurrence, lead time and signature (see `UUID(stableFrom:)`).
    var id: UUID
    /// The event as it was read in the sync that produced this alarm.
    var event: CalendarEventSnapshot
    var leadMinutes: Int
    var fireDate: Date

    var eventTitle: String { event.title }
    var eventStart: Date { event.startDate }

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
                alarms.append(CalendarEventAlarm(id: id, event: event, leadMinutes: lead, fireDate: fireDate))
            }
        }
        return alarms.sorted { ($0.fireDate, $0.id.uuidString) < ($1.fireDate, $1.id.uuidString) }
    }

    /// The events behind `scheduled` alarms, one per occurrence, sorted by start.
    ///
    /// An event is listed while at least one of its alarms is still ahead or is ringing (`alerting`), so it
    /// leaves the list on its own once its last alarm has rung.
    static func syncedEvents(
        from scheduled: [CalendarEventAlarm],
        now: Date,
        alerting: Set<UUID> = []
    ) -> [SyncedCalendarEvent] {
        let groups = Dictionary(grouping: scheduled) { SyncedCalendarEvent.id(for: $0.event) }
        return groups.values.compactMap { alarms -> SyncedCalendarEvent? in
            guard let first = alarms.first,
                  alarms.contains(where: { $0.fireDate > now || alerting.contains($0.id) })
            else { return nil }
            return SyncedCalendarEvent(event: first.event, alarms: alarms.sorted { $0.fireDate < $1.fireDate })
        }
        .sorted { ($0.event.startDate, $0.id) < ($1.event.startDate, $1.id) }
    }
}

/// A calendar event that already has its alarms scheduled, as shown in the reminder list.
struct SyncedCalendarEvent: Identifiable, Hashable, Sendable {
    var event: CalendarEventSnapshot
    /// Sorted by fire date.
    var alarms: [CalendarEventAlarm]

    var id: String { Self.id(for: event) }

    static func id(for event: CalendarEventSnapshot) -> String {
        "\(event.eventID)|\(Int(event.startDate.timeIntervalSince1970))"
    }
}
