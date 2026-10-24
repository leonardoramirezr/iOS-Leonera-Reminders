import Foundation
import Testing
@testable import ReminderCore

struct ReminderTests {
    @Test func completingOneOffReminderMarksItDone() {
        var reminder = Reminder(title: "Renovar seguro", dueDate: local(2026, 10, 10, 9))
        reminder.snooze(by: .minutes(10), now: local(2026, 10, 10, 9), calendar: mexico)
        reminder.complete(now: local(2026, 10, 10, 9, 5), calendar: mexico)
        #expect(reminder.isCompleted)
        #expect(reminder.dueDate == local(2026, 10, 10, 9, 10))
    }

    @Test func completingRepeatingReminderMovesToNextOccurrence() {
        var reminder = Reminder(
            title: "Lavar coche",
            dueDate: local(2026, 10, 11, 21),
            repeatRule: RepeatRule(frequency: .monthly, hour: 20, dayOfMonth: 7)
        )
        reminder.complete(now: local(2026, 10, 11, 21, 3), calendar: mexico)
        #expect(!reminder.isCompleted)
        #expect(reminder.dueDate == local(2026, 11, 7, 20))
        #expect(reminder.lastCompletedAt == local(2026, 10, 11, 21, 3))
    }

    @Test func completingLateSkipsMissedOccurrences() {
        var reminder = Reminder(
            title: "Vitaminas",
            dueDate: local(2026, 10, 10, 23),
            repeatRule: RepeatRule(frequency: .daily, hour: 23)
        )
        reminder.complete(now: local(2026, 10, 13, 8), calendar: mexico)
        #expect(reminder.dueDate == local(2026, 10, 13, 23))
    }

    @Test func completingEarlyGoesToTheFollowingOccurrence() {
        var reminder = Reminder(
            title: "Regar plantas",
            dueDate: local(2026, 10, 17, 8),
            repeatRule: RepeatRule(frequency: .weekly, hour: 8, weekdays: [7])
        )
        reminder.complete(now: local(2026, 10, 15, 12), calendar: mexico)
        #expect(reminder.dueDate == local(2026, 10, 24, 8))
    }

    @Test func snoozeMovesTheDueDateFromNow() {
        var reminder = Reminder(title: "Comprar fruta", dueDate: local(2026, 10, 16, 11))
        reminder.snooze(by: .minutes(20), now: local(2026, 10, 16, 11, 1), calendar: mexico)
        #expect(reminder.dueDate == local(2026, 10, 16, 11, 21))
        #expect(!reminder.isOverdue(now: local(2026, 10, 16, 11, 10)))
        #expect(reminder.isOverdue(now: local(2026, 10, 16, 11, 21)))
    }

    @Test func snoozingARepeatingReminderKeepsTheRule() {
        let rule = RepeatRule(frequency: .daily, hour: 21)
        var reminder = Reminder(title: "Pastilla", dueDate: local(2026, 10, 16, 21), repeatRule: rule)
        reminder.snooze(by: .minutes(10), now: local(2026, 10, 16, 21, 2), calendar: mexico)
        #expect(reminder.dueDate == local(2026, 10, 16, 21, 12))
        reminder.complete(now: local(2026, 10, 16, 21, 13), calendar: mexico)
        #expect(reminder.repeatRule == rule)
        #expect(reminder.dueDate == local(2026, 10, 17, 21))
    }

