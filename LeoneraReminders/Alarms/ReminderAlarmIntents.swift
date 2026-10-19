import AlarmKit
import AppIntents
import Foundation

// Acciones de los botones de la alarma. AlarmKit las ejecuta en el proceso de la app
// (abriéndola en segundo plano si hace falta) cuando se toca el botón correspondiente.

struct SnoozeReminderIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Posponer recordatorio"
    static let isDiscoverable = false

    @Parameter(title: "Recordatorio")
    var reminderID: String

    @Parameter(title: "Alarma")
    var alarmID: String

    init() {
        reminderID = ""
        alarmID = ""
    }

    init(reminderID: UUID, alarmID: UUID) {
        self.reminderID = reminderID.uuidString
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        await AlarmActionHandler.perform(.snooze, reminderID: reminderID, alarmID: alarmID)
        return .result()
    }
}

/// «Abrir app»: pospone con el tiempo por defecto (para que no se pierda) y abre la app para completar deslizando
/// o elegir otro tiempo.
struct SnoozeOptionsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Abrir app"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Recordatorio")
    var reminderID: String

    @Parameter(title: "Alarma")
    var alarmID: String

    init() {
        reminderID = ""
        alarmID = ""
    }

    init(reminderID: UUID, alarmID: UUID) {
        self.reminderID = reminderID.uuidString
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        await AlarmActionHandler.perform(.snoozeOptions, reminderID: reminderID, alarmID: alarmID)
        return .result()
    }
}

@MainActor
enum AlarmActionHandler {
    /// Lo que hace «Detener» (o descartar la notificación), según la configuración.
    static func performStopAction(reminderID: String, alarmID: String) async {
        await perform(SettingsStore.shared.settings.stopAction, reminderID: reminderID, alarmID: alarmID)
    }

    static func perform(_ action: AlarmAction, reminderID: String, alarmID: String) async {
        // «Abrir app» vibra al mostrar la hoja, ya con la app al frente (ver `ReminderListView`).
        if action != .snoozeOptions { Haptics.success() }
        let alarm = UUID(uuidString: alarmID)
        if let alarm { try? AlarmManager.shared.stop(id: alarm) }

        let store = ReminderStore.shared
        guard let id = UUID(uuidString: reminderID), let reminder = store.reminder(id: id) else {
            // El recordatorio ya no existe: sólo se quita la alarma.
            if let alarm { try? AlarmManager.shared.cancel(id: alarm) }
            return
        }
        guard !reminder.isCompleted else { return }
        // Una alarma vieja (el recordatorio ya se atendió desde la app) no debe cambiarlo otra vez.
        if let alarm, !reminder.scheduledAlarms.contains(where: { $0.id == alarm }), reminder.dueDate > Date() {
            return
        }

        let snooze = SettingsStore.shared.settings.defaultSnooze
        switch action {
        case .snooze:
            store.snooze(id: id, by: snooze, undoable: false)
        case .snoozeOptions:
            store.snooze(id: id, by: snooze, undoable: false)
            store.pendingOptionsReminderID = id
        case .none:
            break
        }
        await AlarmSyncService.shared.syncNow()
    }
}
