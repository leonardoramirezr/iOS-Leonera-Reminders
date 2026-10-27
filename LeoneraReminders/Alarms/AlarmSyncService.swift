import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import Observation
import SwiftUI
import os

/// Mantiene una alarma de AlarmKit por cada recordatorio pendiente, a la hora en que debe sonar.
///
/// Cada alarma es de fecha fija (`.fixed`): las repeticiones (mensual, anual, cada N…) las calcula la app
/// y, al completar o posponer, se programa la siguiente alarma.
@MainActor
@Observable
final class AlarmSyncService {
    static let shared = AlarmSyncService()

    private(set) var authorizationState: AlarmManager.AuthorizationState
    /// Alarmas que están sonando ahora.
    private(set) var alertingAlarmIDs: Set<UUID> = []
    /// AlarmKit rechazó más alarmas; las más lejanas quedan sin programar hasta que se liberen.
    private(set) var limitReached = false
    private(set) var lastError: String?
    /// Permiso de notificaciones (sólo se usa en el modo que respeta el silencio).
    private(set) var notificationsAuthorized = true

    private let manager = AlarmManager.shared
    private let logger = Logger(subsystem: "LeoneraReminders", category: "alarms")
    @ObservationIgnored private var lastSync: Task<Void, Never>?
    @ObservationIgnored private var pendingRequest: Task<Void, Never>?
    @ObservationIgnored private var isObserving = false

    private init() {
        authorizationState = AlarmManager.shared.authorizationState
    }