    /// Antes posponer guardaba otra hora sin tocar la fecha límite; al leerlo, esa hora pasa a ser la fecha límite.
    @Test func decodesLegacySnoozeAsTheDueDate() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Hola","dueDate":0,"snoozedUntil":600}"#
        let reminder = try JSONDecoder().decode(Reminder.self, from: Data(json.utf8))
        #expect(reminder.dueDate == Date(timeIntervalSinceReferenceDate: 600))
        let encoded = String(decoding: try JSONEncoder().encode(reminder), as: UTF8.self)
        #expect(!encoded.contains("snoozedUntil"))
    }

    @Test func rescheduleClearsSnoozeAndCompletion() {
        var reminder = Reminder(title: "Algo", dueDate: local(2026, 10, 16, 11))
        reminder.snooze(by: .hours(1), now: local(2026, 10, 16, 11), calendar: mexico)
        reminder.complete(now: local(2026, 10, 16, 11), calendar: mexico)
        reminder.reschedule(to: local(2026, 10, 18, 10))
        #expect(!reminder.isCompleted)
        #expect(reminder.dueDate == local(2026, 10, 18, 10))
    }

    @Test func advancePastDueRepetitionOnlyTouchesOverdueRepeatingReminders() {
        let now = local(2026, 10, 11, 9)
        var overdue = Reminder(title: "Fotos", dueDate: local(2026, 10, 10, 21),
                               repeatRule: RepeatRule(frequency: .weekly, hour: 8, weekdays: [7]))
        let overdueChanged = overdue.advancePastDueRepetition(now: now, calendar: mexico)
        #expect(overdueChanged)
        #expect(overdue.dueDate == local(2026, 10, 17, 8))

        var oneOff = Reminder(title: "Una vez", dueDate: local(2026, 10, 10, 21))
        let oneOffChanged = oneOff.advancePastDueRepetition(now: now, calendar: mexico)
        #expect(!oneOffChanged)

        var future = Reminder(title: "Futuro", dueDate: local(2026, 10, 12, 8),
                              repeatRule: RepeatRule(frequency: .daily, hour: 8))
        let futureChanged = future.advancePastDueRepetition(now: now, calendar: mexico)
        #expect(!futureChanged)
        #expect(future.dueDate == local(2026, 10, 12, 8))
    }

    @Test func decodesOlderDataWithoutOptionalFields() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Hola","dueDate":0}"#
        let reminder = try JSONDecoder().decode(Reminder.self, from: Data(json.utf8))
        #expect(reminder.title == "Hola")
        #expect(reminder.repeatRule == nil)
        #expect(reminder.scheduledAlarms.isEmpty)
    }

    @Test func decodesLegacySingleAlarmAndRoundTrips() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Hola","dueDate":0,"scheduledAlarm":{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FE","fireDate":0,"signature":"x"}}"#
        let reminder = try JSONDecoder().decode(Reminder.self, from: Data(json.utf8))
        #expect(reminder.scheduledAlarms.map(\.signature) == ["x"])
        let again = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(reminder))
        #expect(again == reminder)
    }

    @Test func overdueRemindersRingAgainAtTheNextMinute() {
        let followUp = FollowUpSettings(isEnabled: true, interval: .minutes(1), count: 3)
        var reminder = Reminder(title: "Pastilla", dueDate: local(2026, 10, 16, 21))
        let now = local(2026, 10, 16, 23, 40).addingTimeInterval(25) // 23:40:25, ya sin repeticiones pendientes
        let changed1 = reminder.retryIfOverdue(now: now, followUp: followUp, calendar: mexico)
        #expect(changed1)
        #expect(reminder.isOverdue(now: now)) // sigue en "Vencidos"
        #expect(reminder.pendingAlarmDates(after: now, followUp: followUp, calendar: mexico)
            == [local(2026, 10, 16, 23, 41), local(2026, 10, 16, 23, 42), local(2026, 10, 16, 23, 43), local(2026, 10, 16, 23, 44)])
        // Si ya va a sonar en el siguiente minuto, no se mueve.
        let stable = reminder
        let changed2 = reminder.retryIfOverdue(now: now.addingTimeInterval(10), followUp: followUp, calendar: mexico)
        #expect(!changed2)
        #expect(reminder == stable)
        // Con repeticiones aún pendientes al minuto siguiente tampoco cambia.
        var recent = Reminder(title: "Otro", dueDate: local(2026, 10, 16, 21))
        let changed3 = recent.retryIfOverdue(now: local(2026, 10, 16, 21, 1).addingTimeInterval(5), followUp: followUp, calendar: mexico)
        #expect(!changed3)
        // No vencido: nada. Al completar o posponer se olvida el reintento.
        var future = Reminder(title: "Futuro", dueDate: local(2026, 10, 17, 9))
        let changed4 = future.retryIfOverdue(now: now, followUp: followUp, calendar: mexico)
        #expect(!changed4)
        reminder.snooze(by: .minutes(5), now: now, calendar: mexico)
        #expect(reminder.retryFrom == nil)
    }

    @Test func pendingAlarmDatesIncludeFollowUps() {
        let reminder = Reminder(title: "Pastilla", dueDate: local(2026, 10, 16, 21))
        let followUp = FollowUpSettings(isEnabled: true, interval: .minutes(1), count: 3)
        #expect(reminder.pendingAlarmDates(after: local(2026, 10, 16, 20), followUp: followUp, calendar: mexico)
            == [local(2026, 10, 16, 21), local(2026, 10, 16, 21, 1), local(2026, 10, 16, 21, 2), local(2026, 10, 16, 21, 3)])
        // Ya sonó la principal y se ignoró: sólo quedan las repeticiones futuras.
        #expect(reminder.pendingAlarmDates(after: local(2026, 10, 16, 21, 1), followUp: followUp, calendar: mexico)
            == [local(2026, 10, 16, 21, 2), local(2026, 10, 16, 21, 3)])
        // Pospuesto: las repeticiones cuentan desde la nueva hora.
        var snoozed = reminder
        snoozed.snooze(by: .minutes(10), now: local(2026, 10, 16, 21, 1), calendar: mexico)
        #expect(snoozed.pendingAlarmDates(after: local(2026, 10, 16, 21, 1), followUp: followUp, calendar: mexico).first
            == local(2026, 10, 16, 21, 11))
        var off = followUp
        off.isEnabled = false
        #expect(reminder.pendingAlarmDates(after: local(2026, 10, 16, 20), followUp: off, calendar: mexico) == [local(2026, 10, 16, 21)])
        var done = reminder
        done.complete(now: local(2026, 10, 16, 20), calendar: mexico)
        #expect(done.pendingAlarmDates(after: local(2026, 10, 16, 20), followUp: followUp, calendar: mexico).isEmpty)
    }
}

