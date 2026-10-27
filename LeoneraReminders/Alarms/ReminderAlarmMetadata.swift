import AlarmKit
import Foundation

/// Datos que viajan con cada alarma de AlarmKit.
struct ReminderAlarmMetadata: AlarmMetadata {
    var reminderID: UUID
}

/// Data that travels with the alarm of an Apple Calendar event.
struct CalendarEventAlarmMetadata: AlarmMetadata {
    var eventTitle: String
    var eventStart: Date
}
