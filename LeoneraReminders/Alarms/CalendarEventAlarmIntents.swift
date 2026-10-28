import AlarmKit
import AppIntents
import Foundation

/// The stop button of an event alarm. AlarmKit runs it in the app when the alarm is stopped; the repeat that
/// follows rings a minute later, unless the event has been acknowledged.
struct CalendarEventRingStopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Detener alarma de evento"
    static let isDiscoverable = false

    @Parameter(title: "Alarma")
    var alarmID: String

    init() {
        alarmID = ""
    }

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        await CalendarEventRingHandler.stopped(alarmID: alarmID)
        return .result()
    }
}

@MainActor
enum CalendarEventRingHandler {
    /// An event alarm was stopped (or its notification cleared): its repeat is planned a minute from now.
    static func stopped(alarmID: String) async {
        guard let id = UUID(uuidString: alarmID) else { return }
        let ringStore = CalendarEventRingStore.shared
        var rings = ringStore.rings
        rings.stopped(id, now: Date())
        ringStore.rings = rings
        await AlarmSyncService.shared.syncNow()
    }
}
