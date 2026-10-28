import Foundation

/// Calendars of the Apple Calendar app whose events ring an alarm before they start.
struct CalendarAlarmSettings: Codable, Hashable, Sendable {
    /// `EKCalendar.calendarIdentifier` of each selected calendar; empty means the feature is off.
    var calendarIDs: [String]
    /// Minutes before the start of an event at which its first alarm rings (one of `leadMinuteOptions`).
    var leadMinutes: Int

    static let leadMinuteOptions = [1, 5, 10, 15]
    static let defaultLeadMinutes = 5
    static let `default` = CalendarAlarmSettings(calendarIDs: [], leadMinutes: defaultLeadMinutes)

    var isEnabled: Bool { !calendarIDs.isEmpty }
}

extension CalendarAlarmSettings {
    private enum CodingKeys: String, CodingKey {
        case calendarIDs, leadMinutes
    }

    /// Settings saved before the lead time could be chosen keep the default.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            calendarIDs: try c.decodeIfPresent([String].self, forKey: .calendarIDs) ?? [],
            leadMinutes: try c.decodeIfPresent(Int.self, forKey: .leadMinutes) ?? Self.defaultLeadMinutes
        )
    }
}

/// An event read from the Apple Calendar app, without any EventKit type so it can be tested anywhere.
struct CalendarEventSnapshot: Hashable, Codable, Sendable {
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

/// One alarm of a calendar event: the first one rings `leadMinutes` before it starts, and each repeat rings
/// after the previous alarm is stopped, until the event is acknowledged (see `CalendarEventRings`).
struct CalendarEventAlarm: Identifiable, Hashable, Codable, Sendable {
    /// Stable for the first alarm of an occurrence, lead time and signature (see `UUID(stableFrom:)`); a repeat
    /// gets a random one.
    var id: UUID
    /// The event as it was read in the sync that produced this alarm.
    var event: CalendarEventSnapshot
    var leadMinutes: Int
    var fireDate: Date
    /// 0 for the alarm before the event, then 1, 2… for the repeats.
    var ringIndex = 0

    var eventTitle: String { event.title }
    var eventStart: Date { event.startDate }
    /// The occurrence the alarm belongs to (see `SyncedCalendarEvent.id`).
    var occurrenceID: String { SyncedCalendarEvent.id(for: event) }
    var isRepeat: Bool { ringIndex > 0 }

    /// The repeat that rings at `date`, once this alarm has been stopped.
    func repeated(at date: Date) -> CalendarEventAlarm {
        CalendarEventAlarm(id: UUID(), event: event, leadMinutes: leadMinutes, fireDate: date, ringIndex: ringIndex + 1)
    }

    /// Text shown by the alarm, e.g. "Junta · en 5 min", or "Junta · sin confirmar" for a repeat.
    var alarmTitle: String {
        let title = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.isEmpty ? "Evento" : title
        return isRepeat ? "\(name) · sin confirmar" : "\(name) · en \(leadMinutes) min"
    }
}

enum CalendarEventAlarmPlanner {
    /// How far ahead event alarms are scheduled.
    static let lookAheadDays = 7

    /// The first alarm of each event in `events` whose fire date falls in `from...through`, sorted by fire date.
    ///
    /// All-day and skipped events are left out. `signature` changes when anything the alarm shows or does
    /// changes, so that the alarm gets a new identity and is scheduled again.
    static func alarms(
        for events: [CalendarEventSnapshot],
        from start: Date,
        through end: Date,
        signature: String,
        leadMinutes: Int = CalendarAlarmSettings.defaultLeadMinutes
    ) -> [CalendarEventAlarm] {
        var seen = Set<UUID>()
        var alarms: [CalendarEventAlarm] = []
        for event in events where !event.isAllDay && !event.isSkipped {
            let fireDate = event.startDate.addingTimeInterval(-TimeInterval(leadMinutes * 60))
            guard fireDate >= start, fireDate <= end else { continue }
            let key = "\(event.eventID)|\(Int(event.startDate.timeIntervalSince1970))|\(leadMinutes)|\(event.title)|\(signature)"
            let id = UUID(stableFrom: key)
            guard seen.insert(id).inserted else { continue }
            alarms.append(CalendarEventAlarm(id: id, event: event, leadMinutes: leadMinutes, fireDate: fireDate))
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
