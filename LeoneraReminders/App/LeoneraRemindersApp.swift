import SwiftUI

@main
struct LeoneraRemindersApp: App {
    @State private var store = ReminderStore.shared
    @State private var settings = SettingsStore.shared
    @State private var alarms = AlarmSyncService.shared
    @State private var groqKey = GroqKeyStore.shared
    @State private var calendarEvents = CalendarEventSource.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationDelivery.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ReminderListView()
                .environment(store)
                .environment(settings)
                .environment(alarms)
                .environment(groqKey)
                .environment(calendarEvents)
                .tint(.brand)
                .task { await alarms.start() }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .background, settings.settings.calendarAlarms.isEnabled {
                        CalendarEventSource.scheduleBackgroundRefresh()
                    }
                    guard phase == .active else { return }
                    // Access may have changed in Settings while the app was away.
                    calendarEvents.start()
                    // Ningún vencido se queda callado: vuelve a sonar en el siguiente minuto.
                    store.retryOverdue(ringing: alarms.alertingAlarmIDs)
                    alarms.requestSync()
                }
        }
        // Keeps the calendar event alarms a week ahead even if the app is not opened.
        .backgroundTask(.appRefresh(CalendarEventSource.refreshTaskID)) {
            await AlarmSyncService.shared.syncNow()
            if await SettingsStore.shared.settings.calendarAlarms.isEnabled {
                CalendarEventSource.scheduleBackgroundRefresh()
            }
        }
    }
}
