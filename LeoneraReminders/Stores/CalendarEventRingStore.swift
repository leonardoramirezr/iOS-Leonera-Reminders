import Foundation

/// Keeps the `CalendarEventRings` of the Apple Calendar events in `UserDefaults`, so that their repeats survive
/// a restart of the app.
@MainActor
final class CalendarEventRingStore {
    static let shared = CalendarEventRingStore()

    private static let key = "calendarEventRings.v1"
    private let defaults: UserDefaults
    private var stored: CalendarEventRings

    var rings: CalendarEventRings {
        get { stored }
        set {
            guard newValue != stored else { return }
            stored = newValue
            persist()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(CalendarEventRings.self, from: data) {
            stored = decoded
        } else {
            stored = CalendarEventRings()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