    /// Empieza a observar permisos y alarmas, pide permiso la primera vez y sincroniza.
    func start() async {
        if !isObserving {
            isObserving = true
            Task {
                for await state in manager.authorizationUpdates {
                    if authorizationState != state { authorizationState = state }
                    if state == .authorized { requestSync() }
                }
            }
            Task {
                for await alarms in manager.alarmUpdates {
                    // Llega una actualización por cada alarma que se programa o cancela; asignar el mismo
                    // valor volvería a dibujar toda la lista a media animación.
                    let alerting = Set(alarms.filter { $0.state == .alerting }.map(\.id))
                    if alertingAlarmIDs != alerting { alertingAlarmIDs = alerting }
                }
            }
        }
        if manager.authorizationState == .notDetermined {
            await requestAuthorization()
        }
        await syncNow()
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            authorizationState = try await manager.requestAuthorization()
        } catch {
            logger.error("Permiso de alarmas: \(error.localizedDescription, privacy: .public)")
            authorizationState = manager.authorizationState
        }
        return authorizationState == .authorized
    }

    /// Sincroniza en breve, agrupando cambios seguidos.
    func requestSync() {
        pendingRequest?.cancel()
        pendingRequest = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    /// Sincroniza ya y espera a que termine (las sincronizaciones nunca corren en paralelo).
    func syncNow() async {
        let previous = lastSync
        let task = Task {
            await previous?.value
            await performSync()
        }
        lastSync = task
        await task.value
    }

    // MARK: - Sincronización

    private func performSync() async {
        let settings = SettingsStore.shared.settings
        if authorizationState != manager.authorizationState { authorizationState = manager.authorizationState }
        let eventAlarms = calendarEventAlarms(settings: settings, now: Date())
        if settings.ignoresSilentMode {
            NotificationDelivery.shared.removeAll()
            await syncAlarmKit(settings: settings, eventAlarms: eventAlarms)
        } else {
            // Modo que respeta el silencio: nada de AlarmKit, sólo notificaciones.
            if authorizationState == .authorized {
                for alarm in (try? manager.alarms) ?? [] { try? manager.cancel(id: alarm.id) }
            }
            await syncNotifications(settings: settings, eventAlarms: eventAlarms)
        }
    }

    /// Alarms 5 and 1 minutes before each event of the selected Apple Calendar calendars.
    ///
    /// They start an hour back so that an event alarm ringing right now is kept instead of cancelled;
    /// only the future ones are scheduled.
    private func calendarEventAlarms(settings: AppSettings, now: Date) -> [CalendarEventAlarm] {
        guard settings.calendarAlarms.isEnabled else { return [] }
        let from = now.addingTimeInterval(-60 * 60)
        let through = now.addingTimeInterval(TimeInterval(CalendarEventAlarmPlanner.lookAheadDays * 24 * 60 * 60))
        let maxLead = TimeInterval((CalendarEventAlarmPlanner.leadMinutes.max() ?? 0) * 60)
        let events = CalendarEventSource.shared.events(
            calendarIDs: settings.calendarAlarms.calendarIDs, from: from, to: through.addingTimeInterval(maxLead)
        )
        return CalendarEventAlarmPlanner.alarms(
            for: events, from: from, through: through, signature: "\(settings.alarmSignature)|\(Self.buttonsVersion)"
        )
    }

    /// Notificaciones locales: iOS permite 64 pendientes, así que se programan las más próximas.
    private func syncNotifications(settings: AppSettings, eventAlarms: [CalendarEventAlarm]) async {
        let delivery = NotificationDelivery.shared
        let authorized = await delivery.requestAuthorization()
        if notificationsAuthorized != authorized { notificationsAuthorized = authorized }
        guard notificationsAuthorized else { return }

        let store = ReminderStore.shared
        let now = Date()
        var items: [NotificationDelivery.Item] = []
        for reminder in store.reminders where !reminder.isCompleted {
            let signature = signature(for: reminder, settings: settings)
            for date in reminder.pendingAlarmDates(after: now.addingTimeInterval(1), followUp: settings.followUp) {
                items.append(.reminder(reminder, ScheduledAlarm(id: UUID(), fireDate: date, signature: signature)))
            }
        }
        for alarm in eventAlarms where alarm.fireDate > now.addingTimeInterval(1) {
            items.append(.calendarEvent(alarm))
        }
        items.sort { $0.fireDate < $1.fireDate }
        let overLimit = items.count > NotificationDelivery.maxPending
        if limitReached != overLimit { limitReached = overLimit }
        let scheduled = Array(items.prefix(NotificationDelivery.maxPending))
        await delivery.replaceAll(scheduled, settings: settings)

        var records: [UUID: [ScheduledAlarm]] = [:]
        for case let .reminder(reminder, record) in scheduled {
            records[reminder.id, default: []].append(record)
        }
        store.setScheduledAlarms(records)
        await delivery.removeDelivered(keeping: Set(store.reminders.filter { !$0.isCompleted }.map(\.id)))
    }

    private func syncAlarmKit(settings: AppSettings, eventAlarms: [CalendarEventAlarm]) async {
        guard authorizationState == .authorized else { return }

        let existing: [Alarm]
        do {
            existing = try manager.alarms
        } catch {
            lastError = error.localizedDescription
            logger.error("No se pudieron leer las alarmas: \(error.localizedDescription, privacy: .public)")
            return
        }
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let store = ReminderStore.shared
        let now = Date()

        var keep = Set<UUID>()
        var kept: [UUID: [ScheduledAlarm]] = [:]
        var missing: [MissingAlarm] = []
        for reminder in store.reminders where !reminder.isCompleted {
            let signature = signature(for: reminder, settings: settings)
            let wanted = reminder.pendingAlarmDates(after: now.addingTimeInterval(1), followUp: settings.followUp)
            var current: [ScheduledAlarm] = []
            for record in reminder.scheduledAlarms {
                guard let alarm = existingByID[record.id] else { continue }
                let stillWanted = wanted.contains(record.fireDate) && record.signature == signature
                // Si está sonando y el recordatorio no ha cambiado de hora, se deja sonar.
                let ringing = alarm.state == .alerting && reminder.dueDate <= now
                if stillWanted || ringing {
                    keep.insert(record.id)
                    current.append(record)
                }
            }
            kept[reminder.id] = current
            let scheduledDates = Set(current.map(\.fireDate))
            for date in wanted where !scheduledDates.contains(date) {
                missing.append(.reminder(reminder, date: date, isMain: date == reminder.dueDate))
            }
        }
        // Event alarms have a stable ID, so an existing alarm with that ID is already the right one.
        for alarm in eventAlarms {
            if existingByID[alarm.id] != nil {
                keep.insert(alarm.id)
            } else if alarm.fireDate > now.addingTimeInterval(1) {
                missing.append(.calendarEvent(alarm))
            }
        }

        // Primero se quitan las que sobran, para no chocar con el límite de alarmas.
        for alarm in existing where !keep.contains(alarm.id) {
            try? manager.cancel(id: alarm.id)
        }

        // Si AlarmKit llega a su límite, quedan programadas primero las alarmas principales (también las de
        // eventos del calendario) y luego las repeticiones, en orden de fecha.
        missing.sort { ($0.isMain ? 0 : 1, $0.date) < ($1.isMain ? 0 : 1, $1.date) }
        var reachedLimit = false
        var syncError: String?
        for item in missing where !reachedLimit {
            do {
                switch item {
                case let .reminder(reminder, date, _):
                    let alarmID = UUID()
                    let configuration = Self.configuration(for: reminder, at: date, alarmID: alarmID, settings: settings)
                    _ = try await manager.schedule(id: alarmID, configuration: configuration)
                    let record = ScheduledAlarm(id: alarmID, fireDate: date, signature: signature(for: reminder, settings: settings))
                    kept[reminder.id, default: []].append(record)
                case let .calendarEvent(alarm):
                    _ = try await manager.schedule(id: alarm.id, configuration: Self.configuration(for: alarm, settings: settings))
                }
            } catch AlarmManager.AlarmError.maximumLimitReached {
                reachedLimit = true
            } catch {
                syncError = error.localizedDescription
                logger.error("No se pudo programar «\(item.title, privacy: .private)»: \(error.localizedDescription, privacy: .public)")
            }
        }
        store.setScheduledAlarms(kept.mapValues { records in records.sorted { $0.fireDate < $1.fireDate } })
        if lastError != syncError { lastError = syncError }
        if limitReached != reachedLimit { limitReached = reachedLimit }
    }

    /// An alarm that still has to be scheduled with AlarmKit.
    private enum MissingAlarm {
        case reminder(Reminder, date: Date, isMain: Bool)
        case calendarEvent(CalendarEventAlarm)

        var date: Date {
            switch self {
            case let .reminder(_, date, _): date
            case let .calendarEvent(alarm): alarm.fireDate
            }
        }

        var isMain: Bool {
            switch self {
            case let .reminder(_, _, isMain): isMain
            case .calendarEvent: true
            }
        }

        var title: String {
            switch self {
            case let .reminder(reminder, _, _): reminder.title
            case let .calendarEvent(alarm): alarm.alarmTitle
            }
        }
    }

    /// Sube cuando cambia el texto o el ícono de los botones, para reprogramar las alarmas ya creadas.
    private static let buttonsVersion = 2

    private func signature(for reminder: Reminder, settings: AppSettings) -> String {
        "\(reminder.title)|\(settings.alarmSignature)|\(Self.buttonsVersion)"
    }

    // MARK: - Configuración de la alarma

    nonisolated private static func configuration(
        for reminder: Reminder,
        at date: Date,
        alarmID: UUID,
        settings: AppSettings
    ) -> AlarmManager.AlarmConfiguration<ReminderAlarmMetadata> {
        let title = LocalizedStringResource(stringLiteral: reminder.title)
        let secondaryButton = button(for: settings.secondaryAction, settings: settings)
        let secondaryBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior? = secondaryButton == nil ? nil : .custom

        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            // Desde iOS 26.1 el control de detener lo dibuja el sistema; su acción es `stopIntent`.
            alert = AlarmPresentation.Alert(
                title: title,
                secondaryButton: secondaryButton,
                secondaryButtonBehavior: secondaryBehavior
            )
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: button(for: settings.stopAction, settings: settings)
                    ?? AlarmButton(text: "Detener", textColor: .white, systemImageName: "stop.circle"),
                secondaryButton: secondaryButton,
                secondaryButtonBehavior: secondaryBehavior
            )
        }

        let attributes = AlarmAttributes<ReminderAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: ReminderAlarmMetadata(reminderID: reminder.id),
            tintColor: .brand
        )

        return AlarmManager.AlarmConfiguration<ReminderAlarmMetadata>.alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: intent(for: settings.stopAction, reminderID: reminder.id, alarmID: alarmID),
            secondaryIntent: secondaryButton == nil
                ? nil
                : intent(for: settings.secondaryAction, reminderID: reminder.id, alarmID: alarmID),
            sound: settings.sound.fileName.map { AlertConfiguration.AlertSound.named($0) } ?? .default
        )
    }

    /// The alarm of a calendar event: only a stop button, since there is nothing to snooze, and no intents.
    nonisolated private static func configuration(
        for alarm: CalendarEventAlarm,
        settings: AppSettings
    ) -> AlarmManager.AlarmConfiguration<CalendarEventAlarmMetadata> {
        let title = LocalizedStringResource(stringLiteral: alarm.alarmTitle)
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title, secondaryButton: nil, secondaryButtonBehavior: nil)
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(text: "Detener", textColor: .white, systemImageName: "stop.circle"),
                secondaryButton: nil,
                secondaryButtonBehavior: nil
            )
        }
        let attributes = AlarmAttributes<CalendarEventAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: CalendarEventAlarmMetadata(eventTitle: alarm.eventTitle, eventStart: alarm.eventStart),
            tintColor: .brand
        )
        return AlarmManager.AlarmConfiguration<CalendarEventAlarmMetadata>.alarm(
            schedule: .fixed(alarm.fireDate),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: settings.sound.fileName.map { AlertConfiguration.AlertSound.named($0) } ?? .default
        )
    }

    nonisolated private static func button(for action: AlarmAction, settings: AppSettings) -> AlarmButton? {
        switch action {
        case .snooze:
            return AlarmButton(
                text: LocalizedStringResource(stringLiteral: "Posponer \(settings.defaultSnooze.shortLabel)"),
                textColor: .white,
                systemImageName: "zzz"
            )
        case .snoozeOptions:
            return AlarmButton(text: "Abrir app", textColor: .white, systemImageName: "arrow.up.forward.app")
        case .none:
            return nil
        }
    }

    nonisolated private static func intent(for action: AlarmAction, reminderID: UUID, alarmID: UUID) -> (any LiveActivityIntent)? {
        switch action {
        case .snooze: return SnoozeReminderIntent(reminderID: reminderID, alarmID: alarmID)
        case .snoozeOptions: return SnoozeOptionsIntent(reminderID: reminderID, alarmID: alarmID)
        case .none: return nil
        }
    }
}

extension Color {
    /// Color de la app (también tiñe las alarmas, que no pueden usar el AccentColor del catálogo).
    static let brand = Color(red: 0.95, green: 0.38, blue: 0.20)
}