struct QuickAdjustGridTests {
    let grid = QuickAdjustGrid.default
    let start = local(2026, 10, 16, 11, 7)

    @Test func defaultLayoutMatchesTheRequestedMatrix() {
        let labels = grid.rows.map { row in row.map { "\($0.labelParts.value) \($0.labelParts.unit)".trimmingCharacters(in: .whitespaces) } }
        #expect(labels == [
            ["10:00", "14:00", "18:00", "21:00"],
            ["+10 min", "+1 h", "+1 día", "+1 sem."],
            ["−10 min", "−1 h", "−1 día", "−1 sem."],
        ])
    }

    @Test func cellsAdjustTheDate() {
        let rows = grid.rows
        #expect(rows[0][0].apply(to: start, calendar: mexico) == local(2026, 10, 16, 10, 0))
        #expect(rows[0][3].apply(to: start, calendar: mexico) == local(2026, 10, 16, 21, 0))
        #expect(rows[1][0].apply(to: start, calendar: mexico) == local(2026, 10, 16, 11, 17))
        #expect(rows[1][2].apply(to: start, calendar: mexico) == local(2026, 10, 17, 11, 7))
        #expect(rows[1][3].apply(to: start, calendar: mexico) == local(2026, 10, 23, 11, 7))
        #expect(rows[2][1].apply(to: start, calendar: mexico) == local(2026, 10, 16, 10, 7))
        #expect(rows[2][3].apply(to: start, calendar: mexico) == local(2026, 10, 9, 11, 7))
    }

    @Test func overdueAdditionsCanCountFromNow() {
        let rows = grid.rows
        let now = local(2026, 10, 16, 14, 1)
        // Por defecto suma a la fecha límite aunque ya haya pasado.
        #expect(rows[1][0].apply(to: start, now: now, calendar: mexico) == local(2026, 10, 16, 11, 17))
        // Desde ahora: sólo cambian las sumas, y sólo si ya venció.
        #expect(rows[1][0].apply(to: start, now: now, overdueBase: .now, calendar: mexico) == local(2026, 10, 16, 14, 11))
        #expect(rows[1][1].apply(to: start, now: now, overdueBase: .now, calendar: mexico) == local(2026, 10, 16, 15, 1))
        #expect(rows[2][0].apply(to: start, now: now, overdueBase: .now, calendar: mexico) == local(2026, 10, 16, 10, 57))
        #expect(rows[0][3].apply(to: start, now: now, overdueBase: .now, calendar: mexico) == local(2026, 10, 16, 21, 0))
        // Desde ahora: una hora fija que ya pasó se va al día siguiente.
        #expect(rows[0][0].apply(to: start, now: now, overdueBase: .now, calendar: mexico) == local(2026, 10, 17, 10, 0))
        #expect(rows[0][0].apply(to: start, now: now, calendar: mexico) == local(2026, 10, 16, 10, 0))
        let daysAgo = local(2026, 10, 12, 9)
        #expect(rows[0][2].apply(to: daysAgo, now: now, overdueBase: .now, calendar: mexico) == local(2026, 10, 16, 18, 0))
        #expect(rows[0][1].apply(to: daysAgo, now: now, overdueBase: .now, calendar: mexico) == local(2026, 10, 17, 14, 0))
        let future = local(2026, 10, 16, 18)
        #expect(rows[1][0].apply(to: future, now: now, overdueBase: .now, calendar: mexico) == local(2026, 10, 16, 18, 10))
    }

    @Test func setCellReplacesOnlyThatCell() {
        var custom = QuickAdjustGrid(times: [], additions: [.minutes(5)], subtractions: [])
        custom.setCell(.setTime(TimeOfDay(hour: 7, minute: 30)), column: 2)
        custom.setCell(.subtract(.days(3)), column: 3)
        custom.setCell(.add(.hours(9)), column: 7)
        #expect(custom.times == [TimeOfDay(hour: 10), TimeOfDay(hour: 14), TimeOfDay(hour: 7, minute: 30), TimeOfDay(hour: 21)])
        #expect(custom.additions == [.minutes(5), .hours(1), .days(1), .weeks(1)])
        #expect(custom.subtractions == [.minutes(10), .hours(1), .days(1), .days(3)])
    }

    @Test func shortArraysArePaddedWithDefaults() {
        let custom = QuickAdjustGrid(times: [TimeOfDay(hour: 7, minute: 30)], additions: [], subtractions: [.days(2)])
        #expect(custom.rows.map(\.count) == [4, 4, 4])
        #expect(custom.rows[0][0] == .setTime(TimeOfDay(hour: 7, minute: 30)))
        #expect(custom.rows[0][1] == .setTime(TimeOfDay(hour: 14)))
        #expect(custom.rows[2][0] == .subtract(.days(2)))
    }
}

