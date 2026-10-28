import Foundation
import Testing
@testable import ReminderCore

struct CalendarEventRingsTests {
    private let event = CalendarEventSnapshot(eventID: "a", title: "Junta", startDate: local(2026, 10, 27, 10))
    private var occurrence: String { SyncedCalendarEvent.id(for: event) }

    /// The first alarms the sync plans for `event` at `now`.
    private func planned(at now: Date, leadMinutes: Int = 5) -> [CalendarEventAlarm] {
        CalendarEventAlarmPlanner.alarms(
            for: [event],
            from: now.addingTimeInterval(1),
            through: now.addingTimeInterval(7 * 24 * 60 * 60),
            signature: "s",
            leadMinutes: leadMinutes
        )
    }

    /// Runs a sync at `now` over the event; `scheduled` is what the system still holds, `nil` when unknown.
    private func sync(
        _ rings: inout CalendarEventRings,
        at now: Date,
        scheduled: Set<UUID>? = Set(),
        leadMinutes: Int = 5
    ) {
        rings.reconcile(planned: planned(at: now, leadMinutes: leadMinutes), events: [event], scheduled: scheduled, now: now)
    }

    @Test func aStoppedAlarmRepeatsAMinuteLaterUntilAcknowledged() throws {
        var rings = CalendarEventRings()
        sync(&rings, at: local(2026, 10, 27, 9, 50))
        let first = try #require(rings.current[occurrence])
        #expect(first.fireDate == local(2026, 10, 27, 9, 55))
        #expect(!first.isRepeat)

        let firstStop = local(2026, 10, 27, 9, 55).addingTimeInterval(20)
        rings.stopped(first.id, now: firstStop)
        let second = try #require(rings.current[occurrence])
        #expect(second.ringIndex == 1)
        #expect(second.fireDate == firstStop.addingTimeInterval(60))

        rings.stopped(second.id, now: second.fireDate.addingTimeInterval(5))
        #expect(rings.current[occurrence]?.ringIndex == 2)

        rings.acknowledge(occurrence, start: event.startDate)
        #expect(rings.current[occurrence] == nil)
    }

    @Test func stoppingAnAlarmTwiceOnlyMovesTheChainOnce() throws {
        var rings = CalendarEventRings()
        sync(&rings, at: local(2026, 10, 27, 9, 50))
        let first = try #require(rings.current[occurrence])
        let now = local(2026, 10, 27, 9, 55, 20)
        rings.stopped(first.id, now: now)
        let repeated = rings.current[occurrence]
        rings.stopped(first.id, now: now.addingTimeInterval(1))
        #expect(rings.current[occurrence] == repeated)
    }

    @Test func aRepeatIsPlannedAtTheNextSyncWhenTheSystemLostTheAlarm() throws {
        var rings = CalendarEventRings()
        sync(&rings, at: local(2026, 10, 27, 9, 50))
        // The alarm rang and was stopped without the app hearing about it: the system no longer holds it.
        sync(&rings, at: local(2026, 10, 27, 9, 56))
        let repeated = try #require(rings.current[occurrence])
        #expect(repeated.ringIndex == 1)
        #expect(repeated.fireDate == local(2026, 10, 27, 9, 57))
    }

    @Test func aRingingAlarmIsKeptWhileTheSystemHoldsIt() throws {
        var rings = CalendarEventRings()
        sync(&rings, at: local(2026, 10, 27, 9, 50))
        let ringing = try #require(rings.current[occurrence])
        sync(&rings, at: local(2026, 10, 27, 9, 55, 10), scheduled: [ringing.id])
        #expect(rings.current[occurrence] == ringing)
    }

    @Test func withoutKnowingTheSystemAlarmsNothingMovesOnItsOwn() throws {
        var rings = CalendarEventRings()
        sync(&rings, at: local(2026, 10, 27, 9, 50))
        let first = try #require(rings.current[occurrence])
        sync(&rings, at: local(2026, 10, 27, 9, 57), scheduled: nil)
        #expect(rings.current[occurrence] == first)
    }

    @Test func anAcknowledgedEventDoesNotRingAgain() {
        var rings = CalendarEventRings()
        sync(&rings, at: local(2026, 10, 27, 9, 50))
        rings.acknowledge(occurrence, start: event.startDate)
        sync(&rings, at: local(2026, 10, 27, 9, 51))
        #expect(rings.current[occurrence] == nil)
    }

    @Test func anEventNoLongerInTheCalendarDropsItsAlarm() {
        var rings = CalendarEventRings()
        sync(&rings, at: local(2026, 10, 27, 9, 50))
        rings.reconcile(planned: [], events: [], scheduled: Set(), now: local(2026, 10, 27, 9, 51))
        #expect(rings.current.isEmpty)
    }

    @Test func aChangedLeadTimeReplacesAnAlarmThatHasNotRungYet() {
        var rings = CalendarEventRings()
        sync(&rings, at: local(2026, 10, 27, 9, 0), leadMinutes: 5)
        sync(&rings, at: local(2026, 10, 27, 9, 0), leadMinutes: 15)
        #expect(rings.current[occurrence]?.fireDate == local(2026, 10, 27, 9, 45))
        #expect(rings.current[occurrence]?.leadMinutes == 15)
    }

    @Test func aRepeatIsNotReplacedByThePlannedFirstAlarm() throws {
        var rings = CalendarEventRings()
        sync(&rings, at: local(2026, 10, 27, 9, 50))
        let first = try #require(rings.current[occurrence])
        rings.stopped(first.id, now: local(2026, 10, 27, 9, 55, 20))
        let repeated = try #require(rings.current[occurrence])
        rings.reconcile(
            planned: planned(at: local(2026, 10, 27, 9, 50)),
            events: [event],
            scheduled: nil,
            now: local(2026, 10, 27, 9, 56, 30)
        )
        #expect(rings.current[occurrence] == repeated)
    }

    @Test func ringsSurviveAJSONRoundTrip() throws {
        var rings = CalendarEventRings()
        sync(&rings, at: local(2026, 10, 27, 9, 50))
        rings.acknowledge("other|1", start: local(2026, 10, 27, 12))
        let decoded = try JSONDecoder().decode(CalendarEventRings.self, from: JSONEncoder().encode(rings))
        #expect(decoded == rings)
    }
}
