import Foundation

/// Una cantidad de tiempo expresada en una unidad de calendario ("10 min", "1 h", "1 día", "1 sem.").
/// Se usa para las opciones de posponer y para las filas de suma/resta de la matriz de ajuste rápido.
struct TimeAmount: Codable, Hashable, Sendable, Identifiable {
    enum Unit: String, Codable, CaseIterable, Sendable, Identifiable {
        case minute, hour, day, week, month

        var id: String { rawValue }

        var calendarComponent: Calendar.Component {
            switch self {
            case .minute: .minute
            case .hour: .hour
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            }
        }

        /// Etiqueta abreviada, igual para singular y plural ("min", "h", "sem.").
        func shortName(for value: Int) -> String {
            switch self {
            case .minute: "min"
            case .hour: "h"
            case .day: abs(value) == 1 ? "día" : "días"
            case .week: "sem."
            case .month: abs(value) == 1 ? "mes" : "meses"
            }
        }

        func longName(for value: Int) -> String {
            switch self {
            case .minute: abs(value) == 1 ? "minuto" : "minutos"
            case .hour: abs(value) == 1 ? "hora" : "horas"
            case .day: abs(value) == 1 ? "día" : "días"
            case .week: abs(value) == 1 ? "semana" : "semanas"
            case .month: abs(value) == 1 ? "mes" : "meses"
            }
        }

        /// Duración aproximada en segundos, sólo para ordenar.
        var approximateSeconds: TimeInterval {
            switch self {
            case .minute: 60
            case .hour: 3_600
            case .day: 86_400
            case .week: 604_800
            case .month: 2_629_746
            }
        }
    }

    /// Siempre positivo; el signo lo decide quien aplica la cantidad (sumar o restar).
    var value: Int
    var unit: Unit

    init(_ value: Int, _ unit: Unit) {
        self.value = max(1, abs(value))
        self.unit = unit
    }

    static func minutes(_ value: Int) -> TimeAmount { TimeAmount(value, .minute) }
    static func hours(_ value: Int) -> TimeAmount { TimeAmount(value, .hour) }
    static func days(_ value: Int) -> TimeAmount { TimeAmount(value, .day) }
    static func weeks(_ value: Int) -> TimeAmount { TimeAmount(value, .week) }

    var id: String { "\(value)\(unit.rawValue)" }

    var approximateSeconds: TimeInterval { Double(value) * unit.approximateSeconds }

    /// "10 min", "1 h", "2 días", "1 sem."
    var shortLabel: String { "\(value) \(unit.shortName(for: value))" }

    /// "10 minutos", "1 hora"
    var longLabel: String { "\(value) \(unit.longName(for: value))" }

    func added(to date: Date, sign: Int = 1, calendar: Calendar = .current) -> Date {
        let delta = sign >= 0 ? value : -value
        return calendar.date(byAdding: unit.calendarComponent, value: delta, to: date)
            ?? date.addingTimeInterval(Double(delta) * unit.approximateSeconds)
    }

    func subtracted(from date: Date, calendar: Calendar = .current) -> Date {
        added(to: date, sign: -1, calendar: calendar)
    }
}

extension TimeAmount: Comparable {
    static func < (lhs: TimeAmount, rhs: TimeAmount) -> Bool {
        lhs.approximateSeconds < rhs.approximateSeconds
    }
}

/// Hora del día (sin fecha), p. ej. 10:00.
struct TimeOfDay: Codable, Hashable, Sendable, Comparable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int = 0) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    init(of date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// "8:00", "21:30"
    var label: String { String(format: "%d:%02d", hour, minute) }

    /// La misma fecha (día) con esta hora.
    func applied(to date: Date, calendar: Calendar = .current) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: date)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        return calendar.date(from: parts) ?? date
    }

    /// Esta hora el día de `date`; si eso ya pasó, la próxima vez que llegue después de `now` (hoy o mañana).
    func nextOccurrence(from date: Date, now: Date, calendar: Calendar = .current) -> Date {
        let sameDay = applied(to: date, calendar: calendar)
        guard sameDay <= now else { return sameDay }
        let today = applied(to: now, calendar: calendar)
        guard today <= now else { return today }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return applied(to: tomorrow, calendar: calendar)
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}
