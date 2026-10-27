import Foundation
import Observation

/// Configuración de la app, guardada en `UserDefaults`.
@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private static let key = "appSettings.v1"
    private let defaults: UserDefaults
    private var stored: AppSettings

    var settings: AppSettings {
        get { stored }
        set {
            var value = newValue
            if value.snoozeOptions.isEmpty { value.snoozeOptions = [value.defaultSnooze] }
            if !value.snoozeOptions.contains(value.defaultSnooze) {
                value.defaultSnooze = value.sortedSnoozeOptions.first ?? AppSettings.default.defaultSnooze
            }
            guard value != stored else { return }
            let alarmsChanged = value.alarmSignature != stored.alarmSignature || value.followUp != stored.followUp
                || value.calendarAlarms != stored.calendarAlarms
            stored = value
            persist()
            if alarmsChanged { AlarmSyncService.shared.requestSync() }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            stored = decoded
        } else {
            stored = .default
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
