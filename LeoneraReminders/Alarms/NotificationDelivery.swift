import Foundation
import UserNotifications

/// Entrega de recordatorios con notificaciones locales, para cuando se quiere respetar el modo silencio
/// (las alarmas de AlarmKit siempre suenan). Los botones hacen lo mismo que los de la alarma.
@MainActor
final class NotificationDelivery: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelivery()
    /// iOS sólo conserva 64 notificaciones pendientes por app.
    static let maxPending = 64

    nonisolated private static let categoryID = "reminder"
    nonisolated private static let calendarEventCategoryID = "calendarEvent"
    nonisolated private static let snoozeActionID = "snooze"
    nonisolated private static let optionsActionID = "options"
    nonisolated private static let reminderKey = "reminderID"
    nonisolated private static let alarmKey = "alarmID"
    nonisolated private static let calendarEventKey = "calendarEvent"

    /// A pending notification: a reminder alarm or the alarm before a calendar event.
    enum Item {
        case reminder(Reminder, ScheduledAlarm)
        case calendarEvent(CalendarEventAlarm)

        var fireDate: Date {
            switch self {
            case let .reminder(_, record): record.fireDate
            case let .calendarEvent(alarm): alarm.fireDate
            }
        }
    }

    private let center = UNUserNotificationCenter.current()

    /// Debe llamarse al arrancar para recibir las respuestas a las notificaciones.
    func configure() {
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Reemplaza todas las notificaciones pendientes por `items`.
    func replaceAll(_ items: [Item], settings: AppSettings) async {
        registerCategory(settings: settings)
        center.removeAllPendingNotificationRequests()
        let calendar = Calendar.current
        for item in items {
            let content = UNMutableNotificationContent()
            let identifier: String
            switch item {
            case let .reminder(reminder, record):
                identifier = record.id.uuidString
                content.title = reminder.title
                content.body = record.fireDate == reminder.dueDate ? "Recordatorio" : "Sigue pendiente"
                content.categoryIdentifier = Self.categoryID
                content.userInfo = [
                    Self.reminderKey: reminder.id.uuidString,
                    Self.alarmKey: record.id.uuidString,
                ]
            case let .calendarEvent(alarm):
                identifier = alarm.id.uuidString
                content.title = alarm.eventTitle.isEmpty ? "Evento" : alarm.eventTitle
                content.body = alarm.isRepeat ? "Sin confirmar" : "Empieza en \(alarm.leadMinutes) min"
                content.categoryIdentifier = Self.calendarEventCategoryID
                content.userInfo = [Self.calendarEventKey: true, Self.alarmKey: alarm.id.uuidString]
            }
            content.sound = Self.sound(for: settings.sound)
            content.interruptionLevel = .active
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func removeAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    /// Takes the delivered notification of a calendar event off the Notification Center, once it is acknowledged.
    func removeDeliveredCalendarEvent(_ alarmID: UUID) {
        center.removeDeliveredNotifications(withIdentifiers: [alarmID.uuidString])
    }

    /// Quita del Centro de notificaciones las de recordatorios que ya no están pendientes.
    func removeDelivered(keeping pending: Set<UUID>) async {
        let stale = await center.deliveredNotifications().compactMap { notification -> String? in
            // Calendar event notifications have no reminder: they stay until the user clears them.
            if notification.request.content.userInfo[Self.calendarEventKey] != nil { return nil }
            let id = (notification.request.content.userInfo[Self.reminderKey] as? String).flatMap(UUID.init(uuidString:))
            return id.map(pending.contains) == true ? nil : notification.request.identifier
        }
        if !stale.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: stale)
        }
    }

    private func registerCategory(settings: AppSettings) {
        var actions: [UNNotificationAction] = []
        switch settings.secondaryAction {
        case .snooze:
            actions.append(UNNotificationAction(identifier: Self.snoozeActionID, title: "Posponer \(settings.defaultSnooze.shortLabel)"))
        case .snoozeOptions:
            actions.append(UNNotificationAction(identifier: Self.optionsActionID, title: "Abrir app", options: [.foreground]))
        case .none:
            break
        }
        if settings.secondaryAction != .snooze {
            actions.append(UNNotificationAction(identifier: Self.snoozeActionID, title: "Posponer \(settings.defaultSnooze.shortLabel)"))
        }
        let category = UNNotificationCategory(
            identifier: Self.categoryID, actions: actions, intentIdentifiers: [], options: [.customDismissAction]
        )
        // Clearing the notification of an event counts as stopping its alarm, which plans the next repeat.
        let calendarEventCategory = UNNotificationCategory(
            identifier: Self.calendarEventCategoryID, actions: [], intentIdentifiers: [], options: [.customDismissAction]
        )
        center.setNotificationCategories([category, calendarEventCategory])
    }

    private static func sound(for sound: AlarmSound) -> UNNotificationSound? {
        switch sound {
        case .system: .default
        case .silent: nil
        default: sound.fileName.map { UNNotificationSound(named: UNNotificationSoundName(rawValue: $0)) }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        // A calendar event notification has no reminder actions: clearing it stops the alarm, anything else opens the app.
        if info[Self.calendarEventKey] != nil {
            guard response.actionIdentifier == UNNotificationDismissActionIdentifier,
                  let alarmID = info[Self.alarmKey] as? String
            else { return }
            await CalendarEventRingHandler.stopped(alarmID: alarmID)
            return
        }
        let reminderID = info[Self.reminderKey] as? String ?? ""
        let alarmID = info[Self.alarmKey] as? String ?? ""
        switch response.actionIdentifier {
        case Self.snoozeActionID:
            await AlarmActionHandler.perform(.snooze, reminderID: reminderID, alarmID: alarmID)
        case Self.optionsActionID, UNNotificationDefaultActionIdentifier:
            await AlarmActionHandler.perform(.snoozeOptions, reminderID: reminderID, alarmID: alarmID)
        case UNNotificationDismissActionIdentifier:
            await AlarmActionHandler.performStopAction(reminderID: reminderID, alarmID: alarmID)
        default:
            break
        }
    }
}