struct AppSettingsTests {
    @Test func defaultsMatchTheRequestedSnoozeOptions() {
        #expect(AppSettings.default.sortedSnoozeOptions.map(\.shortLabel)
            == ["1 min", "5 min", "10 min", "20 min", "40 min", "60 min", "2 h", "3 h"])
        #expect(AppSettings.default.stopAction == .snooze)
        #expect(AppSettings.default.secondaryAction == .snoozeOptions)
    }

    @Test func decodingMissingKeysFallsBackToDefaults() throws {
        let json = #"{"defaultSnooze":{"value":5,"unit":"minute"},"stopAction":"snooze"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.defaultSnooze == .minutes(5))
        #expect(settings.stopAction == .snooze)
        #expect(settings.secondaryAction == AppSettings.default.secondaryAction)
        #expect(settings.quickAdjustGrid == .default)
        #expect(settings.overdueAdditionBase == .dueDate)
    }

    @Test func overdueAdditionBaseRoundTrips() throws {
        var settings = AppSettings.default
        settings.overdueAdditionBase = .now
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.overdueAdditionBase == .now)
    }

    /// Antes «Detener» podía completar; esa opción ya no existe y se vuelve al valor por defecto.
    @Test func legacyCompleteActionFallsBackToDefaults() throws {
        let json = #"{"stopAction":"complete","secondaryAction":"complete"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.stopAction == .snooze)
        #expect(settings.secondaryAction == .snoozeOptions)
    }

    @Test func soundAndSilentModeRoundTripAndAffectTheAlarm() throws {
        var settings = AppSettings.default
        #expect(settings.sound == .bell)
        #expect(settings.ignoresSilentMode)
        let before = settings.alarmSignature
        settings.sound = .silent
        settings.ignoresSilentMode = false
        #expect(settings.alarmSignature != before)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(AlarmSound.system.fileName == nil)
        #expect(AlarmSound.allCases.compactMap(\.fileName).count == AlarmSound.allCases.count - 1)
    }

    @Test func swipeCompleteDirectionDefaultsToRightToLeftAndRoundTrips() throws {
        #expect(AppSettings.default.swipeCompleteDirection == .rightToLeft)
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"stopAction":"snooze"}"#.utf8))
        #expect(legacy.swipeCompleteDirection == .rightToLeft)
        var settings = AppSettings.default
        settings.swipeCompleteDirection = .leftToRight
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.swipeCompleteDirection == .leftToRight)
    }

    @Test func celebratesCompletionDefaultsToOnAndRoundTrips() throws {
        #expect(AppSettings.default.celebratesCompletion)
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"stopAction":"snooze"}"#.utf8))
        #expect(legacy.celebratesCompletion)
        var settings = AppSettings.default
        settings.celebratesCompletion = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(!decoded.celebratesCompletion)
    }

    @Test func fireworksInteractionDefaultsToBlockingAndRoundTrips() throws {
        #expect(AppSettings.default.fireworksInteraction == .blocksApp)
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"stopAction":"snooze"}"#.utf8))
        #expect(legacy.fireworksInteraction == .blocksApp)
        var settings = AppSettings.default
        settings.fireworksInteraction = .tapToFinish
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.fireworksInteraction == .tapToFinish)
    }

    @Test func sortedSnoozeOptionsRemovesDuplicates() {
        var settings = AppSettings.default
        settings.snoozeOptions = [.hours(1), .minutes(5), .hours(1), .minutes(1)]
        #expect(settings.sortedSnoozeOptions == [.minutes(1), .minutes(5), .hours(1)])
    }
}
