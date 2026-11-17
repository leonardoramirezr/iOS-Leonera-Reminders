import AlarmKit
import AppIntents
import Foundation

/// The stop button of an event alarm. AlarmKit runs it in the app when the alarm is stopped; the repeat that
/// follows rings a minute later, until the event is acknowledged.
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
        if let id = UUID(uuidString: alarmID) { try? AlarmManager.shared.stop(id: id) }
        await CalendarEventRingHandler.stopped(alarmID: alarmID)
        return .result()
    }
}

/// «Abrir app» on an alarm of an event: stops it like the stop button (so its repeat still rings a minute later
/// until the event is acknowledged) and opens the app on the event's details, where it can be acknowledged.
/// The first alarm at the start of an acknowledged event has no such button; its repeats do.
struct CalendarEventOpenAppIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Abrir app"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Alarma")
    var alarmID: String

    init() {
        alarmID = ""
    }

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try? AlarmManager.shared.stop(id: id) }
        await CalendarEventRingHandler.openApp(alarmID: alarmID)
        return .result()
    }
}

@MainActor
enum CalendarEventRingHandler {
    /// The user asked to open the app from the alarm (or notification) `alarmID` before an event: the alarm counts as
    /// stopped, and the list shows the event's details once the app is in front.
    static func openApp(alarmID: String) async {
        guard let id = UUID(uuidString: alarmID),
              let occurrenceID = CalendarEventRingStore.shared.rings.current.first(where: { $0.value.id == id })?.key
        else { return }
        await stopped(alarmID: alarmID)
        AlarmSyncService.shared.pendingOpenedEventID = occurrenceID
    }

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
