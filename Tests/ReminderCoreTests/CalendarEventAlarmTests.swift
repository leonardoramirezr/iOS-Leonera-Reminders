import Foundation
import Testing
@testable import ReminderCore

struct CalendarEventAlarmTests {
    private let windowStart = local(2026, 10, 27, 8)
    private let windowEnd = local(2026, 11, 3, 8)

    @Test func eachEventRingsFiveAndOneMinuteBefore() {
        let event = CalendarEventSnapshot(eventID: "a", title: "Junta", startDate: local(2026, 10, 27, 10))
        let alarms = CalendarEventAlarmPlanner.alarms(for: [event], from: windowStart, through: windowEnd, signature: "s")
        #expect(alarms.map(\.fireDate) == [local(2026, 10, 27, 9, 55), local(2026, 10, 27, 9, 59)])
        #expect(alarms.map(\.leadMinutes) == [5, 1])
        #expect(alarms.map(\.alarmTitle) == ["Junta · en 5 min", "Junta · en 1 min"])
    }

    @Test func allDayAndSkippedEventsDoNotRing() {
        let events = [
            CalendarEventSnapshot(eventID: "a", title: "Vacaciones", startDate: local(2026, 10, 28), isAllDay: true),
            CalendarEventSnapshot(eventID: "b", title: "Cancelada", startDate: local(2026, 10, 28, 12), isSkipped: true),
        ]
        #expect(CalendarEventAlarmPlanner.alarms(for: events, from: windowStart, through: windowEnd, signature: "s").isEmpty)
    }

    @Test func onlyFireDatesInsideTheWindowAreKept() {
        let events = [
            // The 5-minute alarm already passed; only the 1-minute one is left.
            CalendarEventSnapshot(eventID: "a", title: "Ya casi", startDate: local(2026, 10, 27, 8, 3)),
            CalendarEventSnapshot(eventID: "b", title: "Muy lejos", startDate: local(2026, 11, 10, 9)),
        ]
        let alarms = CalendarEventAlarmPlanner.alarms(for: events, from: windowStart, through: windowEnd, signature: "s")
        #expect(alarms.map(\.fireDate) == [local(2026, 10, 27, 8, 2)])
    }

    @Test func duplicateEventsGetOneAlarmPerLeadTime() {
        let event = CalendarEventSnapshot(eventID: "a", title: "Junta", startDate: local(2026, 10, 27, 10))
        let alarms = CalendarEventAlarmPlanner.alarms(for: [event, event], from: windowStart, through: windowEnd, signature: "s")
        #expect(alarms.count == 2)
    }

    @Test func occurrencesOfARecurringEventAreDistinct() {
        let first = CalendarEventSnapshot(eventID: "a", title: "Diaria", startDate: local(2026, 10, 27, 10))
        var second = first
        second.startDate = local(2026, 10, 28, 10)
        let alarms = CalendarEventAlarmPlanner.alarms(for: [first, second], from: windowStart, through: windowEnd, signature: "s")
        #expect(Set(alarms.map(\.id)).count == 4)
    }

    @Test func alarmIDIsStableAndChangesWithTheEvent() {
        let event = CalendarEventSnapshot(eventID: "a", title: "Junta", startDate: local(2026, 10, 27, 10))
        let ids = { (event: CalendarEventSnapshot, signature: String) in
            CalendarEventAlarmPlanner.alarms(for: [event], from: windowStart, through: windowEnd, signature: signature).map(\.id)
        }
        #expect(ids(event, "s") == ids(event, "s"))

        var moved = event
        moved.startDate = local(2026, 10, 27, 11)
        #expect(Set(ids(moved, "s")).isDisjoint(with: ids(event, "s")))

        var renamed = event
        renamed.title = "Junta semanal"
        #expect(Set(ids(renamed, "s")).isDisjoint(with: ids(event, "s")))

        #expect(Set(ids(event, "other")).isDisjoint(with: ids(event, "s")))
    }

    @Test func stableUUIDIsDeterministicAndWellFormed() {
        let id = UUID(stableFrom: "event|123|5")
        #expect(id == UUID(stableFrom: "event|123|5"))
        #expect(id != UUID(stableFrom: "event|123|1"))
        let text = id.uuidString
        #expect(Array(text)[14] == "8")
        #expect("89AB".contains(Array(text)[19]))
    }

    @Test func untitledEventsUseAGenericTitle() {
        let event = CalendarEventSnapshot(eventID: "a", title: "  ", startDate: local(2026, 10, 27, 10))
        let alarms = CalendarEventAlarmPlanner.alarms(for: [event], from: windowStart, through: windowEnd, signature: "s")
        #expect(alarms.first?.alarmTitle == "Evento · en 5 min")
    }

    @Test func settingsWithoutCalendarAlarmsDecodeToTheDefault() throws {
        let data = Data(#"{"ignoresSilentMode": false}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.calendarAlarms == .default)
        #expect(!settings.calendarAlarms.isEnabled)
        #expect(!settings.ignoresSilentMode)
    }

    @Test func calendarAlarmSettingsRoundTrip() throws {
        var settings = AppSettings.default
        settings.calendarAlarms.calendarIDs = ["work", "home"]
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.calendarAlarms.calendarIDs == ["work", "home"])
    }
}
