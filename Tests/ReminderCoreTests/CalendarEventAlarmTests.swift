import Foundation
import Testing
@testable import ReminderCore

struct CalendarEventAlarmTests {
    private let windowStart = local(2026, 10, 27, 8)
    private let windowEnd = local(2026, 11, 3, 8)

    @Test func eachEventRingsTheChosenLeadTimeBeforeItStarts() {
        let event = CalendarEventSnapshot(eventID: "a", title: "Junta", startDate: local(2026, 10, 27, 10))
        let five = CalendarEventAlarmPlanner.alarms(for: [event], from: windowStart, through: windowEnd, signature: "s")
        #expect(five.map(\.fireDate) == [local(2026, 10, 27, 9, 55)])
        #expect(five.map(\.leadMinutes) == [5])
        #expect(five.map(\.alarmTitle) == ["Junta · en 5 min"])
        #expect(five.map(\.ringIndex) == [0])

        let fifteen = CalendarEventAlarmPlanner.alarms(
            for: [event], from: windowStart, through: windowEnd, signature: "s", leadMinutes: 15
        )
        #expect(fifteen.map(\.fireDate) == [local(2026, 10, 27, 9, 45)])
        #expect(fifteen.map(\.alarmTitle) == ["Junta · en 15 min"])
    }

    @Test func leadTimeOptionsAreOneFiveTenAndFifteenMinutes() {
        #expect(CalendarAlarmSettings.leadMinuteOptions == [1, 5, 10, 15])
        #expect(CalendarAlarmSettings.default.leadMinutes == 5)
    }

    @Test func repeatAlarmHasItsOwnIDAndSaysItIsUnconfirmed() {
        let event = CalendarEventSnapshot(eventID: "a", title: "Junta", startDate: local(2026, 10, 27, 10))
        let first = CalendarEventAlarmPlanner.alarms(for: [event], from: windowStart, through: windowEnd, signature: "s")[0]
        let repeated = first.repeated(at: local(2026, 10, 27, 9, 56))
        #expect(repeated.ringIndex == 1)
        #expect(repeated.isRepeat)
        #expect(repeated.id != first.id)
        #expect(repeated.occurrenceID == first.occurrenceID)
        #expect(repeated.alarmTitle == "Junta · sin confirmar")
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
            // Its alarm would have rung before the window started.
            CalendarEventSnapshot(eventID: "a", title: "Ya casi", startDate: local(2026, 10, 27, 8, 3)),
            CalendarEventSnapshot(eventID: "b", title: "Muy lejos", startDate: local(2026, 11, 10, 9)),
            CalendarEventSnapshot(eventID: "c", title: "Pronto", startDate: local(2026, 10, 27, 8, 6)),
        ]
        let alarms = CalendarEventAlarmPlanner.alarms(for: events, from: windowStart, through: windowEnd, signature: "s")
        #expect(alarms.map(\.event.title) == ["Pronto"])
        #expect(alarms.map(\.fireDate) == [local(2026, 10, 27, 8, 1)])
    }

    @Test func duplicateEventsGetOneAlarm() {
        let event = CalendarEventSnapshot(eventID: "a", title: "Junta", startDate: local(2026, 10, 27, 10))
        let alarms = CalendarEventAlarmPlanner.alarms(for: [event, event], from: windowStart, through: windowEnd, signature: "s")
        #expect(alarms.count == 1)
    }

    @Test func occurrencesOfARecurringEventAreDistinct() {
        let first = CalendarEventSnapshot(eventID: "a", title: "Diaria", startDate: local(2026, 10, 27, 10))
        var second = first
        second.startDate = local(2026, 10, 28, 10)
        let alarms = CalendarEventAlarmPlanner.alarms(for: [first, second], from: windowStart, through: windowEnd, signature: "s")
        #expect(Set(alarms.map(\.id)).count == 2)
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

    @Test func syncedEventsGroupTheAlarmsOfEachOccurrenceSortedByStart() {
        let later = CalendarEventSnapshot(eventID: "b", title: "Comida", startDate: local(2026, 10, 27, 14))
        let sooner = CalendarEventSnapshot(eventID: "a", title: "Junta", startDate: local(2026, 10, 27, 10))
        let alarms = CalendarEventAlarmPlanner.alarms(for: [later, sooner], from: windowStart, through: windowEnd, signature: "s")
        let synced = CalendarEventAlarmPlanner.syncedEvents(from: alarms, now: windowStart)
        #expect(synced.map(\.event.title) == ["Junta", "Comida"])
        #expect(synced.first?.alarms.map(\.leadMinutes) == [5])
    }

    @Test func syncedEventLeavesOnceItsAlarmHasPassedUnlessItIsRinging() {
        let event = CalendarEventSnapshot(eventID: "a", title: "Junta", startDate: local(2026, 10, 27, 10))
        let alarms = CalendarEventAlarmPlanner.alarms(for: [event], from: windowStart, through: windowEnd, signature: "s")
        #expect(CalendarEventAlarmPlanner.syncedEvents(from: alarms, now: local(2026, 10, 27, 9, 54)).count == 1)
        #expect(CalendarEventAlarmPlanner.syncedEvents(from: alarms, now: local(2026, 10, 27, 9, 56)).isEmpty)
        let ringing = Set(alarms.map(\.id))
        #expect(CalendarEventAlarmPlanner.syncedEvents(from: alarms, now: local(2026, 10, 27, 9, 56), alerting: ringing).count == 1)
    }

    @Test func syncedEventKeepsTheEventDetails() throws {
        let event = CalendarEventSnapshot(
            eventID: "a", title: "Junta", startDate: local(2026, 10, 27, 10),
            calendarID: "work", endDate: local(2026, 10, 27, 11), location: "Sala 2", notes: "Llevar laptop"
        )
        let alarms = CalendarEventAlarmPlanner.alarms(for: [event], from: windowStart, through: windowEnd, signature: "s")
        let synced = try #require(CalendarEventAlarmPlanner.syncedEvents(from: alarms, now: windowStart).first)
        #expect(synced.event == event)
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
        settings.calendarAlarms.leadMinutes = 15
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.calendarAlarms.calendarIDs == ["work", "home"])
        #expect(decoded.calendarAlarms.leadMinutes == 15)
    }

    @Test func calendarSettingsSavedBeforeTheLeadTimeKeepTheirCalendarsAndUseTheDefault() throws {
        let data = Data(#"{"calendarIDs": ["work"]}"#.utf8)
        let settings = try JSONDecoder().decode(CalendarAlarmSettings.self, from: data)
        #expect(settings.calendarIDs == ["work"])
        #expect(settings.leadMinutes == CalendarAlarmSettings.defaultLeadMinutes)
    }
}
